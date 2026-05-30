//
//  398_CatalystBackhaulOptimizer.swift
//  EusoTrip — Catalyst track · carrier back-office growth band.
//
//  Verbatim iOS port of 03 Catalyst/Code/398_CatalystBackhaulOptimizer.swift
//  into the iOS house chrome (Shell + BottomNav). NOT the stamped home/detail
//  skeleton and NOT a generic header + card-list: the body is a DEADHEAD-vs-
//  LOADED hero comparison bar plus ranked return-load match cards, each
//  carrying its reposition (deadhead) miles, gross RPM, net-after-deadhead,
//  pickup window and a match score. Turns a free 612-mi empty run home out of
//  Dallas into a paid reposition in one tap.
//
//  CANONICAL PERSONA §12 — Michael Eusorone (Eusotrans LLC owner-op) ·
//  USDOT 3 194 882 · Belle Plaine IA. Web peer: /catalyst/backhaul.
//
//  tRPC wiring manifest (line-confirmed on disk this fire):
//    • ranked matches              → capacityPlanning.getBackhaulOptimizer  (capacityPlanning.ts:690)
//    • power-only / drop-trailer    → capacityPlanning.getPowerOnlyMatching  (capacityPlanning.ts:755)
//    • candidate loads near dropoff → loadBoard.search                       (loadBoard.ts)
//    • deadhead mileage             → routeOptimization.*                    (routeOptimization.ts)
//    • "Tender" CTA                 → loadBidding.createQuote                (loadBidding.ts)
//      (on win writes the loads row + blockchainAudit row, broadcasts
//       WS_EVENTS.LOAD_TENDERED on WS_CHANNELS.catalyst(carrierId))
//  RBAC: isolatedProcedure carrier-scope (capacityPlanning.ts:10).
//
//  HYDRATION HONESTY: the iOS EusoTripAPI does NOT yet expose a
//  `capacityPlanning` service (no getBackhaulOptimizer / getPowerOnlyMatching),
//  and loadBidding has no createQuote. Per house doctrine the representative
//  seed figures below mirror the SVG verbatim and are tagged "0% mock —
//  seeds overwritten on hydrate"; each missing procedure carries a // WIRE:
//  marker so the live envelope can replace the seed the moment the client
//  method lands. NO EusoTripAPI method is called that does not exist.
//
//  Bottom nav (Catalyst variant): HOME · DISPATCH · [orb] · WALLET · ME
//  (DISPATCH current).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen (house wrapper)

struct CatalystBackhaulOptimizerScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            BackhaulBody_398()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_398(),
                trailing: catalystNavTrailing_398(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_398() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_398() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",     isCurrent: false)]
}

// MARK: - View model (mirrors the Code/ fixture verbatim)

private enum BackhaulEquipment_398 { case dryVan, reefer, flatbed }

private struct BackhaulMatch_398: Identifiable {
    let id: String
    let lane: String          // "Dallas TX → Kansas City MO"
    let spec: String          // "53' Dry Van · 38k lb · pickup 18:00"
    let equipment: BackhaulEquipment_398
    let netRPM: String        // "$3.05"
    let matchScore: Int       // 94
    // featured-card extras (best match only)
    let deadheadMi: Int?      // 38
    let gross: String?        // "gross $2,640"
    let tail: String?         // "2.1h home · Eusorone shipper"
}

private struct BackhaulVM_398 {
    let emptyAt: String           // "EMPTY AT DALLAS TX · 16:30 CDT"
    let deadheadLabel: String     // "Deadhead home to Belle Plaine"
    let deadheadValue: String     // "612 mi · $0"
    let loadedLabel: String       // "Best backhaul · 38 mi reposition"
    let loadedValue: String       // "574 loaded mi"
    let payoff: String            // "+$2,640"
    let withinRadius: String      // "14 within 75 mi"
    let matches: [BackhaulMatch_398]
    let footerLead: String
    let footerSub: String         // contains the +$0.34/mi clear
    let searchNote: String        // "Search radius 75 mi · home by Fri · HOS 8:30 drive left"
}

// Representative seed (0% mock — overwritten on hydrate). Mirrors the
// 398 Dark SVG content verbatim.
private let seedBackhaul_398 = BackhaulVM_398(
    emptyAt: "EMPTY AT DALLAS TX · 16:30 CDT",
    deadheadLabel: "Deadhead home to Belle Plaine", deadheadValue: "612 mi · $0",
    loadedLabel: "Best backhaul · 38 mi reposition", loadedValue: "574 loaded mi",
    payoff: "+$2,640", withinRadius: "14 within 75 mi",
    matches: [
        BackhaulMatch_398(id: "ld-dal-kc", lane: "Dallas TX → Kansas City MO",
                          spec: "53' Dry Van · 38k lb · pickup 18:00", equipment: .dryVan,
                          netRPM: "$3.05", matchScore: 94, deadheadMi: 38, gross: "gross $2,640",
                          tail: "2.1h home · Eusorone shipper"),
        BackhaulMatch_398(id: "ld-ftw-oma", lane: "Fort Worth TX → Omaha NE",
                          spec: "Reefer 34°F · DH 41 mi · pickup 20:30", equipment: .reefer,
                          netRPM: "$2.88", matchScore: 89, deadheadMi: nil, gross: nil, tail: nil),
        BackhaulMatch_398(id: "ld-dal-tul", lane: "Dallas TX → Tulsa OK",
                          spec: "Flatbed · DH 12 mi · short reposition lane", equipment: .flatbed,
                          netRPM: "$2.71", matchScore: 82, deadheadMi: nil, gross: nil, tail: nil),
        BackhaulMatch_398(id: "ld-dal-ict", lane: "Dallas TX → Wichita KS",
                          spec: "Dry Van · DH 9 mi · partial load", equipment: .dryVan,
                          netRPM: "$2.44", matchScore: 76, deadheadMi: nil, gross: nil, tail: nil),
    ],
    footerLead: "ESang ranks net RPM after deadhead, HOS fit & home-time",
    footerSub: "Top return clears $0.34/mi over deadhead-home break-even",
    searchNote: "Search radius 75 mi · home by Fri · HOS 8:30 drive left"
)

// MARK: - Notifications (carry the tap intent into the host action layer)

extension Notification.Name {
    static let eusoCatalystBackhaulTender_398     = Notification.Name("eusoCatalystBackhaulTender")
    static let eusoCatalystBackhaulTenderBest_398 = Notification.Name("eusoCatalystBackhaulTenderBest")
    static let eusoCatalystBackhaulRadius_398     = Notification.Name("eusoCatalystBackhaulRadius")
}

// MARK: - Body

private struct BackhaulBody_398: View {
    @Environment(\.palette) private var palette

    @State private var vm: BackhaulVM_398 = seedBackhaul_398

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            iridescentHairline
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    heroCard
                    matchesSection
                    ctaRow
                    Text(vm.searchNote)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s3)
                .padding(.bottom, Space.s7)
            }
        }
        .task { await loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await reload() }
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("CATALYST · BACKHAUL · EMPTY-MILE KILLER")
                        .font(EType.micro)
                        .tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer(minLength: 0)
                Text("EMPTY IN 2h")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 28)
                Text("Backhaul")
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                VStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(palette.textPrimary).frame(width: 4, height: 4)
                    }
                }
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, 56)
        .padding(.bottom, Space.s3)
    }

    private var iridescentHairline: some View {
        IridescentHairline()
    }

    // MARK: Hero — deadhead vs best backhaul comparison

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)
            VStack(alignment: .leading, spacing: 10) {
                Text(vm.emptyAt)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                compareRow(
                    label: vm.deadheadLabel, value: vm.deadheadValue,
                    barFrac: 1.0, barColor: Brand.danger.opacity(0.6),
                    track: Brand.danger.opacity(0.18), valueColor: Brand.danger
                )
                compareRow(
                    label: vm.loadedLabel, value: vm.loadedValue,
                    barFrac: 0.93, barColor: nil,
                    track: Brand.success.opacity(0.18), valueColor: Brand.success
                )
                HStack {
                    Text("Turns the empty run into")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Text(vm.payoff)
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 128)
    }

    private func compareRow(label: String, value: String, barFrac: CGFloat,
                            barColor: Color?, track: Color, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(valueColor)
            }
            GeometryReader { geo in
                let w = geo.size.width * 0.66   // bar occupies the left ~2/3
                ZStack(alignment: .leading) {
                    Capsule().fill(track).frame(width: w, height: 8)
                    barFill(barColor: barColor).frame(width: w * barFrac, height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    @ViewBuilder
    private func barFill(barColor: Color?) -> some View {
        if let bc = barColor {
            Capsule().fill(bc)
        } else {
            Capsule().fill(LinearGradient.primary)
        }
    }

    // MARK: Ranked return matches

    private var matchesSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("RETURN LOADS · RANKED BY NET RPM")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(vm.withinRadius)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                if let best = vm.matches.first { featuredMatch(best) }
                ForEach(Array(vm.matches.dropFirst().enumerated()), id: \.element.id) { idx, m in
                    compactMatch(m)
                    if idx < vm.matches.count - 2 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 48)
                    }
                }
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.footerLead)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(vm.footerSub)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func featuredMatch(_ m: BackhaulMatch_398) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.md - 1.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: Space.s3) {
                    equipmentChip(m.equipment)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.lane)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text(m.spec)
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(m.netRPM)
                            .font(.system(size: 20, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("net /mi · after DH")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                HStack(spacing: 6) {
                    metricChip("DH \(m.deadheadMi ?? 0) mi", tint: Brand.success.opacity(0.12), label: Brand.success)
                    metricChip(m.gross ?? "", tint: palette.bgCardSoft, label: palette.textPrimary)
                    metricChip("\(m.matchScore) MATCH", tint: nil, label: .white)
                }
                HStack {
                    Button {
                        // WIRE: loadBidding.createQuote (loadBidding.ts) — on win
                        // writes the loads row + blockchainAudit, broadcasts
                        // WS_EVENTS.LOAD_TENDERED on WS_CHANNELS.catalyst(carrierId).
                        NotificationCenter.default.post(
                            name: .eusoCatalystBackhaulTender_398, object: nil,
                            userInfo: ["source": "398_CatalystBackhaulOptimizer", "loadId": m.id]
                        )
                    } label: {
                        Text("TENDER NOW →")
                            .font(EType.micro).tracking(0.4).fontWeight(.heavy)
                            .foregroundStyle(LinearGradient.primary)
                            .padding(.horizontal, 14).padding(.vertical, 4)
                            .background(Capsule().strokeBorder(LinearGradient.primary, lineWidth: 1.1))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    if let tail = m.tail {
                        Text(tail)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .padding(Space.s3)
        }
        .padding(Space.s2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Best return, \(m.lane), net \(m.netRPM) per mile after deadhead, match \(m.matchScore)")
    }

    private func metricChip(_ text: String, tint: Color?, label: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.3).monospacedDigit()
            .foregroundStyle(label)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(tint ?? Color.clear))
            .background(tint == nil ? AnyView(Capsule().fill(LinearGradient.primary)) : AnyView(EmptyView()))
    }

    private func compactMatch(_ m: BackhaulMatch_398) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            equipmentChip(m.equipment)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.lane)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(m.spec)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(m.netRPM)
                    .font(EType.bodyStrong).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("\(m.matchScore) match")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
    }

    @ViewBuilder
    private func equipmentChip(_ eq: BackhaulEquipment_398) -> some View {
        let icon = equipmentIcon(eq)
        let tint = equipmentTint(eq)
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm).fill(tint.opacity(0.16))
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 36, height: 36)
    }

    private func equipmentIcon(_ eq: BackhaulEquipment_398) -> String {
        switch eq {
        case .dryVan:  return "box.truck"
        case .reefer:  return "thermometer.snowflake"
        case .flatbed: return "rectangle.compress.vertical"
        }
    }

    private func equipmentTint(_ eq: BackhaulEquipment_398) -> Color {
        switch eq {
        case .dryVan:  return Brand.rail            // SVG #607D8B slate
        case .reefer:  return Brand.info            // SVG #2196F3
        case .flatbed: return palette.textPrimary
        }
    }

    // MARK: CTA pair

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                // WIRE: loadBidding.createQuote on the best return (loadBidding.ts)
                NotificationCenter.default.post(
                    name: .eusoCatalystBackhaulTenderBest_398, object: nil,
                    userInfo: ["source": "398_CatalystBackhaulOptimizer"]
                )
            } label: {
                Text("Tender best return")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tender the best return load")

            Button {
                NotificationCenter.default.post(
                    name: .eusoCatalystBackhaulRadius_398, object: nil,
                    userInfo: ["source": "398_CatalystBackhaulOptimizer"]
                )
            } label: {
                Text("Adjust radius")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Adjust search radius")
        }
    }

    // MARK: - Network

    private func loadAll() async {
        await reload()
    }

    private func reload() async {
        // Hydration target — replace the seed once the iOS client exposes
        // the carrier-scope capacity-planning surface:
        //
        //   WIRE: capacityPlanning.getBackhaulOptimizer  (capacityPlanning.ts:690) — ranked matches
        //   WIRE: capacityPlanning.getPowerOnlyMatching  (capacityPlanning.ts:755) — power-only / drop-trailer
        //   WIRE: loadBoard.search                       (loadBoard.ts)            — candidate loads near dropoff
        //   WIRE: routeOptimization.*                    (routeOptimization.ts)    — deadhead mileage
        //
        // No matching EusoTripAPI.shared service exists yet (verified: there
        // is no `capacityPlanning` client and loadBidding has no createQuote),
        // so the SVG-verbatim seed stands. When the envelope lands:
        //   self.vm = BackhaulVM_398(emptyAt: env.emptyAt, ...,
        //                            matches: env.matches.map { ... })
        vm = seedBackhaul_398
    }
}

// MARK: - Previews

#Preview("398 · Catalyst · Backhaul Optimizer · Night") {
    CatalystBackhaulOptimizerScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("398 · Catalyst · Backhaul Optimizer · Afternoon") {
    CatalystBackhaulOptimizerScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
