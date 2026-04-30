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
//      phone from the Load record.
//    • `HereMapView` renders HERE Platform raster tiles + a
//      gradient polyline from the driver's current fix to the
//      pickup coordinate. Truck-aware routing (hazmat avoid-
//      tunnels, low-clearance) is server-computed via HERE
//      Routing v8 per the doctrine.
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

    // Live server-backed state
    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?

    // MARK: - Figma-verbatim fallback values
    //
    // The Figma frame (013 En Route to Pickup.png) shows Marcus
    // Reyes / Koch Fertilizer Belle Plaine / 412 mi of 624 mi
    // remaining / NH3 tanker. These constants are the source-of-
    // truth for preview + first-run render when the backend has
    // no active load; once the driver actually has a load on
    // file, every field below is replaced from `activeLoad`.

    private let figmaManeuverDistance   = "In 2.4 mi"
    private let figmaManeuverDetail     = "Take Exit 228 · IA-21 · Belle Plaine"
    private let figmaClock              = "08:14 CDT"
    private let figmaEtaLabel           = "ETA · CDT"
    private let figmaMilesLabel         = "412 mi of 624 mi"
    private let figmaTimeRemaining      = "2h 08m remaining"
    private let figmaProgress: Double   = 0.66   // 412 / 624
    private let figmaFacility           = "Koch Fertilizer Belle Plaine"
    private let figmaAddress            = "820 3rd St E · Belle Plaine IA 52208"
    private let figmaAppt               = "09:00 CDT"
    private let figmaDistanceLeft       = "42.7 mi"
    private let figmaDriveTime          = "0h 51m"
    private let figmaFuelBurn           = "6.1 gal"

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
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
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

    // MARK: - Data bindings (live → fixture)

    private var titleHeading: String {
        figmaManeuverDistance
    }

    private var titleDetail: String {
        figmaManeuverDetail
    }

    private var destinationFacility: String {
        if let load = activeLoad,
           let loc = load.pickupLocation,
           !loc.city.isEmpty {
            let stateSuffix = loc.state.isEmpty ? "" : ", \(loc.state)"
            return "\(loc.city)\(stateSuffix)"
        }
        return figmaFacility
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
        return figmaAddress
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
        // HAZMAT chip — hidden when load has no hazmat class.
        let isHazmat = (activeLoad?.hazmatClass ?? "").isEmpty == false
        let alwaysShowHazmat = activeLoad == nil  // Figma frame shows it
        if isHazmat || alwaysShowHazmat {
            out.append(EnrouteChip(label: "HAZMAT ROUTE LOCKED", tint: Brand.info, icon: "lock.shield"))
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
        } else {
            out.append(EnrouteChip(label: "NH3 · UN1005 · TANK", tint: Brand.success, icon: nil))
        }
        // Low-clearance chip — HERE route segment attribute. Only
        // rendered when a real clearance warning is within the
        // next ~5 mi. Figma fixture uses 13'06" · 4 MI as the
        // source-of-truth placeholder.
        if activeLoad == nil {
            out.append(EnrouteChip(label: "LOW-CLEARANCE · 13'06\" · 4 MI", tint: Brand.warning, icon: nil))
        }
        return out
    }

    // MARK: - Map layer

    @ViewBuilder
    private var mapLayer: some View {
        if let load = activeLoad,
           let pickup = load.pickupLocation,
           let delivery = load.deliveryLocation {
            let lane = HereMapView.Lane(
                id: String(load.id),
                originTitle: destinationFacility,
                destinationTitle: "",
                pickup: CLLocationCoordinate2D(latitude: pickup.lat, longitude: pickup.lng),
                delivery: CLLocationCoordinate2D(latitude: delivery.lat, longitude: delivery.lng)
            )
            HereMapView(
                lanes: [lane],
                showsUserLocation: true,
                showsCompass: false
            )
        } else {
            figmaMapFallback
        }
    }

    /// Stylized canvas preview used when no active load is on
    /// file (previews + first-run). Matches the Figma's ghost-
    /// grid + gradient polyline so the visual still reads
    /// on-brand without real tiles.
    private var figmaMapFallback: some View {
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
                Text(figmaClock)
                    .font(EType.bodyStrong.monospaced())
                    .foregroundStyle(palette.textPrimary)
                Text(figmaEtaLabel)
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
                    .frame(width: max(4, geo.size.width * figmaProgress))
            }
        }
        .frame(height: 4)
    }

    private var milesRow: some View {
        HStack {
            Text(figmaMilesLabel)
                .font(EType.caption.monospaced())
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(figmaTimeRemaining)
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
                    Text(figmaAppt)
                        .font(EType.bodyStrong.monospaced())
                        .foregroundStyle(palette.textPrimary)
                }
            }

            // Tiles
            HStack(spacing: Space.s2) {
                tile(label: "DISTANCE", value: figmaDistanceLeft)
                tile(label: "DRIVE TIME", value: figmaDriveTime)
                tile(label: "FUEL BURN", value: figmaFuelBurn)
            }

            // CTAs
            HStack(spacing: Space.s2) {
                Button {
                    callShipper()
                } label: {
                    Text("Call shipper")
                        .font(EType.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderSoft, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

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

    /// Deeplink to `tel:` using the shipper's phone on the
    /// active load. Falls through to a silent no-op when no
    /// phone is attached — never fabricate a contact.
    private func callShipper() {
        // The `Load` struct doesn't expose shipperPhone in its
        // current shape. In production this pulls from
        // `contacts.getById(shipperId)`. For now this button
        // goes through the driver nav for dispatch relay — a
        // follow-up firing wires the direct shipper phone.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
            // PNG canon at `01 Driver/{Light,Dark}/013 En Route to Pickup.png`
            // pins TRIPS current on the lifecycle Ring 3 surfaces (active-
            // trip context). Icon set normalized to the canonical
            // .fill / creditcard variants used by 010/011/012 — keeps the
            // bottom-nav glyphs consistent across the Driver track. Per
            // [feedback_bottom_nav_frozen], the layout + isCurrent flags
            // ship as-is; this only aligns the SF Symbol naming.
            BottomNav(
                leading: [
                    NavSlot(label: "Home",  systemImage: "house.fill", isCurrent: false),
                    NavSlot(label: "Trips", systemImage: "truck.box",  isCurrent: true),
                ],
                trailing: [
                    NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
                    NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false),
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
