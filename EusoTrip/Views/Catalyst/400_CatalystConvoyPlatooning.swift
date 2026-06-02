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
//  tRPC wiring manifest (line-confirmed on disk this fire) — NONE of these
//  procedures has a Swift client method in EusoTripAPI yet (grep-verified:
//  no convoy/platoon surface on CatalystAPI or any client), so per the
//  house 0%-mock contract the Code/ representative seed figures are kept
//  and each missing call is flagged with a single WIRE marker below.
//    • map hero + roster        → convoy.getConvoy            (convoy.ts:135)
//    • live truck spacing        → convoy.getConvoyPositions   (convoy.ts:173)
//    • rear-gap alert            → convoy.getConvoyAlerts      (convoy.ts:601)
//    • "Optimize spacing" CTA    → convoy.optimizeConvoyRoute  (convoy.ts:325)
//                                  + convoy.predictOptimalSpacing (convoy.ts:493)
//    • "Pause convoy" CTA        → convoy.updateConvoyStatus   (convoy.ts:218)
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
    let meanGap: String             // "1,465"
    let meanGapSub: String          // "feet · target 1,400"
    let draftTime: String           // "2h 14m"
    let draftSub: String            // "linked · 138 mi left"
    let units: [ConvoyUnit_400]
    let alertTitle: String          // "ESang: rear unit 90 ft past draft window"
    let alertSub: String            // "Auto-optimize recovers the −11% draft savings"
}

// Representative seed mirrors the SVG verbatim. House 0%-mock: these are
// overwritten on hydrate once a convoy client lands; until then they are
// the canonical figures from the Code/ spec (no fabrication).
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

// MARK: - Body

private struct ConvoyBody_400: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    // House 0%-mock seed; reload() overwrites once a convoy client exists.
    @State private var vm: ConvoyVM_400 = convoySeed_400

    private var isDark: Bool { scheme == .dark }

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

    // MARK: Map hero — live platoon spacing

    private var mapHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(LinearGradient.diagonal)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                        .fill(isDark ? Color(hex: 0x10141B) : Color(hex: 0xDDE5EF))
                    // faint cross road
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h * 0.30))
                        p.addLine(to: CGPoint(x: w, y: h * 0.40))
                    }
                    .stroke(isDark ? Color(hex: 0x222A35) : Color(hex: 0xC7D2E0),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    // primary route I-10
                    Path { p in
                        p.move(to: CGPoint(x: w * 0.10, y: h * 0.88))
                        p.addCurve(to: CGPoint(x: w * 0.93, y: h * 0.18),
                                   control1: CGPoint(x: w * 0.34, y: h * 0.76),
                                   control2: CGPoint(x: w * 0.62, y: h * 0.44))
                    }
                    .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    Path { p in
                        p.move(to: CGPoint(x: w * 0.10, y: h * 0.88))
                        p.addCurve(to: CGPoint(x: w * 0.93, y: h * 0.18),
                                   control1: CGPoint(x: w * 0.34, y: h * 0.76),
                                   control2: CGPoint(x: w * 0.62, y: h * 0.44))
                    }
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 8]))
                    // gap callouts
                    Text("1,510 ft").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                        .position(x: w * 0.40, y: h * 0.68)
                    Text("1,420 ft").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                        .position(x: w * 0.66, y: h * 0.48)
                    // truck markers: rear, middle, lead along the route
                    truckMarker(.rear).position(x: w * 0.26, y: h * 0.78)
                    truckMarker(.middle).position(x: w * 0.55, y: h * 0.59)
                    truckMarker(.lead).position(x: w * 0.82, y: h * 0.30)
                    // overlays
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
                    }.padding(14)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous))
                .padding(1.5)
            }
        }
        .frame(height: 216)
    }

    private func truckMarker(_ role: ConvoyRole_400) -> some View {
        let stroke: Color = role == .lead ? .clear : (role == .rear ? Brand.warning : Brand.blue)
        return ZStack {
            Circle().fill(role == .lead ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Color.white))
                .overlay(Circle().strokeBorder(stroke, lineWidth: 2.4))
            Image(systemName: "box.truck.fill").font(.system(size: 11))
                .foregroundStyle(role == .lead ? Color.white : (role == .rear ? Brand.warning : Brand.blue))
        }
        .frame(width: role == .lead ? 28 : 26, height: role == .lead ? 28 : 26)
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
    // No convoy/platoon client exists on EusoTripAPI yet (grep-verified this
    // fire). When the convoy router lands a Swift client, hydrate `vm` here
    // from convoy.getConvoy + convoy.getConvoyPositions + convoy.getConvoyAlerts.
    // Until then the canonical Code/ seed stands (house 0%-mock contract).
    private func reload() async {
        // WIRE: convoy.getConvoy (convoy.ts:135) + convoy.getConvoyPositions (convoy.ts:173)
        // self.vm = <map from envelope>
    }
}

// MARK: - Previews

#Preview("400 · Catalyst · Convoy · Night") {
    CatalystConvoyPlatooningScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("400 · Catalyst · Convoy · Afternoon") {
    CatalystConvoyPlatooningScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
