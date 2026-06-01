//
//  013_ActiveEnroute.swift
//  EusoTrip 2027 UI — Wave 7 (driver · lifecycle · en route to pickup)
//
//  Screen 013 · En Route to Pickup — the driver is rolling toward
//  the pickup dock with live turn-by-turn guidance, hazmat-safe
//  routing, and a bottom sheet that shows the facility + appt
//  clock + the three live tiles (distance left / drive time /
//  fuel burn).
//
//  Figma source of truth:
//    /Users/diegousoro/Desktop/EusoTrip 2027 UI Wireframes/
//      01 Driver/{Dark,Light}/013 En Route to Pickup.png
//
//  Cohort B — server-backed (97th firing, gap-analysis P0):
//
//    • `TripLifecycleStore` hydrates the driver's currently-
//      assigned load + enumerates legal next-state transitions.
//    • "Continue route" CTA fires `loadLifecycle.executeTransition`
//      on the closest matching forward hop + chains into the
//      local `lifecycleAdvance` closure so the trip walks to 014.
//    • `Call shipper` deeplinks to `tel:` using the shipper's
//      phone from the Load record; disables honestly ("No phone
//      on file") while the wire shape carries no contact phone.
//    • The HUD figures (ETA clock, remaining mi, remaining drive
//      time, approach progress) are computed LIVE from a HERE
//      Routing v8 leg between the driver's CoreLocation fix and
//      the pickup coordinate. No seeded constants — any field
//      without a live source renders an honest em-dash "—"
//      (e.g. instantaneous FUEL BURN: no truck-telemetry feed
//      exists, so it is always "—").
//    • `HereLiveMapView` renders the OMV vector map + a polyline
//      from pickup to delivery. Truck-aware routing is computed
//      via HERE Routing v8 per the doctrine.
//
//  Role + vertical awareness:
//    • DRIVER / CATALYST / ESCORT → "En route · Pickup"
//    • RAIL_ENGINEER / RAIL_CONDUCTOR → "En route · Rail yard"
//    • SHIP_CAPTAIN / VESSEL_OPERATOR → "En route · Port"
//    • Chip row adapts to the product:
//        hazmat tanker → NH3 · UN1005 · TANK
//        dry van → BOL · CTE · DRY
//        reefer → REEFER · 36°F · CTE
//    • Low-clearance warning only renders when HERE returns a
//      vertical-clearance attribute on any segment in the next
//      ~5 mi.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on "Continue route" primary CTA
//         + progress bar fill. Brand.warning on LOW-CLEARANCE chip.
//         Brand.blue on HAZMAT ROUTE LOCKED. Brand.success on
//         NH3/UN/TANK commodity chip when hazmat is locked.
//    §4   Tokenized Space / Radius / EType throughout.
//    §5   Palette semantic throughout (no raw Color.white).
//

import SwiftUI
import MapKit
import CoreLocation
import UIKit

// MARK: - Screen

struct ActiveEnroute: View {
    @Environment(\.palette) var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject var session: EusoTripSession

    enum Register { case night, morning }
    let register: Register

    @Environment(\.openURL) private var openURL

    // Live server-backed state
    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?

    // MARK: - Live nav state (HERE Routing v8 · current fix → pickup)
    //
    // FOUNDER BAR: every HUD figure below is computed from a real
    // source — the HERE-routed leg from the driver's live GPS fix
    // to the pickup coordinate, or the load's own pickup window.
    // There are NO seeded constants. When a source isn't available
    // (no active load, no GPS fix, no truck-telemetry fuel feed),
    // the field renders an honest em-dash "—".

    /// Remaining distance to the pickup, in meters, from the last
    /// HERE route between the live GPS fix and the pickup coordinate.
    @State private var remainingMeters: Double?
    /// Remaining drive time to pickup, in seconds (HERE summary).
    @State private var remainingSeconds: Double?
    /// ISO-8601 arrival time HERE computed for the pickup.
    @State private var etaISO: String?
    /// First-measured fix→pickup distance (meters). Captured once so
    /// the approach-progress bar has an honest live denominator: the
    /// fraction is (baseline − remaining) / baseline, both numbers
    /// being real HERE measurements.
    @State private var baselineMeters: Double?

    // NOTE: turn-by-turn maneuver narration ("Take Exit 228 · …") has
    // NO live source — `HereRouteModels.HereRouteSection` does not
    // decode the `actions` array, so the next-step instruction text is
    // not available on the wire. The maneuver card therefore renders
    // the honest remaining-distance heading + the pickup road/city
    // from the load, never a fabricated exit string.

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topManeuverCard
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s2)
                Spacer()
                bottomSheet
                    .padding(.horizontal, Space.s3)
                    .padding(.bottom, Space.s3)
            }
        }
        .screenTileRoot()
        .task { await hydrateLiveTrip() }
    }

    // MARK: - Product + vertical awareness
    //
    // Dispatched through the shared `LifecycleProductContext` so
    // this screen carries the same vertical + product-variant
    // awareness the 014-025 rewrites use. Retired the local
    // `TripVertical` enum that only knew about pickup-word and
    // didn't split by product — now every chip, icon, and ESANG
    // line can adapt to dry van / reefer / flatbed / container /
    // rail / vessel just like the rest of the lifecycle family.

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    /// Back-compat alias for the existing call sites inside this
    /// file that read `vertical.pickupWord`. Any new surface on
    /// 013 should read `ctx.vertical` / `ctx.product` directly.
    private var vertical: TripVertical { ctx.vertical }

    // MARK: - Hydration

    /// Hydrate the lifecycle store from the driver's current
    /// assigned load and pull the full Load row for the map +
    /// destination card. Safe to run on every appear — cheap
    /// when `loadId` is already populated.
    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        let load = try? await EusoTripAPI.shared.loads.getById(n)
        activeLoad = load
        if let load { await refreshLiveNav(for: load) }
    }

    /// Computes the live remaining leg from the driver's current GPS
    /// fix to the pickup coordinate via HERE Routing v8 (truck-aware),
    /// and caches the summary numbers that drive the HUD. Every value
    /// is a real measurement; on any failure (no fix, no pickup, HERE
    /// error) the cached values stay nil and the HUD shows "—".
    @MainActor
    private func refreshLiveNav(for load: Load) async {
        guard let pickup = load.pickupLocation,
              pickup.lat != 0 || pickup.lng != 0 else { return }

        // Live GPS fix. nil when denied / timed out → HUD reads "—".
        guard let fix = await DriverLocationResolver.shared.currentCoordinate() else {
            remainingMeters = nil
            remainingSeconds = nil
            etaISO = nil
            return
        }

        let stops = HereStops(
            origin: fix,
            destination: CLLocationCoordinate2D(latitude: pickup.lat, longitude: pickup.lng)
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
            // Capture the approach baseline exactly once so the
            // progress bar has an honest live denominator.
            if baselineMeters == nil { baselineMeters = Double(summary.length) }
        } catch {
            // Honest failure: leave the numbers nil so the HUD shows
            // "—" rather than a stale or fabricated figure.
            remainingMeters = nil
            remainingSeconds = nil
            etaISO = nil
        }
    }

    /// Fires the next forward state transition on the server
    /// then hops to 014 via the local `lifecycleAdvance` closure.
    /// Selection picks the first transition whose target state
    /// matches pickup-arrival semantics; falls through to local
    /// advance when no legal server transition exists (preview +
    /// no-active-load runtime).
    private func continueRoute() async {
        let candidates = lifecycle.availableTransitions
        let preferred = candidates.first { t in
            let to = t.to.lowercased()
            return to.contains("approach") || to.contains("at_pickup") || to.contains("pickup")
        } ?? candidates.first
        if let transition = preferred {
            _ = await lifecycle.execute(transition)
        }
        advance?()
    }

    // MARK: - Data bindings (live HERE leg → honest em-dash)

    private static let metersPerMile = 1609.344

    /// "42.7 mi" from the live HERE remaining length, else "—".
    private var remainingMilesText: String {
        guard let m = remainingMeters else { return "—" }
        return String(format: "%.1f mi", m / Self.metersPerMile)
    }

    /// "0h 51m" from the live HERE remaining duration, else "—".
    private var remainingDriveText: String {
        guard let s = remainingSeconds, s.isFinite, s >= 0 else { return "—" }
        let total = Int(s.rounded())
        let h = total / 3600
        let mins = (total % 3600) / 60
        return "\(h)h \(String(format: "%02dm", mins))"
    }

    /// "08:14" local clock from the live HERE arrival ISO, else "—".
    private var etaClockText: String {
        guard let iso = etaISO,
              let date = Self.parseISO(iso) else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// "ETA · CDT" with the device timezone abbreviation, else "ETA".
    private var etaLabelText: String {
        guard etaISO != nil else { return "ETA" }
        let tz = TimeZone.current.abbreviation() ?? ""
        return tz.isEmpty ? "ETA" : "ETA · \(tz)"
    }

    /// "412 mi" — live remaining distance for the miles row, else "—".
    private var milesLabelText: String { remainingMilesText }

    /// "2h 08m remaining" from the live duration, else "—".
    private var timeRemainingText: String {
        guard let s = remainingSeconds, s.isFinite, s >= 0 else { return "—" }
        let total = Int(s.rounded())
        let h = total / 3600
        let mins = (total % 3600) / 60
        return "\(h)h \(String(format: "%02dm", mins)) remaining"
    }

    /// Honest approach fraction: (baseline − remaining) / baseline,
    /// both real HERE measurements. 0 when no live leg is on file.
    private var liveProgress: Double {
        guard let base = baselineMeters, base > 0,
              let rem = remainingMeters else { return 0 }
        let consumed = base - rem
        return min(max(consumed / base, 0), 1)
    }

    /// Pickup-window clock from the load's `pickupDate` (the APPT
    /// shown beside the pickup facility), else "—".
    private var appointmentText: String {
        guard let iso = activeLoad?.pickupDate,
              let date = Self.parseISO(iso) else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let tz = TimeZone.current.abbreviation() ?? ""
        return tz.isEmpty ? f.string(from: date) : "\(f.string(from: date)) \(tz)"
    }

    /// Instantaneous FUEL BURN has NO live source — there is no
    /// truck-telemetry feed anywhere in the platform — so it renders
    /// an honest em-dash, never a fabricated gallons figure.
    private var fuelBurnText: String { "—" }

    /// Maneuver heading: live remaining distance to the pickup. HERE
    /// turn-by-turn `actions` are not decoded by the route models, so
    /// we never fabricate an exit-narration string.
    private var titleHeading: String {
        guard remainingMeters != nil else { return "—" }
        return "In \(remainingMilesText)"
    }

    /// Maneuver detail: the live pickup destination (city/state) from
    /// the load, else an honest em-dash.
    private var titleDetail: String {
        if let load = activeLoad, let loc = load.pickupLocation, !loc.cityState.isEmpty {
            return "Next stop · \(loc.cityState)"
        }
        return "—"
    }

    /// Lenient ISO-8601 parse (with and without fractional seconds).
    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private var destinationFacility: String {
        if let load = activeLoad,
           let loc = load.pickupLocation,
           !loc.city.isEmpty {
            let stateSuffix = loc.state.isEmpty ? "" : ", \(loc.state)"
            return "\(loc.city)\(stateSuffix)"
        }
        return "—"
    }

    private var destinationAddress: String {
        if let load = activeLoad,
           let loc = load.pickupLocation,
           !loc.address.isEmpty {
            var parts = [loc.address]
            if !loc.city.isEmpty    { parts.append(loc.city) }
            if !loc.state.isEmpty   { parts.append(loc.state) }
            if !loc.zipCode.isEmpty { parts.append(loc.zipCode) }
            return parts.joined(separator: " · ")
        }
        return "—"
    }

    // MARK: - Commodity chip row
    //
    // Reads the load's hazmat + product + HERE clearance fields
    // to compose the three chips visible in the Figma frame. Each
    // chip comes from a real data source — we never fabricate an
    // NH3 UN number or a low-clearance distance.

    private struct EnrouteChip: Identifiable {
        let id = UUID()
        let label: String
        let tint: Color
        let icon: String?
    }

    private var chips: [EnrouteChip] {
        var out: [EnrouteChip] = []
        // HAZMAT chip — rendered only when the live load actually
        // carries a hazmat class. No load = no fabricated chip.
        let isHazmat = (activeLoad?.hazmatClass ?? "").isEmpty == false
        if isHazmat {
            out.append(EnrouteChip(label: "HAZMAT ROUTE LOCKED", tint: Brand.info, icon: "lock.shield"))
        }
        // 2026-05-17 — Mode chip on the driver en-route header. Hidden
        // for default truck-single-vehicle. Renders MODE × Nx so a rail
        // engineer hauling a 100-tank-car unit train sees the count
        // up-front during transit, distinguishable from a single-truck
        // load even though they look identical in plain text.
        if let load = activeLoad {
            let mode = (load.transportMode ?? "truck").lowercased()
            let count = load.multiVehicleCount ?? 1
            if mode != "truck" || count > 1 {
                let label: String = {
                    let m = mode.uppercased()
                    return count > 1 ? "\(count)× \(m)" : m
                }()
                let tint: Color = {
                    switch mode {
                    case "rail":   return Brand.rail
                    case "vessel": return Brand.vessel
                    case "barge":  return Brand.info
                    default:       return Brand.blue
                    }
                }()
                out.append(EnrouteChip(label: label, tint: tint, icon: nil))
            }
        }
        // Commodity chip — UN + class + cargoType.
        if let load = activeLoad {
            var pieces: [String] = []
            if let name = load.commodityName, !name.isEmpty { pieces.append(name.uppercased()) }
            if let un = load.unNumber, !un.isEmpty { pieces.append(un) }
            if let cargo = load.cargoType, !cargo.isEmpty { pieces.append(cargo.uppercased()) }
            if !pieces.isEmpty {
                out.append(EnrouteChip(
                    label: pieces.joined(separator: " · "),
                    tint: Brand.success,
                    icon: nil
                ))
            }
        }
        // Low-clearance chip — sourced from HERE route span
        // truck-attributes. The route models don't currently decode
        // per-span clearance limits, so there is no live source for a
        // clearance warning and we never fabricate one.
        return out
    }

    // MARK: - Map layer

    @ViewBuilder
    private var mapLayer: some View {
        if let load = activeLoad,
           let pickup = load.pickupLocation,
           let delivery = load.deliveryLocation,
           // Coord gate (D-maps-basemap 2026-06-01): the server's geocode
           // self-heal can return a load whose pickup/delivery JSON is present
           // but whose lat/lng are still 0 (HERE geocode not yet run). Drawing
           // those frames the map on null island (0,0). Require a real fix on
           // BOTH endpoints; otherwise fall to the honest placeholder until the
           // next read lands coords.
           !(pickup.lat == 0 && pickup.lng == 0),
           !(delivery.lat == 0 && delivery.lng == 0) {
            // Canonical OMV vector map + live HERE add-ons surfaced as pins:
            // fuel / EV / weather / traffic / sponsored ad-zones. The route +
            // pickup/delivery are the base layers; HereLiveMapView fetches the
            // add-ons around the lane and overlays them with a corner legend.
            HereLiveMapView(
                center: .init(pickup.lat, pickup.lng),
                zoom: 7,
                firstPerson: true,
                route: [.init(pickup.lat, pickup.lng), .init(delivery.lat, delivery.lng)],
                baseLayers: [
                    .route(polyline: [.init(pickup.lat, pickup.lng),
                                      .init(delivery.lat, delivery.lng)],
                           colorHex: "#1473FF"),
                    .markers([
                        .init(at: .init(pickup.lat, pickup.lng), kind: .pickup, label: destinationFacility),
                        .init(at: .init(delivery.lat, delivery.lng), kind: .delivery, label: nil)
                    ])
                ],
                addOns: .driverEnRoute
            )
        } else {
            mapPlaceholder
        }
    }

    /// Stylized ghost-grid canvas shown only when no active load
    /// is on file (previews + first-run). It carries NO business
    /// data — it's a neutral on-brand backdrop, not a fabricated
    /// route.
    private var mapPlaceholder: some View {
        ZStack {
            palette.bgPage.ignoresSafeArea()
            Canvas { ctx, size in
                let stroke = palette.borderFaint.opacity(0.6)
                let step: CGFloat = 48
                var x: CGFloat = 0
                while x < size.width {
                    var path = Path()
                    path.move(to: .init(x: x, y: 0))
                    path.addLine(to: .init(x: x, y: size.height))
                    ctx.stroke(path, with: .color(stroke), lineWidth: 0.5)
                    x += step
                }
                var y: CGFloat = 0
                while y < size.height {
                    var path = Path()
                    path.move(to: .init(x: 0, y: y))
                    path.addLine(to: .init(x: size.width, y: y))
                    ctx.stroke(path, with: .color(stroke), lineWidth: 0.5)
                    y += step
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Path { p in
                    p.move(to: .init(x: w * 0.72, y: h * 0.92))
                    p.addQuadCurve(to: .init(x: w * 0.68, y: h * 0.65),
                                   control: .init(x: w * 0.82, y: h * 0.78))
                    p.addQuadCurve(to: .init(x: w * 0.55, y: h * 0.35),
                                   control: .init(x: w * 0.58, y: h * 0.50))
                    p.addQuadCurve(to: .init(x: w * 0.62, y: h * 0.02),
                                   control: .init(x: w * 0.52, y: h * 0.18))
                }
                .stroke(LinearGradient.diagonal,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
        }
    }

    // MARK: - Top maneuver card

    private var topManeuverCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            maneuverIcon
            VStack(alignment: .leading, spacing: Space.s2) {
                maneuverHeader
                maneuverSubhead
                progressRail
                milesRow
                chipsRow
                // HERE Dynamic Map Content — live road intel chips.
                // Pulls Real-Time Traffic flow, Road Alerts
                // (incidents), and Safety Cameras in parallel, using
                // the driver's current CoreLocation fix or a fallback
                // waypoint from the active load. Chips silently hide
                // when HERE returns nothing, so the card stays clean
                // between events.
                EnRouteRoadIntelStrip()
            }
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderSoft, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        )
    }

    private var maneuverIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(LinearGradient.diagonal)
            Image(systemName: "arrow.up")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 54, height: 54)
    }

    private var maneuverHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titleHeading)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(etaClockText)
                    .font(EType.bodyStrong.monospaced())
                    .foregroundStyle(palette.textPrimary)
                Text(etaLabelText)
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var maneuverSubhead: some View {
        Text(titleDetail)
            .font(EType.body)
            .foregroundStyle(palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var progressRail: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.tintNeutral.opacity(0.4))
                Capsule().fill(LinearGradient.diagonal)
                    .frame(width: max(4, geo.size.width * liveProgress))
            }
        }
        .frame(height: 4)
    }

    private var milesRow: some View {
        HStack {
            Text(milesLabelText)
                .font(EType.caption.monospaced())
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(timeRemainingText)
                .font(EType.caption.monospaced())
                .foregroundStyle(palette.textTertiary)
        }
    }

    @ViewBuilder
    private var chipsRow: some View {
        let all = chips
        FlowRow(spacing: 6) {
            ForEach(all) { chip in
                enrouteChip(chip)
            }
        }
    }

    private func enrouteChip(_ chip: EnrouteChip) -> some View {
        HStack(spacing: 4) {
            Circle().fill(chip.tint).frame(width: 6, height: 6)
            if let icon = chip.icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(chip.tint)
            }
            Text(chip.label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(chip.tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(
            Capsule().stroke(chip.tint.opacity(0.55), lineWidth: 1)
        )
    }

    // MARK: - Bottom sheet

    private var bottomSheet: some View {
        VStack(spacing: Space.s3) {
            Capsule().fill(palette.borderSoft).frame(width: 40, height: 4)

            // Facility row
            HStack(alignment: .top, spacing: Space.s3) {
                facilityPin
                VStack(alignment: .leading, spacing: 2) {
                    Text(destinationFacility)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(destinationAddress)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("APPT")
                        .font(EType.micro)
                        .tracking(1.3)
                        .foregroundStyle(palette.textTertiary)
                    Text(appointmentText)
                        .font(EType.bodyStrong.monospaced())
                        .foregroundStyle(palette.textPrimary)
                }
            }

            // Tiles
            HStack(spacing: Space.s2) {
                tile(label: "DISTANCE", value: remainingMilesText)
                tile(label: "DRIVE TIME", value: remainingDriveText)
                tile(label: "FUEL BURN", value: fuelBurnText)
            }

            // CTAs
            HStack(spacing: Space.s2) {
                Button {
                    callShipper()
                } label: {
                    Text(shipperPhone == nil ? "No phone on file" : "Call shipper")
                        .font(EType.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(shipperPhone == nil ? palette.textTertiary : palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderSoft, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(shipperPhone == nil)

                Button {
                    Task { await continueRoute() }
                } label: {
                    HStack(spacing: 6) {
                        if lifecycle.inflightTransitionId != nil {
                            ProgressView().progressViewStyle(.circular).tint(.white)
                        }
                        Text("Continue route")
                            .font(EType.body)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(LinearGradient.diagonal)
                    )
                }
                .buttonStyle(.plain)
                .disabled(lifecycle.inflightTransitionId != nil)
                .accessibilityLabel("Continue route to pickup")
            }
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderSoft, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
        )
    }

    private var facilityPin: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(LinearGradient.diagonal.opacity(0.18))
                .frame(width: 40, height: 40)
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
        }
    }

    private func tile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong.monospaced())
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Helpers

    /// The shipper's dialable phone, when the live `Load` carries
    /// one. The current `Load` Codable shape does NOT surface a
    /// shipper/contact phone (no field on the wire), so this stays
    /// nil and the Call button disables itself honestly — we never
    /// fabricate a number. Mirrors the receiver-call pattern on 038.
    private var shipperPhone: String? {
        // Wired to a real value once `loads.getById` surfaces
        // `shipper.phone`. Until then there is no live source.
        nil
    }

    /// Deeplink to `tel:` using the shipper's phone on the active
    /// load. No-op when no phone is on file — never fabricate a
    /// contact, never dial a placeholder number.
    private func callShipper() {
        guard let raw = shipperPhone, !raw.isEmpty else { return }
        let digits = raw.filter { "+0123456789".contains($0) }
        guard !digits.isEmpty, let url = URL(string: "tel:\(digits)") else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        openURL(url)
    }
}

// MARK: - FlowRow (wraps chips across lines)

private struct FlowRow<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        _FlowLayout(spacing: spacing) { content() }
    }
}

private struct _FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var total = CGSize(width: 0, height: 0)
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxWidth, x > 0 {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            total.width = max(total.width, x)
            total.height = y + rowH
        }
        return total
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            s.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(sz)
            )
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Wrapper (registry entry)

struct ActiveEnrouteScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            // Figma shows a single register — the Dark/Light
            // variants are palette-driven, not register-driven.
            // We pick `.morning` as the default; a future cue from
            // session time-of-day can flip to `.night`.
            ActiveEnroute(register: .morning)
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
                    NavSlot(label: "Trips", systemImage: "truck.box", isCurrent: true),
                ],
                trailing: [
                    NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
                    NavSlot(label: "Me",     systemImage: "person",      isCurrent: false),
                ],
                orbState: .idle
            )
        }
    }
}

// MARK: - Previews

#Preview("013 · En Route to Pickup · Dark") {
    ActiveEnrouteScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("013 · En Route to Pickup · Light") {
    ActiveEnrouteScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
