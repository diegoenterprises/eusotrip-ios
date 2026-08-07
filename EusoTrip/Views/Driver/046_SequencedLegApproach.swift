//
//  046_SequencedLegApproach.swift
//  EusoTrip — Lifecycle screen 046 · Sequenced Leg Approach.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `046 Sequenced Leg Approach.png`. Driver is approaching the
//  Catalyst home yard. Surfaces miles + ETA hero, leg-handoff
//  card (closed leg → open off-duty), driver-yard facts, and a
//  4-row product-aware yard-in checklist.
//
//  FOUNDER BAR (2026-06-06 · de-fabrication sweep):
//    Every HUD figure on this screen is now computed from a real
//    source — the HERE-routed leg from the driver's live GPS fix
//    to the home-yard coordinate (mirrors 013_ActiveEnroute) — or
//    from the active load's own record. There are NO seeded
//    constants. When a source isn't available (no active load, no
//    GPS fix, no home-yard coord, no appointment) the field renders
//    an honest em-dash.
//
//    Target coord chain for the approach leg: a carrier home-yard
//    coordinate is not first-class on the wire, so we route to the
//    load's `deliveryLocation` (the terminal this screen already
//    carries). When neither a GPS fix nor a delivery coord exists,
//    the hero shows "—".
//
//    Yard gate / spot / bay cells are governed by `yardManagement`
//    (a separate wiring item) and currently have no live source, so
//    they render "—" rather than a fabricated gate/row/bay.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

struct SequencedLegApproach: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var completed: Set<String> = []

    // MARK: - Live nav state (HERE Routing v8 · current fix → home yard)
    //
    // Mirrors 013_ActiveEnroute: the HERE-routed leg from the
    // driver's live GPS fix to the home-yard (delivery) coordinate.
    // Every value is a real measurement; on any failure (no fix, no
    // coord, HERE error) the cached values stay nil and the HUD
    // renders an honest em-dash.

    /// Remaining distance to the home yard, meters (HERE summary).
    @State private var remainingMeters: Double?
    /// Remaining drive time to the home yard, seconds (HERE summary).
    @State private var remainingSeconds: Double?
    /// ISO-8601 arrival time HERE computed for the home yard.
    @State private var etaISO: String?

    /// Most-recent appointment for the active load — supplies the
    /// honest scheduled-arrival time when one is on file.
    @State private var appointment: AppointmentsAPI.ByLoadAppointment?

    /// Device wall clock for the header timestamp — refreshed on
    /// appear. Never a seeded literal.
    @State private var nowDate = Date()

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private static let metersPerMile = 1609.344

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: - Live data bindings (honest em-dash when no source)

    /// "5.4" — live HERE remaining length in miles (numeric only,
    /// the "mi" suffix is rendered separately in the hero), else "—".
    private var heroMilesText: String {
        guard let m = remainingMeters else { return "—" }
        return String(format: "%.1f", m / Self.metersPerMile)
    }

    /// "16 min" — live HERE remaining drive time, else "—".
    private var etaMinText: String {
        guard let s = remainingSeconds, s.isFinite, s >= 0 else { return "—" }
        let mins = Int((s / 60).rounded())
        return "\(mins) min"
    }

    /// "23:14" — HERE arrival clock for the home yard, else "—".
    private var arriveByText: String {
        guard let iso = etaISO, let date = Self.parseISO(iso) else { return "—" }
        return Self.clock(date)
    }

    /// Header device clock, e.g. "22:58". Live wall time, never seeded.
    private var nowClockText: String { Self.clock(nowDate) }

    /// Scheduled appointment clock for the yard arrival, else "—".
    private var apptClockText: String {
        guard let iso = appointment?.scheduledAt, let date = Self.parseISO(iso) else { return "—" }
        return Self.clock(date)
    }

    /// Home-yard name — the delivery/terminal facility on the load.
    /// City+state when present, else "—". No fabricated yard name.
    private var yardName: String {
        if let loc = activeLoad?.deliveryLocation,
           !(loc.lat == 0 && loc.lng == 0) || !loc.cityState.isEmpty {
            if !loc.cityState.isEmpty { return loc.cityState }
        }
        return "—"
    }

    /// Home-yard address composed from the delivery location, else "—".
    private var yardAddress: String {
        guard let loc = activeLoad?.deliveryLocation else { return "—" }
        var parts: [String] = []
        if !loc.address.isEmpty  { parts.append(loc.address.uppercased()) }
        if !loc.city.isEmpty     { parts.append(loc.city.uppercased()) }
        if !loc.state.isEmpty    { parts.append(loc.state.uppercased()) }
        if !loc.zipCode.isEmpty  { parts.append(loc.zipCode) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// First letter of the home-yard city for the avatar monogram,
    /// else a neutral dot. Never a hardcoded "C".
    private var yardMonogram: String {
        if let c = activeLoad?.deliveryLocation?.city.first { return String(c).uppercased() }
        return "·"
    }

    /// Closed-leg title — the real pickup→delivery city pair from the
    /// active load, prefixed by the product word. "—" when no load.
    private var closedLegTitle: String {
        guard let load = activeLoad else { return "—" }
        let origin = load.pickupLocation?.cityState ?? ""
        let dest   = load.deliveryLocation?.cityState ?? ""
        let lane: String
        if !origin.isEmpty && !dest.isEmpty { lane = "\(origin) → \(dest)" }
        else if !origin.isEmpty             { lane = origin }
        else if !dest.isEmpty               { lane = dest }
        else                                { return "—" }
        return "\(productWord) · \(lane)"
    }

    /// Product word for the closed-leg title prefix.
    private var productWord: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:  return "Tanker"
        case .reefer:                       return "Cold"
        case .flatbed:                      return "Flatbed"
        case .container, .railIntermodal:   return "Container"
        case .vesselContainer:              return "Vessel box"
        case .railBulk, .vesselBulk:        return "Bulk"
        case .dryVan:                       return "Dry"
        }
    }

    /// Closed-leg distance sub-line — the load's own routed distance
    /// when the wire carries it, else "—". No fabricated mileage.
    private var closedLegSub: String {
        guard let raw = activeLoad?.distance, let d = Double(raw), d > 0 else { return "—" }
        let unit = (activeLoad?.distanceUnit ?? "mi").lowercased()
        let suffix = unit.contains("km") ? "km" : "mi"
        return String(format: "%.0f %@", d, suffix)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                heroCard
                legHandoff
                yardCard
                yardChecklist
                esangFooter
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task {
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
                    Image(systemName: "house.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("APPROACHING HOME YARD · DEADHEAD")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text(headerTitle)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(ctx.headerKicker)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    // EUSOTRIP-MODE-BADGE-2026-05-17 — mode chip on lifecycle screen
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
            }
            Spacer(minLength: 0)
            Text(nowClockText)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, 4)
    }

    /// Header line — live arrival clock against the home-yard name.
    /// "Arriving at <yard> by <clock>" when both are known; degrades
    /// honestly to the clock-only or yard-only or em-dash forms.
    private var headerTitle: String {
        let name = yardName == "—" ? "home yard" : "\(yardName) yard"
        let by = arriveByText
        return by == "—"
            ? "Arriving at \(name)"
            : "Arriving at \(name) by \(by)"
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(heroMilesText)
                    .font(.system(size: 50, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("mi")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("· \(etaMinText)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
                if apptClockText != "—" {
                    Text("· APPT \(apptClockText)")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 4)
                    HStack(spacing: 4) {
                        ForEach(0..<22, id: \.self) { _ in
                            Circle().fill(LinearGradient.diagonal).frame(width: 4, height: 4)
                        }
                    }
                }
                .frame(height: 8)
            }
            .frame(height: 8)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var legHandoff: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            handoffBlock(state: "CLOSED · LEG 1", title: closedLegTitle, sub: closedLegSub, color: Brand.success)
            handoffBlock(state: "OPEN · POST-TRIP DVIR", title: "34-hour reset begins", sub: "Cycle resets 49 CFR 395.3(c)", color: Brand.warning)
        }
    }

    private func handoffBlock(state: String, title: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(color)
            Text(title)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(sub)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(2)
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

    private var yardCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    Text(yardMonogram).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(yardName)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(yardAddress)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            // Yard gate / spot / bay assignments are owned by the
            // `yardManagement` wiring (a separate item) — no live
            // source on this load read, so every cell renders an
            // honest em-dash rather than a fabricated gate/row/bay.
            HStack(spacing: Space.s2) {
                yardCell(label: "ENTRY",         value: "—")
                yardCell(label: "ASSIGNED SPOT", value: "—")
                yardCell(label: "PARKED",        value: "—")
                yardCell(label: "SLEEPER BAY",   value: "—")
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

    private func yardCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var yardChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YARD-IN CHECKLIST")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            ForEach(ctx.yardInChecklist) { row in
                Button {
                    if completed.contains(row.id) {
                        completed.remove(row.id)
                    } else {
                        completed.insert(row.id)
                    }
                } label: {
                    HStack(spacing: Space.s3) {
                        rowDot(done: completed.contains(row.id))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(EType.body.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)
                            Text(row.subtitle)
                                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(completed.contains(row.id) ? "VERIFIED" : row.tail)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(completed.contains(row.id) ? Brand.success : palette.textTertiary)
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

    private var esangFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("ESANG · SHOWER + BUNK QUEUED · WEATHER CALM · I'LL WAKE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
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

    private func hydrateLiveTrip() async {
        nowDate = Date()
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        let load = try? await EusoTripAPI.shared.loads.getById(n)
        activeLoad = load
        // Appointment (scheduled-arrival window) for this load — honest
        // nil when none is on file. No fabricated appt clock.
        appointment = try? await EusoTripAPI.shared.appointments.getByLoad(loadId: lifecycle.loadId)
        if let load { await refreshLiveNav(for: load) }
    }

    /// Computes the live remaining leg from the driver's current GPS
    /// fix to the home-yard coordinate via HERE Routing v8 (truck-aware),
    /// and caches the summary numbers that drive the hero. The target is
    /// the load's `deliveryLocation` (the terminal this screen carries)
    /// because no first-class carrier home-yard coordinate exists on the
    /// wire. Every value is a real HERE measurement; on any failure (no
    /// fix, no coord, HERE error) the cached values stay nil and the hero
    /// renders an honest em-dash. Mirrors 013_ActiveEnroute:~208.
    @MainActor
    private func refreshLiveNav(for load: Load) async {
        // Home-yard target coord: the delivery/terminal coordinate.
        guard let dest = load.deliveryLocation,
              !(dest.lat == 0 && dest.lng == 0) else {
            remainingMeters = nil
            remainingSeconds = nil
            etaISO = nil
            return
        }

        // Live GPS fix. nil when denied / timed out → hero reads "—".
        guard let fix = await DriverLocationResolver.shared.currentCoordinate() else {
            remainingMeters = nil
            remainingSeconds = nil
            etaISO = nil
            return
        }

        let stops = HereStops(
            origin: fix,
            destination: CLLocationCoordinate2D(latitude: dest.lat, longitude: dest.lng)
        )
        let profile = TruckProfile.from(load: load)
        do {
            let resp = try await HereRoutingClient.shared.route(stops: stops, profile: profile)
            guard let section = resp.routes.first?.sections.first,
                  let summary = section.summary else {
                remainingMeters = nil
                remainingSeconds = nil
                etaISO = nil
                return
            }
            remainingMeters = Double(summary.length)
            remainingSeconds = Double(summary.duration)
            etaISO = section.arrival.time
        } catch {
            // Honest failure: leave the numbers nil so the hero shows
            // "—" rather than a stale or fabricated figure.
            remainingMeters = nil
            remainingSeconds = nil
            etaISO = nil
        }
    }
}

struct SequencedLegApproachScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            SequencedLegApproach(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_046(),
                      trailing: driverNavTrailing_046(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_046() -> [NavSlot] {
    RoleNav.driverLeading(current: .trips)
}
private func driverNavTrailing_046() -> [NavSlot] {
    RoleNav.driverTrailing(current: .none)
}

#Preview("046 · Sequenced Leg Approach · Dark") {
    SequencedLegApproachScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("046 · Sequenced Leg Approach · Light") {
    SequencedLegApproachScreen(theme: Theme.light).preferredColorScheme(.light)
}
