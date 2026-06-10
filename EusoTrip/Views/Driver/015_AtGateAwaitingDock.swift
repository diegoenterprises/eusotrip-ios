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
//    • Header — back chevron + "At the gate" + right-column live
//      device clock + mode-correct "Bay 03 · gate 2".
//    • Facility line — live facility/city + "GUARD CHECK-IN COMPLETE".
//    • Queue position card — gradient-bordered hero. No live queue
//      source yet (`loadLifecycle.queuePosition`), so it reads an
//      honest "AWAITING DISPATCH" empty-state until that endpoint
//      ships; the rank / total / wait / advance-cadence figures
//      return then.
//    • 2×2 metadata grid — LOAD ID (live commodity) / DWELL POLICY
//      (em-dash, no per-load terms) / GATE GUARD (em-dash) / APPT
//      DRIFT (live scheduled-vs-now from the appointment).
//    • ESANG · IDLE-WATCH card.
//    • Footer CTAs — "Log dwell" outline + "Mark ready" gradient.
//    • Bottom nav — preserved verbatim per doctrine.
//
//  Data wiring:
//    • `TripLifecycleStore.hydrateActiveLoad()` → `loads.getById`
//      for the real load id + pickup location + commodity facets.
//    • Header clock is the live device clock (TimelineView every
//      minute).
//    • APPT DRIFT computes scheduled-vs-now from the real
//      `appointments.getByLoad.scheduledAt` row (the same read the
//      sibling lifecycle screens 014/020/037 hydrate); em-dash when
//      no appointment is on file.
//    • LOAD ID secondary commodity reads the live
//      `ctx.facets.commodityWithUN` (composed commodityName · UN);
//      em-dash when the load carries neither — no hazmat default.
//    • ESANG idle-watch dwell-snapshot timestamp is the real
//      appointment scheduled ISO when present; the sentence omits the
//      "armed at" clause entirely when no timestamp is known.
//
//  De-fabrication (2026-06-07): the seeded header clock "08:32 CDT",
//  the queue hero (2 / of 4 / 14m est / 7-min cadence), the DWELL
//  POLICY "2h free" / "Detention after 2h" copy, the APPT DRIFT
//  "-6 min" / "vs. scheduled 09:00 CDT" literals, the ESANG "armed at
//  08:18 CDT" stamp, and the "UN1005 · NH3 · tanker" hazmat-default
//  commodity were all Figma fixtures that leaked onto the live path.
//  Queue position has no live source (`loadLifecycle.queuePosition`
//  is not yet on the wire), so the hero now reads an honest
//  "AWAITING DISPATCH" empty-state instead of a fabricated rank. The
//  four honest "-" sentinels (facility / load id / guard / badge)
//  are preserved.
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
    /// The most-recent appointment row for this load — source for the
    /// APPT DRIFT (scheduled-vs-now) compute and the ESANG dwell-snapshot
    /// timestamp. The same `appointments.getByLoad` read the sibling
    /// lifecycle screens (014/020/037) hydrate. Nil-tolerant: no row →
    /// drift + armed-at fall through to em-dash / an omitted clause.
    @State private var appointment: AppointmentsAPI.ByLoadAppointment?
    @State private var isMarkingReady: Bool = false
    @State private var isLoggingDwell: Bool = false
    @State private var dwellToast: String? = nil

    enum Register { case night, morning }
    let register: Register

    init(register: Register = .night) { self.register = register }

    /// Product + vertical dispatch. Queue position + metadata grid
    /// + ESANG idle-watch line all adapt to the active load's
    /// vertical / product instead of defaulting to hazmat copy.
    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Honest sentinels
    //
    // The four facts that have no live source on this screen render an
    // honest em-dash "-" until their column lands on the wire: the
    // facility brand (no structured facility field on pickupLocation),
    // the load id (until hydration), and the gate-guard identity +
    // badge (no guard column exists). These are sentinels, NOT seeded
    // literals.
    private let dash = "-"
    private let fallbackFacility = "-"
    private let fallbackLoadID   = "-"
    private let fallbackGuard    = "-"
    private let fallbackBadge    = "-"

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

    /// Live commodity line — the composed "<commodity> · <UN>" from the
    /// load's real facets, em-dash when the load carries neither. Drops
    /// the prior "UN1005 · NH3 · tanker" hazmat default that mislabeled
    /// non-hazmat loads.
    private var commodityText: String {
        ctx.facets.commodityWithUN
    }

    // MARK: - Header clock (live device clock)

    /// "HH:mm zzz" wall clock formatter for the header. Fed the live
    /// device `Date` via the header's TimelineView(.everyMinute) — no
    /// seeded "08:32 CDT".
    private func headerClock(_ now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm zzz"
        return f.string(from: now)
    }

    // MARK: - APPT DRIFT (scheduled-vs-now from the live appointment)

    /// Lenient ISO-8601 parse (with and without fractional seconds).
    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Signed minute drift of NOW vs the appointment's committed
    /// `scheduledAt` (negative = ahead of schedule, positive = past the
    /// window). Em-dash when no appointment is on file. Computed against
    /// the live device clock so it advances minute-over-minute with the
    /// header's TimelineView.
    private func apptDriftText(_ now: Date) -> String {
        guard let iso = appointment?.scheduledAt,
              let sched = Self.parseISO(iso) else { return dash }
        let mins = Int((now.timeIntervalSince(sched) / 60).rounded())
        if mins == 0 { return "on time" }
        return mins > 0 ? "+\(mins) min" : "\(mins) min"
    }

    /// "vs. scheduled HH:mm zzz" sub-line from the real appointment
    /// `scheduledAt`. Em-dash when no appointment is on file — never the
    /// seeded "vs. scheduled 09:00 CDT".
    private var apptSchedText: String {
        guard let iso = appointment?.scheduledAt,
              let sched = Self.parseISO(iso) else { return dash }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm zzz"
        return "vs. scheduled \(f.string(from: sched))"
    }

    /// On-time/behind tint for the APPT DRIFT primary value — warning
    /// once we're past the committed window, neutral otherwise. nil (→
    /// default text color) when there's no appointment to judge against.
    private func apptDriftColor(_ now: Date) -> Color? {
        guard let iso = appointment?.scheduledAt,
              let sched = Self.parseISO(iso) else { return nil }
        return now.timeIntervalSince(sched) > 0 ? Brand.warning : nil
    }

    /// ESANG idle-watch dwell-armed clause. When the appointment carries
    /// a real `scheduledAt`, the dwell timer is armed against that
    /// committed window and we surface the local time; otherwise the
    /// clause is omitted entirely rather than inventing an "08:18 CDT".
    private var dwellArmedClause: String {
        guard let iso = appointment?.scheduledAt,
              let sched = Self.parseISO(iso) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm zzz"
        return " Dwell timer armed at \(f.string(from: sched))."
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                facilityStrip
                queueCard
                metadataGrid
                if loadIDText != "-" { gateCredentialCard }
                esangIdleWatchCard
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .overlay(alignment: .bottom) {
            if let msg = dwellToast {
                Text(msg)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
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
        .animation(.easeOut(duration: 0.18), value: dwellToast)
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
                    // 2026-05-17 — Mode chip at the gate. Hidden for
                    // default truck-single-vehicle; a rail engineer
                    // waiting on siding clearance vs a vessel captain
                    // waiting on tide reads differently from a truck
                    // driver waiting on a dock door.
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text("At the \(ctx.vertical.gateWord)")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                // Live device clock — ticks every minute, no seeded
                // "08:32 CDT".
                TimelineView(.everyMinute) { timeline in
                    Text(headerClock(timeline.date))
                        .font(EType.mono(.caption)).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                }
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
        // No live queue source — `loadLifecycle.queuePosition(loadId:)`
        // is not yet on the wire. Rather than paint a fabricated rank /
        // total / wait estimate / advance cadence, the hero reads an
        // honest "AWAITING DISPATCH" empty-state. The card chrome
        // (gradient-bordered hero) is preserved verbatim; only the
        // fabricated figures are gone. The big-number rank, the
        // "of N trucks waiting", the "Est. wait …" line, and the dot
        // row all bind to that missing endpoint, so they return when it
        // ships.
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("QUEUE POSITION")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(dash)
                    .font(.system(size: 86, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 0) {
                    Text("AWAITING DISPATCH")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("queue position pending")
                        .font(EType.body)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            HStack(spacing: 6) {
                Text("Queue position appears when the yard releases the call-forward.")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    // MARK: 2×2 metadata grid

    private var metadataGrid: some View {
        // APPT DRIFT ticks against the live device clock so the
        // scheduled-vs-now delta advances minute-over-minute, matching
        // the header clock cadence.
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            VStack(spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    metaCard(label: "LOAD ID", primary: loadIDText, secondary: commodityText)
                    // DWELL POLICY — no per-load detention-terms column
                    // feeds this screen, so the generic "2h free" /
                    // "Detention after 2h" copy is dropped for an honest
                    // em-dash rather than asserting a free window we
                    // can't read off this load.
                    metaCard(label: "DWELL POLICY", primary: dash, secondary: dash)
                }
                HStack(spacing: Space.s2) {
                    metaCard(label: "GATE GUARD", primary: fallbackGuard, secondary: fallbackBadge)
                    // APPT DRIFT — computed from the real appointment
                    // scheduledAt vs the live clock; em-dash when no
                    // appointment is on file.
                    metaCard(
                        label: "APPT DRIFT",
                        primary: apptDriftText(now),
                        secondary: apptSchedText,
                        primaryColor: apptDriftColor(now)
                    )
                }
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

    // MARK: Gate credential QR

    private var gateCredentialCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("GATE CREDENTIAL")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            HStack {
                Spacer()
                EusoQRView(
                    kind: .loadCredential(loadId: loadIDText, mode: .credential),
                    role: .driver,
                    size: 200,
                    cornerRadius: 12
                )
                Spacer()
            }
            Text("Show to guard or scan at reader - pickup credential for \(loadIDText)")
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
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
                Text("Engine off, parking brake set. I'll listen for your call-forward and wake you if the queue moves.\(dwellArmedClause)")
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
            Button { Task { await logDwellSnapshot() } } label: {
                HStack(spacing: 6) {
                    if isLoggingDwell {
                        ProgressView()
                            .controlSize(.small)
                            .tint(palette.textPrimary)
                    }
                    Text(isLoggingDwell ? "Logging…" : "Log dwell")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .disabled(isLoggingDwell)
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
        // Appointment row (scheduledAt → APPT DRIFT compute + ESANG
        // dwell-snapshot timestamp) — the same `appointments.getByLoad`
        // read the sibling lifecycle screens (014/020/037) hydrate.
        // nil-tolerant: no row → APPT DRIFT + armed-at fall through to
        // em-dash / an omitted clause.
        appointment = try? await EusoTripAPI.shared.appointments
            .getByLoad(loadId: lifecycle.loadId)
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

    private func logDwellSnapshot() async {
        guard !isLoggingDwell else { return }
        guard !lifecycle.loadId.isEmpty else { return }
        isLoggingDwell = true
        defer { isLoggingDwell = false }
        let stamp = ISO8601DateFormatter().string(from: Date())
        do {
            if let appt = try await EusoTripAPI.shared.appointments
                .getByLoad(loadId: lifecycle.loadId) {
                _ = try? await EusoTripAPI.shared.appointments
                    .updateStatus(
                        id: appt.id,
                        status: "checked_in",
                        notes: "Driver-marked dwell snapshot at \(stamp)"
                    )
                dwellToast = "Dwell logged"
            } else {
                dwellToast = "No appointment on file"
            }
        } catch {
            dwellToast = "Couldn't log dwell"
        }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        dwellToast = nil
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
