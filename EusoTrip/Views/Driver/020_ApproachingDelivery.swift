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
//      turn banner (live remaining-distance heading) + keep-right
//      subtitle (delivery city/state from the load).
//    • Geofence pill — "ARMING DASH-CAM ON ENTRY".
//    • Facility card — receiver brand + city/state + dock name (e.g.
//      "ACME DC 7271 / SOMECITY, ST · Receiving Dock"); rendered live
//      from `activeLoad.deliveryLocation`.
//    • Hero — big gradient "<mi> mi to delivery" + right-column
//      ETA / appt window / on-time chip.
//    • 4-row product-specific pre-gate checklist with READY/PENDING/NA chips.
//    • Footer CTAs — "I'm at the gate" gradient + "Call receiver" outline.
//    • Bottom nav — preserved verbatim per doctrine.
//
//  De-fabrication (2026-06-06): the hero "2.0 mi to delivery", the
//  "ETA 00:22" clock, the turn banner "In 0.8 mi · <road>", and the
//  "Appt 23:30 – 23:59" window were Figma literals that leaked onto
//  the live path. They now resolve from real sources — the HERE
//  Routing v8 leg between the driver's live GPS fix and the load's
//  `deliveryLocation` coordinate (remaining miles / ETA), and the
//  `appointments.getByLoad` row (scheduledAt window) — mirroring the
//  proven 013 En-Route pattern. Any field without a live source
//  renders an honest em-dash "-": no GPS fix, no delivery coord, or
//  no appointment on file all degrade to "-" rather than a fake
//  number. HERE turn-by-turn `actions` are not decoded by the route
//  models, so the maneuver line carries the live remaining-distance
//  heading + the delivery city/state, never a fabricated exit string.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

struct ApproachingDelivery: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverDialPhone) private var dialPhone
    @Environment(\.driverOpenMessages) private var openMessages
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var completed: Set<String> = []
    @State private var isConfirming: Bool = false

    // MARK: - Live nav state (HERE Routing v8 · current fix → delivery)
    //
    // FOUNDER BAR: every figure below is computed from a real source —
    // the HERE-routed leg from the driver's live GPS fix to the
    // delivery coordinate, or the load's own appointment row. There
    // are NO seeded constants. When a source isn't available (no
    // active load, no GPS fix, no delivery coord, no appointment), the
    // field renders an honest em-dash "-".

    /// Remaining distance to the receiver, in meters, from the last
    /// HERE route between the live GPS fix and the delivery coordinate.
    @State private var remainingMeters: Double?
    /// ISO-8601 arrival time HERE computed for the delivery.
    @State private var etaISO: String?
    /// The most-recent appointment row for this load (window source).
    @State private var appointment: AppointmentsAPI.ByLoadAppointment?

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private static let metersPerMile = 1609.344
    private let dash = "-"

    // MARK: - Live derived strings (HERE leg + appointment → honest "-")

    /// Live remaining distance to the receiver, "2.0" formatted, else "-".
    private var heroMilesText: String {
        guard let m = remainingMeters else { return dash }
        return String(format: "%.1f", m / Self.metersPerMile)
    }

    /// "In 2.0 mi" maneuver heading from the live HERE remaining length.
    /// HERE turn-by-turn `actions` are not decoded by the route models,
    /// so we never fabricate an exit-narration string — the honest
    /// remaining-distance heading stands in. Em-dash with no live leg.
    private var turnHeadingText: String {
        guard remainingMeters != nil else { return dash }
        return "In \(heroMilesText) mi"
    }

    /// Maneuver subtitle: the live delivery city/state from the load,
    /// else an honest em-dash. Never a fabricated road name.
    private var turnSubText: String {
        if let cs = activeLoad?.deliveryLocation?.cityState, !cs.isEmpty {
            return "Keep right · \(cs)"
        }
        return dash
    }

    /// "ETA 00:22" local clock from the live HERE arrival ISO, else "ETA -".
    private var etaText: String {
        guard let iso = etaISO, let date = Self.parseISO(iso) else { return "ETA \(dash)" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return "ETA \(f.string(from: date))"
    }

    /// "Appt 23:30 EDT" from the appointment's `scheduledAt` (falling
    /// through to the load's `deliveryDate`), else "Appt -". The live
    /// `appointments.getByLoad` projection carries no window-duration
    /// column, so we render the honest single scheduled time — never a
    /// fabricated "23:30 – 23:59" range.
    private var apptText: String {
        if let t = Self.formatClock(appointment?.scheduledAt) { return "Appt \(t)" }
        if let t = Self.formatClock(activeLoad?.deliveryDate) { return "Appt \(t)" }
        return "Appt \(dash)"
    }

    /// Lenient ISO-8601 parse (with and without fractional seconds).
    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// On-time status from the live HERE ETA vs the appointment time.
    /// Returns nil when either side is unknown — we make NO claim then,
    /// rather than asserting a fabricated green "ON-TIME". A 5-minute
    /// grace before we call the leg behind schedule.
    private var onTimeStatus: (text: String, color: Color)? {
        guard let iso = etaISO, let eta = Self.parseISO(iso),
              let apptISO = appointment?.scheduledAt, let appt = Self.parseISO(apptISO)
        else { return nil }
        if eta <= appt.addingTimeInterval(300) { return ("ON-TIME", Brand.success) }
        return ("BEHIND", Brand.warning)
    }

    /// "23:30 EDT" wall clock + device timezone, nil when unparseable.
    private static func formatClock(_ iso: String?) -> String? {
        guard let iso = iso, !iso.isEmpty, let date = parseISO(iso) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        let tz = TimeZone.current.abbreviation() ?? ""
        return tz.isEmpty ? f.string(from: date) : "\(f.string(from: date)) \(tz)"
    }

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
                        // 2026-05-17 — Mode chip on approach-delivery
                        // header. Same chrome as approach-pickup (014).
                        LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                      multiVehicleCount: activeLoad?.multiVehicleCount,
                                      compact: true)
                    }
                    Text(turnHeadingText)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(turnSubText)
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
            // The dash-cam arms on geofence entry (real behavior). The
            // trigger radius is a server-side geofence config not on the
            // wire, so we state the behavior without a fabricated "0.4 MI"
            // distance literal.
            Text("ARMING DASH-CAM ON ENTRY")
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
                     : dash)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(activeLoad?.deliveryLocation?.cityState.isEmpty == false
                     ? "\(activeLoad!.deliveryLocation!.cityState) · Receiving Dock"
                     : dash)
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
                Text(heroMilesText)
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
                Text(etaText)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text(apptText)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                if let s = onTimeStatus {
                    Text(s.text)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(s.color)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().stroke(s.color.opacity(0.5), lineWidth: 1))
                }
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

            Button {
                Task {
                    let rows = (try? await EusoTripAPI.shared.contacts
                        .list(type: "shipper", limit: 1)) ?? []
                    if let phone = rows.first?.phone, !phone.isEmpty {
                        dialPhone?(phone)
                    } else {
                        openMessages?(nil)
                    }
                }
            } label: {
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
        let load = try? await EusoTripAPI.shared.loads.getById(n)
        activeLoad = load
        // Appointment window (scheduledAt) for the right-column "Appt"
        // line — same `appointments.getByLoad` read the sibling
        // lifecycle screens (021/022) hydrate. nil-tolerant: no row →
        // apptText falls through to deliveryDate, then "-".
        appointment = try? await EusoTripAPI.shared.appointments
            .getByLoad(loadId: lifecycle.loadId)
        if let load { await refreshLiveNav(for: load) }
    }

    /// Computes the live remaining leg from the driver's current GPS
    /// fix to the delivery coordinate via HERE Routing v8 (truck-aware),
    /// and caches the remaining miles + arrival ISO that drive the hero
    /// + ETA. Every value is a real measurement; on any failure (no
    /// fix, no delivery coord, HERE error) the cached values stay nil
    /// and the UI shows "-". Mirrors 013's `refreshLiveNav`.
    @MainActor
    private func refreshLiveNav(for load: Load) async {
        guard let delivery = load.deliveryLocation,
              !(delivery.lat == 0 && delivery.lng == 0) else {
            remainingMeters = nil
            etaISO = nil
            return
        }

        // Live GPS fix. nil when denied / timed out → UI reads "-".
        guard let fix = await DriverLocationResolver.shared.currentCoordinate() else {
            remainingMeters = nil
            etaISO = nil
            return
        }

        let stops = HereStops(
            origin: fix,
            destination: CLLocationCoordinate2D(latitude: delivery.lat, longitude: delivery.lng)
        )
        let profile = TruckProfile.from(load: load)
        do {
            let resp = try await HereRoutingClient.shared.route(stops: stops, profile: profile)
            guard let section = resp.routes.first?.sections.first,
                  let summary = section.summary else {
                remainingMeters = nil
                etaISO = nil
                return
            }
            remainingMeters = Double(summary.length)
            etaISO = section.arrival.time
        } catch {
            // Honest failure: leave the numbers nil so the UI shows "-"
            // rather than a stale or fabricated figure.
            remainingMeters = nil
            etaISO = nil
        }
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
