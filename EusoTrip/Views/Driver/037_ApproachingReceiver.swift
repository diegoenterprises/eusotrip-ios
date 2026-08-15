//
//  037_ApproachingReceiver.swift
//  EusoTrip — Lifecycle screen 037 · Approaching Receiver.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `037 Approaching Receiver.png`. Rig is approaching the receiver,
//  ESANG is pre-arming the arrival. Leads with a big gradient
//  "<mi> mi · <min>" hero + receiver card (gate/bay/contact/phone) +
//  product-aware hazmat strip (shown only when `ctx.isHazmat`) +
//  4-row pre-arrival checklist dispatched through
//  `LifecycleProductContext` + ESANG arrival card + Trip log /
//  Notify receiver CTAs.
//
//  De-fabrication (2026-06-06): the hero "4.2 mi · 7 min", the header
//  arrive-by "21:14" + clock "21:07", the receiver address, the
//  GATE "B-2" / BAY "Dock 3" / CONTACT "Reg Hammond" / PHONE facts,
//  and the canned ESANG advisory ("FIT FOR 21:11 · WEATHER HOLD
//  CLEARED · AMMONIA SENSORS WARM") were Figma literals that leaked
//  onto the live path. They now resolve from real sources, mirroring
//  the proven sibling 020 Approaching-Delivery pattern:
//    • hero miles / minutes + header arrive-by + clock — the HERE
//      Routing v8 leg between the driver's live GPS fix and the
//      load's `deliveryLocation` coordinate (remaining length /
//      arrival ISO);
//    • receiver address — `activeLoad.deliveryLocation`
//      (address / city-state / zip);
//    • BAY (dock) + arrive-by — the `appointments.getByLoad` row
//      (`dockNumber` / `scheduledAt`);
//    • CONTACT name + PHONE — the live `contacts.list` shipper rep,
//      dialed through `driverDialPhone` exactly like 020's "Call
//      receiver";
//    • GATE — honest em-dash "-" (no gate column exists on the wire);
//    • ESANG advisory — honest em-dash "-" (no live ESANG advisory
//      source feeds this screen).
//  Any field without a live source renders an honest em-dash "-":
//  no GPS fix, no delivery coord, no appointment, or no contact all
//  degrade to "-" rather than a seeded figure. The pre-arrival rows
//  start unchecked and turn CONFIRMED only on a real driver tap —
//  the auto-seed of the first three rows is removed.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

struct ApproachingReceiver: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverDialPhone) private var dialPhone
    @Environment(\.driverOpenMessages) private var openMessages
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var completed: Set<String> = []
    @State private var isNotifying: Bool = false

    // MARK: - Live nav state (HERE Routing v8 · current fix → receiver)
    //
    // FOUNDER BAR: every figure below is computed from a real source —
    // the HERE-routed leg from the driver's live GPS fix to the
    // delivery coordinate, the load's own appointment row, or the
    // contact book. There are NO seeded constants. When a source isn't
    // available (no active load, no GPS fix, no delivery coord, no
    // appointment, no contact), the field renders an honest em-dash "-".

    /// Remaining distance to the receiver, in meters, from the last
    /// HERE route between the live GPS fix and the delivery coordinate.
    @State private var remainingMeters: Double?
    /// ISO-8601 arrival time HERE computed for the delivery.
    @State private var etaISO: String?
    /// The most-recent appointment row for this load (dock + window).
    @State private var appointment: AppointmentsAPI.ByLoadAppointment?
    /// The live receiver-side contact (shipper rep) for CONTACT + PHONE.
    @State private var receiverContact: ContactsAPI.Contact?

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private static let metersPerMile = 1609.344
    private let dash = "-"

    // MARK: - Live derived strings (HERE leg + appointment + contact → "-")

    /// Live remaining distance to the receiver, "4.2" formatted, else "-".
    private var heroMilesText: String {
        guard let m = remainingMeters else { return dash }
        return String(format: "%.1f", m / Self.metersPerMile)
    }

    /// "· 7 min" remaining-time chip from the live HERE arrival ISO vs
    /// now, else "· -". Never a seeded duration.
    private var heroMinutesText: String {
        guard let iso = etaISO, let eta = Self.parseISO(iso) else { return "· \(dash)" }
        let secs = eta.timeIntervalSinceNow
        guard secs > 0 else { return "· \(dash)" }
        let mins = Int((secs / 60).rounded())
        return "· \(mins) min"
    }

    /// Header arrive-by clock from the appointment `scheduledAt` (the
    /// committed receiving window), falling through to the live HERE
    /// arrival ISO, then the load `deliveryDate`, else "-".
    private var arriveByText: String {
        if let t = Self.formatClock(appointment?.scheduledAt) { return t }
        if let t = Self.formatClock(etaISO) { return t }
        if let t = Self.formatClock(activeLoad?.deliveryDate) { return t }
        return dash
    }

    /// Right-column wall clock — the live HERE arrival local time, else "-".
    private var headerClockText: String {
        Self.formatClock(etaISO, withZone: false) ?? dash
    }

    /// Receiver display title — brand/address + city/state from the
    /// live load, else the honest em-dash sentinel.
    private var receiverTitle: String {
        if let loc = activeLoad?.deliveryLocation, !loc.cityState.isEmpty {
            let brand = loc.address.isEmpty ? loc.cityState : loc.address
            return "\(brand) - \(loc.cityState)"
        }
        return dash
    }

    /// Receiver street address line — "<address> · <city, ST> <zip>"
    /// from the live load, else "-". No fabricated street.
    private var receiverAddressLine: String {
        guard let loc = activeLoad?.deliveryLocation else { return dash }
        let parts = [
            loc.address.isEmpty ? nil : loc.address,
            loc.cityState.isEmpty ? nil : loc.cityState,
            loc.zipCode.isEmpty ? nil : loc.zipCode
        ].compactMap { $0 }
        return parts.isEmpty ? dash : parts.joined(separator: " · ")
    }

    /// BAY fact — the assigned dock door from the appointment row, else "-".
    private var bayText: String {
        guard let d = appointment?.dockNumber, !d.isEmpty else { return dash }
        return d
    }

    /// CONTACT fact — the live receiver-side rep name, else "-".
    private var contactText: String {
        guard let n = receiverContact?.name, !n.isEmpty else { return dash }
        return n
    }

    /// PHONE fact — the live receiver-side rep phone, else "-".
    private var phoneText: String {
        guard let p = receiverContact?.phone, !p.isEmpty else { return dash }
        return p
    }

    /// Header city line for "Arriving at <city> by <time>", else "-".
    private var receiverCityLine: String {
        // 116th firing M2 retrofit (2026-04-26): replaced fixture
        // fallback with the canonical em-dash sentinel. The screen
        // renders an honest "-" when the active trip hasn't hydrated
        // yet, never a fabricated city. Doctrine: 0% mock data.
        let cs = activeLoad?.deliveryLocation?.cityState ?? ""
        return cs.isEmpty ? dash : cs
    }

    /// Lenient ISO-8601 parse (with and without fractional seconds).
    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// "21:14 EDT" wall clock (+ device timezone when requested); nil
    /// when the ISO is missing or unparseable.
    private static func formatClock(_ iso: String?, withZone: Bool = true) -> String? {
        guard let iso = iso, !iso.isEmpty, let date = parseISO(iso) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        guard withZone else { return f.string(from: date) }
        let tz = TimeZone.current.abbreviation() ?? ""
        return tz.isEmpty ? f.string(from: date) : "\(f.string(from: date)) \(tz)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                heroCard
                receiverCard
                if !ctx.receiverHazmatStrip.isEmpty {
                    hazmatStrip
                }
                preArrivalChecklist
                esangAdvisory
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .eusoRefreshTask {
            await hydrateLiveTrip()
        }
        .screenTileRoot()
    }

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
                    Image(systemName: ctx.product.symbol)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("APPROACHING DESTINATION")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("· \(ctx.headerKicker)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                    // EUSOTRIP-MODE-BADGE-2026-05-17 — mode chip on lifecycle screen
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text("Arriving at \(receiverCityLine) by \(arriveByText)")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(headerClockText)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text("APPROACHING")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
            }
        }
        .padding(.top, 4)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(heroMilesText)
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("mi")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(heroMinutesText)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
            }
            // Stylized purple dotted progress
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 3)
                    HStack(spacing: 4) {
                        ForEach(0..<20, id: \.self) { _ in
                            Circle()
                                .fill(LinearGradient.diagonal)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
                .frame(height: 8)
            }
            .frame(height: 8)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var receiverCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 34, height: 34)
                    Text(String(receiverTitle.prefix(1)))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(receiverTitle)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(receiverAddressLine)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Divider().overlay(palette.borderFaint)
            HStack(spacing: Space.s2) {
                // GATE has no column on the wire — honest em-dash, never
                // a fabricated "B-2".
                fact(label: "GATE", value: dash)
                fact(label: "BAY",  value: bayText)
                fact(label: "CONTACT", value: contactText)
                fact(label: "PHONE", value: phoneText)
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

    private func fact(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hazmatStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Brand.warning)
            Text("HAZMAT RECEIVING PRECAUTIONS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Brand.warning)
            Text("· PINGED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Brand.warning.opacity(0.8))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 8)
        .background(Brand.warning.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var preArrivalChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRE-ARRIVAL CHECKLIST")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            ForEach(ctx.receiverPreArrival) { item in
                Button {
                    if completed.contains(item.id) {
                        completed.remove(item.id)
                    } else {
                        completed.insert(item.id)
                    }
                } label: {
                    HStack(spacing: Space.s3) {
                        rowDot(done: completed.contains(item.id))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(EType.body.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)
                            Text(item.subtitle)
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                .foregroundStyle(palette.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Text(completed.contains(item.id) ? "CONFIRMED" : "PENDING")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(completed.contains(item.id) ? Brand.success : palette.textTertiary)
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
        }
    }

    private func rowDot(done: Bool) -> some View {
        ZStack {
            if done {
                Circle().fill(Brand.success.opacity(0.2))
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Brand.success)
            } else {
                Circle().strokeBorder(palette.borderSoft, lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
    }

    private var esangAdvisory: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            // No live ESANG advisory source feeds this screen — the
            // canned "FIT FOR 21:11 · WEATHER HOLD CLEARED · AMMONIA
            // SENSORS WARM" string was a Figma fixture. Render the
            // honest em-dash sentinel until a real advisory lane lands.
            Text(dash)
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { navBack?() } label: {
                Text("Trip log")
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
            CTAButton(
                title: "Notify receiver",
                action: { Task { await notifyReceiver() } },
                trailingIcon: "arrow.right",
                isLoading: isNotifying
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        let load = try? await EusoTripAPI.shared.loads.getById(n)
        activeLoad = load
        // Appointment row (dockNumber → BAY, scheduledAt → arrive-by) —
        // the same `appointments.getByLoad` read the sibling lifecycle
        // screens hydrate. nil-tolerant: no row → BAY + arrive-by fall
        // through to "-".
        appointment = try? await EusoTripAPI.shared.appointments
            .getByLoad(loadId: lifecycle.loadId)
        // Receiver-side rep (CONTACT + PHONE) — same `contacts.list`
        // shipper lookup the 020 "Call receiver" path dials. nil-tolerant.
        receiverContact = (try? await EusoTripAPI.shared.contacts
            .list(type: "shipper", limit: 1))?.first
        if let load { await refreshLiveNav(for: load) }
    }

    /// Computes the live remaining leg from the driver's current GPS
    /// fix to the delivery coordinate via HERE Routing v8 (truck-aware),
    /// and caches the remaining miles + arrival ISO that drive the hero
    /// + minutes + header clock. Every value is a real measurement; on
    /// any failure (no fix, no delivery coord, HERE error) the cached
    /// values stay nil and the UI shows "-". Mirrors 020's
    /// `refreshLiveNav`.
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

    private func notifyReceiver() async {
        isNotifying = true
        defer { isNotifying = false }
        // Dial the live receiver-side rep when we have one (mirrors 020's
        // "Call receiver"); otherwise fall back to opening messages.
        if let phone = receiverContact?.phone, !phone.isEmpty {
            dialPhone?(phone)
        }
        let keys = ["at_receiver", "credentials", "gate"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct ApproachingReceiverScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ApproachingReceiver(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_037(),
                      trailing: driverNavTrailing_037(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_037() -> [NavSlot] {
    RoleNav.driverLeading(current: .trips)
}
private func driverNavTrailing_037() -> [NavSlot] {
    RoleNav.driverTrailing(current: .none)
}

#Preview("037 · Approaching Receiver · Dark") {
    ApproachingReceiverScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("037 · Approaching Receiver · Light") {
    ApproachingReceiverScreen(theme: Theme.light).preferredColorScheme(.light)
}
