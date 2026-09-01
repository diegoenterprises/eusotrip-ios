//
//  400_CatalystConvoyPlatooning.swift
//  EusoTrip 2027 UI — Catalyst track · carrier network-intelligence band
//
//  Moment: Michael Eusorone runs three Eusotrans units on the same I-10 W lane and
//          links them into a drafting platoon so the trailing trucks burn less fuel.
//          This is the convoy coordinator — NOT the home/detail skeleton and NOT a
//          stat dashboard: a MAP HERO dominates (canonical load route + three
//          nose-to-tail observation markers + gap callouts + fuel-save badge), a compact metric band
//          reads the platoon's fuel save / mean gap / draft time, and a roster lists
//          each unit's role (lead/middle/rear), draft gap and link state. The
//          dispatcher tightens spacing or pauses the convoy in one tap.
//
//  SwiftUI twin of:
//    03 Catalyst/Dark-SVG/400 Catalyst Convoy Platooning.svg
//
//  Web peer: /catalyst/dispatch/convoy.
//
//  MAP AUTHORITY (real per-truck observations + exact load route):
//    The map hero renders each convoy member as a .truck observation on
//    HereLiveMapView, sourced one-hop from two procs that EXIST and return
//    real coordinates off the `location_history` table (convoy router is
//    mounted as `convoy:` at server/routers.ts:2122):
//      1. convoy.getActiveConvoys {limit}  (convoy.ts:705) → the active
//         convoy row → its `id` (convoyId) + loadId + lead/load/rear userIds
//         + currentLead/RearDistance. No coord-by-name needed; this yields
//         the convoyId the position feed keys on.
//      2. convoy.getConvoyPositions {convoyId} (convoy.ts:173) → REAL
//         positions:[{userId, role:"lead"|"load"|"rear", lat, lng, speed,
//         heading, timestamp}] selected from location_history.latitude/
//         longitude (convoy.ts:191-192), plus leadDistance/rearDistance the
//         server computes from reported fixes. EACH lat/lng is an observation —
//         the same kind of feed §375/§376 read via catalysts.getMyDrivers
//         "lat,lng", but here convoy-native (lead/load/rear formation).
//    The route itself is never inferred from those observations. The convoy's
//    exact loadId resolves the current server-owned active_job route.plan; only
//    its released, rights-valid, current, checksum-bound independent geometry
//    members render through `.eusoRoute`. Missing route authority remains an
//    honest pending/degraded state. The puck id is the member userId.
//
//  Action wiring:
//    • rear-gap alert            → convoy.getConvoyAlerts
//    • "Optimize spacing" CTA    → convoy.predictOptimalSpacing
//    • "Pause convoy" CTA        → convoy.updateConvoyStatus
//  The fuel-save / draft-time figures have NO DB column (no coordinate
//  source) — they stay representative labels, clearly NOT coordinate data.
//  RBAC write gate catalystProcedure (_core/trpc.ts:150). transportMode=truck; US lane.
//  Persona: Eusotrans LLC · Michael Eusorone lead unit 142 · USDOT 3 194 882.
//
//  Bottom nav (Catalyst variant): HOME · DISPATCH · [orb] · WALLET · ME (DISPATCH current).
//

import SwiftUI

// MARK: - Wrapper

struct CatalystConvoyPlatooningScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            ConvoyBody_400()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_400(),
                trailing: catalystNavTrailing_400(),
                orbState: .idle
            )
        }
    }
}

// MARK: - Catalyst BottomNav (HOME · DISPATCH · [orb] · WALLET · ME — DISPATCH current)

private func catalystNavLeading_400() -> [NavSlot] {
    CarrierNavRoute.leading(current: .loads)
}

private func catalystNavTrailing_400() -> [NavSlot] {
    CarrierNavRoute.trailing(current: .loads)
}

// MARK: - View model (file-local)

private enum ConvoyRole_400 { case lead, middle, rear }

private struct ConvoyUnit_400: Identifiable {
    let id: String              // unit number
    let unit: String            // "142"
    let driverLine: String      // "Michael Eusorone · Unit 142"
    let detailLine: String      // mono spec / gap line
    let role: ConvoyRole_400
    let roleLabel: String       // "LEAD" / "DRAFTING" / "CLOSING"
    let rightNote: String       // "setting pace" / "linked 2h 14m" / "ease to 1,440 ft"
    let noteColor: Color
}

private struct ConvoyVM_400 {
    let lane: String                // "I-10 W · 62 mph"
    let fuelSaveBadge: String       // "−9.4% FUEL"
    let fuelSave: String            // "−9.4%"
    let fuelSaveSub: String         // "$0.21/mi"
    var meanGap: String             // "1,465" — overwritten with real separation
    var meanGapSub: String          // "feet · target 1,400"
    let draftTime: String           // "2h 14m"
    let draftSub: String            // "linked · 138 mi left"
    let units: [ConvoyUnit_400]
    let alertTitle: String          // "ESang: rear unit 90 ft past draft window"
    let alertSub: String            // "Auto-optimize recovers the −11% draft savings"
}

// Representative seed mirrors the SVG verbatim. The fuel-save / draft-time /
// roster spec strings have NO coordinate or DB source, so they remain the
// canonical Code/ labels (clearly NOT coordinate data). The LIVE map hero is
// driven entirely by real GPS from convoy.getConvoyPositions — never from
// this seed. The lane/distance lines are overwritten with real separation
// distances on hydrate where the server returns them.
private let convoySeed_400 = ConvoyVM_400(
    lane: "I-10 W · 62 mph", fuelSaveBadge: "−9.4% FUEL",
    fuelSave: "−9.4%", fuelSaveSub: "$0.21/mi",
    meanGap: "1,465", meanGapSub: "feet · target 1,400",
    draftTime: "2h 14m", draftSub: "linked · 138 mi left",
    units: [
        ConvoyUnit_400(id: "142", unit: "142", driverLine: "Michael Eusorone · Unit 142",
                       detailLine: "Freightliner Cascadia · USDOT 3 194 882", role: .lead,
                       roleLabel: "LEAD", rightNote: "setting pace", noteColor: Brand.success),
        ConvoyUnit_400(id: "207", unit: "207", driverLine: "D. Okafor · Unit 207",
                       detailLine: "gap 1,420 ft · drafting · −11%", role: .middle,
                       roleLabel: "DRAFTING", rightNote: "linked 2h 14m", noteColor: Color(hex: 0x52606D)),
        ConvoyUnit_400(id: "318", unit: "318", driverLine: "L. Brandt · Unit 318",
                       detailLine: "gap 1,510 ft · 90 ft over window", role: .rear,
                       roleLabel: "CLOSING", rightNote: "ease to 1,440 ft", noteColor: Brand.warning),
    ],
    alertTitle: "ESang: rear unit 90 ft past draft window",
    alertSub: "Auto-optimize recovers the −11% draft savings"
)

// MARK: - Wire models (exact convoy.getActiveConvoys / getConvoyPositions shapes)

/// Mirrors a `convoy.getActiveConvoys` row (convoy.ts:711-721). Carries the
/// convoyId the position feed keys on + the lead/load/rear userIds and the
/// server's last-known separation distances (meters).
private struct ActiveConvoyRow_400: Decodable, Identifiable, Hashable {
    let id: Int
    let loadId: Int?
    let status: String
    let leadUserId: Int?
    let loadUserId: Int?
    let rearUserId: Int?
    let currentLeadDistance: Double?
    let currentRearDistance: Double?
    let startedAt: String?
}

/// Mirrors one entry of `convoy.getConvoyPositions.positions` (convoy.ts:188-196).
/// `lat`/`lng` are REAL fixes selected from location_history.latitude/longitude.
private struct ConvoyPosition_400: Decodable, Identifiable, Hashable {
    let userId: Int
    let role: String          // "lead" | "load" | "rear"
    let lat: Double
    let lng: Double
    let speed: Double?
    let heading: Double?
    let timestamp: String?
    var id: Int { userId }
}

/// Mirrors the `convoy.getConvoyPositions` envelope (convoy.ts:214).
private struct ConvoyPositions_400: Decodable, Hashable {
    let convoyId: Int
    let positions: [ConvoyPosition_400]
    let leadDistance: Double?
    let rearDistance: Double?
    let status: String
}

private struct ConvoyLimitInput_400: Encodable { let limit: Int }
private struct ConvoyIdInput_400: Encodable { let convoyId: Int }
private struct ConvoyAlert_400: Decodable, Identifiable, Hashable {
    let id: String
    let type: String?
    let severity: String?
    let message: String
    let timestamp: String?
}
private struct SpacingInput_400: Encodable {
    let convoyId: Int
    let currentSpeed: Double?
}
private struct SpacingOut_400: Decodable {
    let recommendedLeadDistance: Int?
    let recommendedRearDistance: Int?
    let recommendedMaxSpeed: Int?
    let confidence: Int?
    let model: String?
    let warnings: [String]?
}
private struct ConvoyStatusInput_400: Encodable {
    let convoyId: Int
    let status: String
}
private struct ConvoyStatusOut_400: Decodable {
    let success: Bool?
}

// MARK: - Body

private struct ConvoyBody_400: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    // Representative labels seed (non-coordinate spec text); reload() refreshes
    // the distance lines from real separation distances when present.
    @State private var vm: ConvoyVM_400 = convoySeed_400

    // Convoy identity + reported per-truck positions.
    @State private var activeConvoy: ActiveConvoyRow_400? = nil
    @State private var positions: [ConvoyPosition_400] = []
    @State private var mapLoading: Bool = true
    @State private var canonicalRouteLines: [[HereLatLng]] = []
    @State private var canonicalRouteVersion: Int? = nil
    @State private var canonicalRouteStatus: String? = nil
    @State private var alerts: [ConvoyAlert_400] = []
    @State private var showAlerts = false
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil
    @State private var actionBusy = false

    /// Preview-only injection — when set, the body paints the seeded live map
    /// without a network session (mirrors §375's previewSeed pattern).
    var previewSeedPositions: [ConvoyPosition_400]? = nil
    var previewSeedConvoy: ActiveConvoyRow_400? = nil

    private var isDark: Bool { scheme == .dark }

    // MARK: Real-coordinate derivations (every fix coord-gated)

    /// A position's real fix, or nil at null island (never frame on 0,0).
    private func fix(_ p: ConvoyPosition_400) -> HereLatLng? {
        guard let coordinate = LatLongParser.validatedCoordinate(
            latitude: p.lat,
            longitude: p.lng
        ) else { return nil }
        return HereLatLng(coordinate.latitude, coordinate.longitude)
    }

    /// Reported fixes ordered nose-to-tail for marker framing only. These
    /// observations are never joined into route geometry.
    private var orderedFixes: [(role: String, fix: HereLatLng)] {
        let rank: [String: Int] = ["lead": 0, "load": 1, "rear": 2]
        return positions
            .sorted { (rank[$0.role] ?? 9) < (rank[$1.role] ?? 9) }
            .compactMap { p in fix(p).map { (p.role, $0) } }
    }

    /// Truck pucks for every real fix; id = userId so a tap routes to that member.
    private var truckMarkers: [HereMarker] {
        positions.compactMap { p in
            guard let f = fix(p) else { return nil }
            return HereMarker(at: f, kind: .truck, label: roleLabel(p.role), id: String(p.userId))
        }
    }

    /// Canonical route wins camera framing; otherwise use a reported convoy fix.
    private var mapCenter: HereLatLng? {
        if let routeStart = canonicalRouteLines.lazy.compactMap(\.first).first {
            return routeStart
        }
        if let load = positions.first(where: { $0.role == "load" }), let f = fix(load) { return f }
        return orderedFixes.first?.fix
    }

    private func roleLabel(_ role: String) -> String {
        switch role {
        case "lead": return "LEAD"
        case "load": return "DRAFTING"
        case "rear": return "REAR"
        default:     return role.uppercased()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            VStack(alignment: .leading, spacing: Space.s4) {
                mapHero
                metricBand
                rosterSection
                alertRow
                ctaPair
                actionFeedback
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s7)
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await reload() }
        }
        .eusoRefreshHandler { await reload() }
        .sheet(isPresented: $showAlerts) { alertSheet }
    }

    // MARK: TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EusoTripEyebrow(verbatim: "CATALYST · CONVOY").font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("I-10 W · ACTIVE").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary).frame(width: 28, height: 28)
                    .accessibilityLabel("Back to Dispatch")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Platoon").font(EType.display).foregroundStyle(palette.textPrimary)
                    Text("Eusotrans LLC · 3-truck convoy · DAT-verified link")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5).padding(.bottom, Space.s3)
    }

    // MARK: Map hero — canonical load route + reported convoy formation
    //
    // Replaces the prior hand-drawn Path/.position() schematic entirely. Each
    // .truck puck sits on a location_history observation from
    // convoy.getConvoyPositions. The line is exclusively the exact current
    // route.plan bound to the convoy load; truck observations are never linked
    // into geometry. tilt==0 register ⇒ flat catalyst board (the
    // dispatcher's overhead formation view, not the driver first-person lane).

    @ViewBuilder
    private var mapHero: some View {
        if let center = mapCenter {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(LinearGradient.diagonal)
                HereLiveMapView(
                    center: center,
                    zoom: 9,
                    interactive: true,
                    route: [],
                    baseLayers: convoyMapLayers,
                    addOns: .shipperTracking,
                    showTicker: false,
                    mapModeContext: .primary(.truck),
                    liveOperationsStatus: .init(
                        availability: .degraded,
                        sourceLabel: "Convoy telemetry",
                        detail: "Convoy positions available; freshness not supplied",
                        observationCount: orderedFixes.count
                    ),
                    onSelectMarker: { userId in selectMember(userId) }
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous))
                .padding(1.5)
                // overlays — lane label + fuel-save badge (representative labels,
                // NOT coordinate data; the formation itself is the real read)
                VStack {
                    HStack(alignment: .top) {
                        Text(vm.lane).font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: 0x0D1117))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(.white.opacity(0.92)))
                        Spacer()
                        Text(vm.fuelSaveBadge)
                            .font(.system(size: 14, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Brand.success))
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        Text("REPORTED · \(truckMarkers.count)/3 POSITION OBSERVATIONS")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.42)))
                    }
                }.padding(14)
                if let canonicalRouteStatus {
                    VStack {
                        Spacer()
                        HStack {
                            Text(canonicalRouteStatus)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.black.opacity(0.58)))
                            Spacer()
                        }
                    }
                    .padding(14)
                    .padding(.bottom, 24)
                }
            }
            .frame(height: 216)
        } else {
            convoyMapPlaceholder
        }
    }

    /// Exact current load-route members plus a .truck marker per reported fix.
    /// Discontinuous route members remain independent; no observation-derived
    /// or endpoint-derived line is ever introduced.
    private var convoyMapLayers: [HereMapLayer] {
        var layers: [HereMapLayer] = canonicalRouteLines.enumerated().map { index, line in
            .eusoRoute(
                polyline: line,
                state: .active,
                label: index == 0
                    ? "Eusorone truck convoy route plan version \(canonicalRouteVersion ?? 0)"
                    : nil
            )
        }
        if !truckMarkers.isEmpty {
            layers.append(.markers(truckMarkers))
        }
        return layers
    }

    /// Honest empty state — no active convoy or no parseable GPS fix yet.
    /// Never a fabricated route; the map only draws on real coordinates.
    private var convoyMapPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(isDark ? Color(hex: 0x10141B) : Color(hex: 0xDDE5EF))
            VStack(spacing: 8) {
                Image(systemName: mapLoading ? "dot.radiowaves.left.and.right" : "map")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(mapLoading ? "Resolving convoy authority…" : "Awaiting convoy map authority")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(mapLoading
                     ? "Canonical load route and convoy observations are being resolved"
                     : "No canonical route or reported convoy position is currently available")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 216)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .redacted(reason: mapLoading ? .placeholder : [])
    }

    // MARK: Metric band

    private var metricBand: some View {
        HStack(spacing: Space.s3) {
            metricTile("FUEL SAVE", vm.fuelSave, sub: vm.fuelSaveSub,
                       valueStyle: AnyShapeStyle(LinearGradient.diagonal), subColor: Brand.success)
            metricTile("MEAN GAP", vm.meanGap, sub: vm.meanGapSub,
                       valueStyle: AnyShapeStyle(palette.textPrimary), subColor: palette.textSecondary)
            metricTile("DRAFT TIME", vm.draftTime, sub: vm.draftSub,
                       valueStyle: AnyShapeStyle(palette.textPrimary), subColor: palette.textSecondary)
        }
    }

    private func metricTile(_ label: String, _ value: String, sub: String,
                            valueStyle: AnyShapeStyle, subColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 24, weight: .semibold).monospacedDigit())
                .foregroundStyle(valueStyle)
            Text(sub).font(EType.caption).foregroundStyle(subColor)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: Roster

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("PLATOON ROSTER · 3 UNITS").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("nose-to-tail").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(vm.units.enumerated()), id: \.element.id) { idx, u in
                    rosterRow(u)
                    if idx < vm.units.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 52)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func rosterRow(_ u: ConvoyUnit_400) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm + 2)
                    .fill(u.role == .lead ? AnyShapeStyle(LinearGradient.diagonal)
                          : AnyShapeStyle((u.role == .rear ? Brand.hazmat : Brand.blue).opacity(0.14)))
                Text(u.unit).font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(u.role == .lead ? AnyShapeStyle(Color.white)
                                     : AnyShapeStyle(u.role == .rear ? Brand.warning : Brand.blue))
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(u.driverLine).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(u.detailLine).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                rolePill(u)
                Text(u.rightNote).font(.system(size: 11, weight: .semibold)).foregroundStyle(u.noteColor)
            }
        }
        .padding(Space.s3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(u.driverLine), \(u.roleLabel), \(u.rightNote)")
    }

    private func rolePill(_ u: ConvoyUnit_400) -> some View {
        let bg: AnyShapeStyle
        let fg: Color
        switch u.role {
        case .lead:   bg = AnyShapeStyle(LinearGradient.primary);              fg = .white
        case .middle: bg = AnyShapeStyle(Brand.success.opacity(0.14));         fg = Brand.success
        case .rear:   bg = AnyShapeStyle(Brand.hazmat.opacity(0.16));          fg = Brand.warning
        }
        return Text(u.roleLabel).font(.system(size: 10, weight: .heavy)).tracking(0.6)
            .foregroundStyle(fg).padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(bg))
    }

    // MARK: Alert + CTA

    private var alertRow: some View {
        Button {
            Task { await openAlerts() }
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear],
                                                 center: .init(x: 0.35, y: 0.30),
                                                 startRadius: 0, endRadius: 16))
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.alertTitle).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(vm.alertSub).font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                Task { await optimizeSpacing() }
            } label: {
                Text("Optimize spacing").font(EType.bodyStrong).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(actionBusy)
            Button {
                Task { await pauseConvoy() }
            } label: {
                Text("Pause convoy").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 144, height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            }
            .buttonStyle(.plain)
            .disabled(actionBusy)
        }
    }

    @ViewBuilder
    private var actionFeedback: some View {
        if let actionError {
            Text(actionError)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.danger.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.danger.opacity(0.35)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        } else if let actionMessage {
            Text(actionMessage)
                .font(EType.caption)
                .foregroundStyle(Brand.success)
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.success.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.success.opacity(0.35)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private var alertSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if alerts.isEmpty {
                        EusoEmptyState(
                            systemImage: "checkmark.shield",
                            title: "No convoy alerts",
                            subtitle: "The live convoy alert engine did not return a separation, speed, or GPS-staleness alert for this convoy.")
                    } else {
                        ForEach(alerts) { alert in
                            VStack(alignment: .leading, spacing: 6) {
                                Text((alert.severity ?? "info").uppercased())
                                    .font(EType.micro)
                                    .foregroundStyle(alertColor(alert.severity))
                                Text(alert.message)
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textPrimary)
                                if let ts = alert.timestamp {
                                    Text(ts)
                                        .font(EType.mono(.caption))
                                        .foregroundStyle(palette.textTertiary)
                                }
                            }
                            .padding(Space.s3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.bgCard)
                            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Convoy alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showAlerts = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func alertColor(_ severity: String?) -> Color {
        switch severity?.lowercased() {
        case "critical": return Brand.danger
        case "warning": return Brand.warning
        default: return palette.textTertiary
        }
    }

    private func selectMember(_ userId: String) {
        actionError = nil
        actionMessage = "Convoy member selected. Full member detail opens from the truck's own live position marker."
    }

    private func openAlerts() async {
        actionMessage = nil
        actionError = nil
        guard let convoyId = activeConvoy?.id else {
            actionError = "No active convoy is loaded yet."
            return
        }
        do {
            alerts = try await EusoTripAPI.shared.query(
                "convoy.getConvoyAlerts",
                input: ConvoyIdInput_400(convoyId: convoyId))
            showAlerts = true
        } catch {
            actionError = convoyFailureCopy_400(error, noun: "convoy alerts")
        }
    }

    private func optimizeSpacing() async {
        actionBusy = true
        actionMessage = nil
        actionError = nil
        defer { actionBusy = false }
        guard let convoyId = activeConvoy?.id else {
            actionError = "No active convoy is loaded yet."
            return
        }
        do {
            let out: SpacingOut_400 = try await EusoTripAPI.shared.query(
                "convoy.predictOptimalSpacing",
                input: SpacingInput_400(convoyId: convoyId, currentSpeed: averageSpeedMph()))
            let lead = out.recommendedLeadDistance.map { "\($0)m lead" } ?? "lead spacing pending"
            let rear = out.recommendedRearDistance.map { "\($0)m rear" } ?? "rear spacing pending"
            let speed = out.recommendedMaxSpeed.map { "\($0) mph max" } ?? "speed pending"
            let confidence = out.confidence.map { "\($0)% confidence" } ?? "confidence pending"
            let warning = out.warnings?.first.map { " · \($0)" } ?? ""
            actionMessage = "Spacing guidance: \(lead), \(rear), \(speed) · \(confidence)\(warning)"
        } catch {
            actionError = convoyFailureCopy_400(error, noun: "spacing guidance")
        }
    }

    private func pauseConvoy() async {
        actionBusy = true
        actionMessage = nil
        actionError = nil
        defer { actionBusy = false }
        guard let convoyId = activeConvoy?.id else {
            actionError = "No active convoy is loaded yet."
            return
        }
        do {
            let out: ConvoyStatusOut_400 = try await EusoTripAPI.shared.mutation(
                "convoy.updateConvoyStatus",
                input: ConvoyStatusInput_400(convoyId: convoyId, status: "paused"))
            if out.success == false {
                actionError = "Convoy pause did not persist."
                return
            }
            actionMessage = "Convoy paused and broadcast through the convoy status service."
            await reload()
        } catch {
            actionError = convoyFailureCopy_400(error, noun: "convoy pause")
        }
    }

    private func averageSpeedMph() -> Double? {
        let speeds = positions.compactMap { $0.speed }.filter { $0 > 0 }
        guard !speeds.isEmpty else { return nil }
        return speeds.reduce(0, +) / Double(speeds.count)
    }

    // MARK: Network
    //
    // Live chain (real per-truck GPS, no Swift client needed — EusoTripAPI.query
    // is generic, same as §375 calling catalysts.getMyDrivers by name):
    //   convoy.getActiveConvoys {limit} → first active convoy → its id
    //     → convoy.getConvoyPositions {convoyId} → real lead/load/rear fixes.
    // The map hero hydrates from `positions`; the distance lines hydrate from
    // the server's real separation distances where present. The fuel-save /
    // draft-time labels have no coordinate source and stay representative.
    private func reload() async {
        // Preview path — no session; paint observation markers only. Preview
        // coordinates never become route geometry.
        if let seed = previewSeedPositions {
            self.activeConvoy = previewSeedConvoy
            self.positions = seed
            self.canonicalRouteLines = []
            self.canonicalRouteVersion = nil
            self.canonicalRouteStatus = "Canonical route unavailable in preview"
            self.mapLoading = false
            applyRealDistances()
            return
        }

        mapLoading = true
        defer { mapLoading = false }

        do {
            let convoys: [ActiveConvoyRow_400] = try await EusoTripAPI.shared.query(
                "convoy.getActiveConvoys",
                input: ConvoyLimitInput_400(limit: 20)
            )
            // First active convoy is the platoon subject for this surface.
            guard let convoy = convoys.first else {
                self.activeConvoy = nil
                self.positions = []
                self.canonicalRouteLines = []
                self.canonicalRouteVersion = nil
                self.canonicalRouteStatus = "No active convoy load is bound"
                return
            }
            self.activeConvoy = convoy

            await refreshCanonicalRoute(loadId: convoy.loadId)

            let env: ConvoyPositions_400? = try? await EusoTripAPI.shared.query(
                "convoy.getConvoyPositions",
                input: ConvoyIdInput_400(convoyId: convoy.id)
            )
            self.positions = env?.positions ?? []
            applyRealDistances(positionEnvelope: env)
        } catch {
            // Soft-fail to the honest placeholder; never fabricate a formation.
            self.activeConvoy = nil
            self.positions = []
            self.canonicalRouteLines = []
            self.canonicalRouteVersion = nil
            self.canonicalRouteStatus = error.eusoUserCopy
        }
    }

    /// Resolves only the exact load identity supplied by the authenticated
    /// convoy response. No endpoint, mode, asset fact, or geometry crosses the
    /// client boundary.
    @MainActor
    private func refreshCanonicalRoute(loadId: Int?) async {
        canonicalRouteLines = []
        canonicalRouteVersion = nil
        canonicalRouteStatus = "Verified active route is still being prepared"
        guard let loadId, loadId > 0 else {
            canonicalRouteStatus = "Convoy is not bound to a persisted load"
            return
        }
        do {
            let result = try await CanonicalRoutePlanClient.shared.planLoad(
                id: loadId,
                purpose: .activeJob
            )
            switch result {
            case .persisted(let persisted):
                applyCanonicalRoute(persisted.route)
            case .pending(let pending):
                canonicalRouteStatus = pending.blockers.first?.message
                    ?? "Canonical truck route pending verified authority"
                await readExistingCanonicalRoute(loadId: loadId)
            }
        } catch {
            canonicalRouteStatus = error.eusoUserCopy
            await readExistingCanonicalRoute(loadId: loadId)
        }
    }

    @MainActor
    private func readExistingCanonicalRoute(loadId: Int) async {
        do {
            applyCanonicalRoute(
                try await CanonicalRoutePlanClient.shared.getBoundLoad(id: loadId)
            )
        } catch {
            if canonicalRouteStatus == nil { canonicalRouteStatus = error.eusoUserCopy }
        }
    }

    @MainActor
    private func applyCanonicalRoute(_ route: CanonicalRoutePlanClient.BoundRoutePlan) {
        guard route.plan.purpose == .activeJob,
              route.plan.identity.mode == .truck,
              let payload = route.rendererPayload else {
            canonicalRouteLines = []
            canonicalRouteVersion = nil
            canonicalRouteStatus = "Canonical truck route exists but is not released for rendering"
            return
        }
        canonicalRouteLines = payload.lines
        canonicalRouteVersion = payload.identity.version
        canonicalRouteStatus = nil
    }

    /// Overwrite the mean-gap / draft distance lines with REAL separation
    /// distances (meters → feet) from the server when available; otherwise the
    /// representative seed line stands. Coordinate-derived, not fabricated.
    private func applyRealDistances(positionEnvelope env: ConvoyPositions_400? = nil) {
        let leadM = env?.leadDistance ?? activeConvoy?.currentLeadDistance
        let rearM = env?.rearDistance ?? activeConvoy?.currentRearDistance
        let meters = [leadM, rearM].compactMap { $0 }
        guard !meters.isEmpty else { return }
        let meanFeet = (meters.reduce(0, +) / Double(meters.count)) * 3.28084
        vm.meanGap = numberFmt_400(meanFeet)
        vm.meanGapSub = "feet · reported separation · location_history"
    }

    private func numberFmt_400(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(Int(v))
    }
}

// MARK: - Preview seed (real-shape convoy + lead/load/rear GPS fixes)

/// I-10 W nose-to-tail formation (real-shape positions; preview only). These
/// mirror the convoy.getConvoyPositions envelope so the live map hero renders
/// in #Preview without a network session — in the app the SAME shape arrives
/// from location_history via the proc.
private let convoyPreviewConvoy_400 = ActiveConvoyRow_400(
    id: 4001, loadId: 88231, status: "active",
    leadUserId: 142, loadUserId: 207, rearUserId: 318,
    currentLeadDistance: 433, currentRearDistance: 460, startedAt: nil
)

private let convoyPreviewPositions_400: [ConvoyPosition_400] = [
    ConvoyPosition_400(userId: 142, role: "lead", lat: 29.9012, lng: -95.6210, speed: 62, heading: 250, timestamp: nil),
    ConvoyPosition_400(userId: 207, role: "load", lat: 29.8771, lng: -95.6602, speed: 61, heading: 250, timestamp: nil),
    ConvoyPosition_400(userId: 318, role: "rear", lat: 29.8534, lng: -95.6981, speed: 60, heading: 250, timestamp: nil),
]

@MainActor
private func convoyPreviewBody_400() -> ConvoyBody_400 {
    var body = ConvoyBody_400()
    body.previewSeedConvoy = convoyPreviewConvoy_400
    body.previewSeedPositions = convoyPreviewPositions_400
    return body
}

private struct CatalystConvoyPreview_400: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            convoyPreviewBody_400()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_400(),
                trailing: catalystNavTrailing_400(),
                orbState: .idle
            )
        }
    }
}

// MARK: - Previews

#Preview("400 · Catalyst · Convoy · Night") {
    CatalystConvoyPreview_400(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("400 · Catalyst · Convoy · Afternoon") {
    CatalystConvoyPreview_400(theme: Theme.light)
        .preferredColorScheme(.light)
}

// MARK: - Operator-facing failure copy

/// Operator-language reason a convoy action failed.
///
/// The caught error is still available for logging; the catalyst running
/// the convoy sees a sentence they can act on, never a raw `NSError`
/// description. `noun` names what failed ("convoy pause", "spacing
/// guidance") so the line stays specific.
fileprivate func convoyFailureCopy_400(_ error: Error, noun: String) -> String {
    if let api = error as? EusoTripAPIError {
        switch api {
        case .unauthenticated:
            return "Your session expired. Sign in again to keep running this convoy."
        case .forbidden(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "This account isn't cleared to control this convoy."
                : trimmed
        case .trpcError(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "The \(noun) was rejected. Reload the convoy and try again."
                : trimmed
        case .httpStatus(let code, _):
            return "The \(noun) didn't go through (code \(code)). Try again in a moment."
        case .decodingFailed:
            return "The \(noun) came back in a form this build can't read. Update the app, then retry."
        case .empty:
            return "Nothing came back for the \(noun). Reload the convoy and try again."
        case .notConfigured, .badURL:
            return "This device isn't set up for live convoy control yet. Restart the app and try again."
        case .queuedForOfflineReplay:
            return "You're offline — the \(noun) is queued and sends the moment you reconnect."
        }
    }
    if (error as NSError).domain == NSURLErrorDomain {
        return "No connection right now. The \(noun) didn't complete — hold the convoy and retry once you have signal."
    }
    return "The \(noun) didn't complete. Reload the convoy and try again."
}
