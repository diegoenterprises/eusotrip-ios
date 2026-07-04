//
//  400_CatalystConvoyPlatooning.swift
//  EusoTrip 2027 UI — Catalyst track · carrier network-intelligence band
//
//  Moment: Michael Eusorone runs three Eusotrans units on the same I-10 W lane and
//          links them into a drafting platoon so the trailing trucks burn less fuel.
//          This is the live coordinator — NOT the home/detail skeleton and NOT a
//          stat dashboard: a MAP HERO dominates (route + three nose-to-tail truck
//          markers + live gap callouts + fuel-save badge), a compact metric band
//          reads the platoon's fuel save / mean gap / draft time, and a roster lists
//          each unit's role (lead/middle/rear), draft gap and link state. The
//          dispatcher tightens spacing or pauses the convoy in one tap.
//
//  SwiftUI twin of:
//    03 Catalyst/Dark-SVG/400 Catalyst Convoy Platooning.svg
//
//  Web peer: /catalyst/dispatch/convoy.
//
//  LIVE MAP WIRING (this fire — real per-truck GPS, no fabricated coords):
//    The map hero renders each convoy member as a REAL .truck puck on
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
//         server computes via haversine. EACH lat/lng is a real GPS fix —
//         the same kind of feed §375/§376 read via catalysts.getMyDrivers
//         "lat,lng", but here convoy-native (lead/load/rear formation).
//    Every fix is coord-gated (!(lat==0 && lng==0)); no active convoy or no
//    parseable position ⇒ honest "awaiting convoy position feed" placeholder,
//    never a hand-drawn route. The puck id is the member userId → tap routes
//    to that member.
//
//  Still WIRE-flagged (no coord dependency; not part of the map build):
//    • rear-gap alert            → convoy.getConvoyAlerts      (convoy.ts:601)
//    • "Optimize spacing" CTA    → convoy.optimizeConvoyRoute  (convoy.ts:325)
//    • "Pause convoy" CTA        → convoy.updateConvoyStatus   (convoy.ts:218)
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
    [NavSlot(label: "Home",     systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "tray.full",  isCurrent: true)]
}

private func catalystNavTrailing_400() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
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

// MARK: - Notifications

extension Notification.Name {
    static let eusoCatalystConvoyOptimize_400 = Notification.Name("eusoCatalystConvoyOptimize")
    static let eusoCatalystConvoyPause_400    = Notification.Name("eusoCatalystConvoyPause")
    static let eusoCatalystConvoyAlert_400    = Notification.Name("eusoCatalystConvoyAlert")
}

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

// MARK: - Body

private struct ConvoyBody_400: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    // Representative labels seed (non-coordinate spec text); reload() refreshes
    // the distance lines from real separation distances when present.
    @State private var vm: ConvoyVM_400 = convoySeed_400

    // LIVE convoy + real per-truck GPS positions (the map hero source of truth).
    @State private var activeConvoy: ActiveConvoyRow_400? = nil
    @State private var positions: [ConvoyPosition_400] = []
    @State private var mapLoading: Bool = true

    /// Preview-only injection — when set, the body paints the seeded live map
    /// without a network session (mirrors §375's previewSeed pattern).
    var previewSeedPositions: [ConvoyPosition_400]? = nil
    var previewSeedConvoy: ActiveConvoyRow_400? = nil

    private var isDark: Bool { scheme == .dark }

    // MARK: Real-coordinate derivations (every fix coord-gated)

    /// A position's real fix, or nil at null island (never frame on 0,0).
    private func fix(_ p: ConvoyPosition_400) -> HereLatLng? {
        guard !(p.lat == 0 && p.lng == 0) else { return nil }
        return HereLatLng(p.lat, p.lng)
    }

    /// Real fixes ordered nose-to-tail (lead → load → rear) for the polyline.
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

    /// Map center = the load (middle) truck's real fix, else the first real fix.
    private var mapCenter: HereLatLng? {
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

    private var hasLiveFormation: Bool { mapCenter != nil && !truckMarkers.isEmpty }

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
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s7)
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await reload() }
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ CATALYST · CONVOY").font(EType.micro).tracking(1.0)
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

    // MARK: Map hero — LIVE platoon formation on the in-house HERE basemap
    //
    // Replaces the prior hand-drawn Path/.position() schematic entirely. Each
    // .truck puck sits on a REAL location_history fix from
    // convoy.getConvoyPositions; the nose-to-tail polyline links the ordered
    // lead → load → rear fixes. tilt==0 register ⇒ flat catalyst board (the
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
                    route: orderedFixes.map { $0.fix },
                    baseLayers: convoyMapLayers,
                    addOns: .shipperTracking,
                    showTicker: false,
                    onSelectMarker: { userId in
                        // Tap a member puck → open that member's dispatch detail.
                        NotificationCenter.default.post(
                            name: .eusoCatalystConvoyAlert_400, object: nil,
                            userInfo: ["source": "400_CatalystConvoyPlatooning", "memberUserId": userId])
                    }
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
                        Text("LIVE · \(truckMarkers.count)/3 GPS · convoy positions")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.42)))
                    }
                }.padding(14)
            }
            .frame(height: 216)
        } else {
            convoyMapPlaceholder
        }
    }

    /// Real-coordinate map layers: nose-to-tail polyline over the ordered fixes
    /// + a .truck puck per member. Empty when no real fix resolves.
    private var convoyMapLayers: [HereMapLayer] {
        var layers: [HereMapLayer] = []
        let line = orderedFixes.map { $0.fix }
        if line.count >= 2 {
            layers.append(.route(polyline: line, colorHex: "#1473FF"))
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
                Text(mapLoading ? "Locating convoy formation…" : "Awaiting convoy position feed")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(mapLoading
                     ? "convoy.getConvoyPositions · location_history heartbeat"
                     : "No active convoy with a live GPS fix · pucks draw on real coordinates only")
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
            // WIRE: convoy.getConvoyAlerts (convoy.ts:601) — open the rear-gap alert detail
            NotificationCenter.default.post(name: .eusoCatalystConvoyAlert_400, object: nil,
                userInfo: ["source": "400_CatalystConvoyPlatooning"])
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
                // WIRE: convoy.optimizeConvoyRoute (convoy.ts:325) + convoy.predictOptimalSpacing (convoy.ts:493)
                NotificationCenter.default.post(name: .eusoCatalystConvoyOptimize_400, object: nil,
                    userInfo: ["source": "400_CatalystConvoyPlatooning"])
            } label: {
                Text("Optimize spacing").font(EType.bodyStrong).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            Button {
                // WIRE: convoy.updateConvoyStatus (convoy.ts:218) — status → paused
                NotificationCenter.default.post(name: .eusoCatalystConvoyPause_400, object: nil,
                    userInfo: ["source": "400_CatalystConvoyPlatooning"])
            } label: {
                Text("Pause convoy").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 144, height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            }
            .buttonStyle(.plain)
        }
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
        // Preview path — no live session; paint the seeded live formation.
        if let seed = previewSeedPositions {
            self.activeConvoy = previewSeedConvoy
            self.positions = seed
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
                return
            }
            self.activeConvoy = convoy

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
        }
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
        vm.meanGapSub = "feet · live separation · location_history"
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
