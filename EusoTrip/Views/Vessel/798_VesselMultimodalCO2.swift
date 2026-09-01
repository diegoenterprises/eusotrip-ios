//
//  798_VesselMultimodalCO2.swift
//  EusoTrip — Vessel Operator · Multimodal CO₂ (MONEY-DETAIL archetype).
//
//  Faithful port of "798 Vessel Multimodal CO2.svg" (Dark + Light). A door-to-door
//  emissions breakdown for the intermodal lane: a gradient total-CO₂e headline, a
//  three-segment split bar (vessel / rail / drayage) with per-mode stats, and a
//  per-leg emissions ledger — so the operator can quote a carbon-cleared lane, see
//  the exact offset $ to neutralize it, and prove the rail leg's saving vs all-road.
//
//  Nav: Shell + BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME), COMPLIANCE inked.
//
//  REAL WIRING (tRPC · server/routers/co2Calculator.ts + sustainability.ts):
//    · co2Calculator.calculateMultiModal  { legs:[{mode, distanceNm?/distanceMiles?,
//        weightTons?, fuelType?}] } -> { legs:[{leg, mode, co2Kg}], totalCo2Kg,
//        totalCo2Tonnes, carbonOffsetCostUsd }  (:192) — the emissions per leg + total
//        + offset ($25/tCO₂e) are ALL server-computed off GLEC factors; only the lane
//        (leg distances/weights) is the modeled input. An all-road baseline is a second
//        real calculateMultiModal call so the "vs all-truck" saving is computed, not
//        fabricated.
//    · "Buy carbon offsets" -> sustainability.buyOffsets { tonnesCO2e } -> { success,
//        handle, tonnesCO2e, totalUSD }  (:193 · mutation · records the offset intent +
//        emits an audit handle). "Recalc" re-runs calculateMultiModal.
//
//  RBAC: calculateMultiModal / buyOffsets protectedProcedure. transportMode=vessel ·
//  country US (USD · GLEC v3.0). NO mock data — every tonne, share and $ is server math;
//  the lane is the modeled door-to-door route.
//

import SwiftUI

struct VesselMultimodalCO2Screen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VesselMultimodalCO2Body()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Lane model + wire shapes

/// A modeled door-to-door leg. Distances/weights are the lane input; emissions come
/// back from the server. Matched-set lane VES-260602 (CNSHA → USLGB → Chicago → DC).
private struct LegSpec798 {
    let n: Int
    let title: String
    let lane: String
    let distanceLabel: String
    let mode: String        // "vessel" | "rail" | "truck"
    let pillText: String
    let accent: Color
}

private struct MultiModalResult798: Decodable {
    let legs: [MultiModalLeg798]
    let totalCo2Kg: Double?
    let totalCo2Tonnes: Double?
    let carbonOffsetCostUsd: Double?
}

private struct MultiModalLeg798: Decodable {
    let leg: Int
    let mode: String
    let co2Kg: Double
}

private struct BuyOffsetsResult798: Decodable {
    let success: Bool?
    let handle: String?
    let tonnesCO2e: Double?
    let totalUSD: Double?
}

// MARK: - Body

private struct VesselMultimodalCO2Body: View {
    @Environment(\.palette) private var palette
    @Environment(\.vesselOperatorNavHandler) private var navHandler

    @State private var result: MultiModalResult798? = nil
    @State private var allRoadTonnes: Double? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var buying = false
    @State private var buyAck: String? = nil
    @State private var buyError: String? = nil

    /// The modeled lane — three legs. Weights default to a 20t container load.
    private let lane: [LegSpec798] = [
        LegSpec798(n: 1, title: "Leg 1 · Ocean", lane: "CNSHA → USLGB",
                   distanceLabel: "5,720 nm", mode: "vessel", pillText: "VESSEL", accent: Color(hex: 0x5AA6FF)),
        LegSpec798(n: 2, title: "Leg 2 · Rail", lane: "LBCT ICTF → Chicago",
                   distanceLabel: "2,010 mi", mode: "rail", pillText: "RAIL", accent: Color(hex: 0xC77DD8)),
        LegSpec798(n: 3, title: "Leg 3 · Drayage", lane: "Chicago LP → Eusorone DC",
                   distanceLabel: "38 mi", mode: "truck", pillText: "TRUCK", accent: Color(hex: 0x9AA4AE)),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                IridescentHairline().padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        errorCard(err)
                    } else {
                        splitCard
                        legLedger
                        if let ack = buyAck { banner(ack, danger: false) }
                        if let err = buyError { banner(err, danger: true) }
                        ctaRow
                        esangCard
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.top, Space.s5)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header (eyebrow + breadcrumb + total tCO₂e hero)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("VESSEL OPERATOR · MULTIMODAL CO2")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("GLEC v3.0").font(EType.mono(.micro)).tracking(0.8).foregroundStyle(palette.textTertiary)
            }
            Button { navHandler?("Compliance") } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    Text("Compliance").font(.system(size: 13, weight: .semibold))
                }.foregroundStyle(palette.textSecondary)
            }.buttonStyle(.plain).padding(.top, Space.s2)

            Text(tonnesText(totalTonnes))
                .font(.system(size: 34, weight: .bold, design: .monospaced)).tracking(-0.6)
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.top, Space.s3)
            Text("door-to-door · \(lane.count) legs · GLEC v3.0 factors · offset \(money(offsetCost)) @ $25/t")
                .font(EType.caption).foregroundStyle(palette.textSecondary).padding(.top, 2)
        }
    }

    // MARK: Emissions split card (gradient-rim · 3-segment bar + per-mode stats)

    private var splitCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("EMISSIONS SPLIT · BY LEG")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(tonnesText(totalTonnes))
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
            }
            // Proportioned 3-segment bar.
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(legRows.enumerated()), id: \.offset) { _, row in
                        RoundedRectangle(cornerRadius: 6).fill(row.spec.accent)
                            .frame(width: max(4, geo.size.width * CGFloat(row.share)))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 12)
            // Per-mode stats.
            HStack(alignment: .top, spacing: Space.s5) {
                ForEach(Array(legRows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.spec.pillText).font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textSecondary)
                        Text(tonnesText(row.tonnes)).font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
    }

    // MARK: Per-leg ledger + total

    private var legLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("EMISSIONS BY LEG").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(legRows.enumerated()), id: \.offset) { _, row in
                    legRow(row)
                    Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                }
                totalRow
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }

    private func legRow(_ row: LegRow798) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(row.spec.accent.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "leaf.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(row.spec.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.spec.title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("\(row.spec.lane) · \(row.spec.distanceLabel)")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Text(row.spec.pillText).font(.system(size: 9, weight: .heavy)).tracking(0.3)
                .foregroundStyle(row.spec.accent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(row.spec.accent.opacity(0.16)))
            Text(tonnesText(row.tonnes)).font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.textPrimary).frame(width: 56, alignment: .trailing)
        }
        .padding(Space.s4)
    }

    private var totalRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.success.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "leaf.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.success)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Door-to-door").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("\(lane.count) legs · \(kgText(totalKg)) CO₂e · offset \(money(offsetCost))")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Text("TOTAL").font(.system(size: 9, weight: .heavy)).tracking(0.3).foregroundStyle(Brand.success)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Brand.success.opacity(0.16)))
            Text(tonnesText(totalTonnes)).font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.textPrimary).frame(width: 56, alignment: .trailing)
        }
        .padding(Space.s4)
    }

    // MARK: CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await buyOffsets() } } label: {
                HStack(spacing: 6) {
                    if buying { ProgressView().tint(.white).scaleEffect(0.8) }
                    Text(buying ? "Booking…" : "Buy carbon offsets")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary).clipShape(Capsule())
            }
            .buttonStyle(.plain).disabled(buying || totalTonnes <= 0).opacity(totalTonnes <= 0 ? 0.6 : 1.0)

            Button { Task { await load() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold))
                    Text("Recalc").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(palette.textPrimary)
                .frame(minWidth: 116, minHeight: 48).padding(.horizontal, Space.s3)
                .background(palette.bgCard).overlay(Capsule().strokeBorder(palette.borderFaint)).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    // MARK: ESang card (real saving vs all-road)

    private var esangCard: some View {
        HStack(spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(esangHeadline).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.85)
                Text("door-to-door \(tonnesText(totalTonnes)) · \(money(offsetCost)) offset clears GLEC v3.0")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Loading / error / banners

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 118)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 240)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    private func errorCard(_ err: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func banner(_ msg: String, danger: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: danger ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(danger ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(LinearGradient.diagonal))
            Text(msg).font(EType.caption).foregroundStyle(danger ? Brand.danger : palette.textPrimary)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background((danger ? Brand.danger : Brand.success).opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder((danger ? Brand.danger : Brand.success).opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Derived

    private struct LegRow798 { let spec: LegSpec798; let kg: Double; let tonnes: Double; let share: Double }

    private var legRows: [LegRow798] {
        guard let legs = result?.legs else {
            return lane.map { LegRow798(spec: $0, kg: 0, tonnes: 0, share: 0) }
        }
        let total = max(totalKg, 0.001)
        return lane.map { spec in
            let kg = legs.first(where: { $0.leg == spec.n })?.co2Kg ?? 0
            return LegRow798(spec: spec, kg: kg, tonnes: kg / 1000, share: kg / total)
        }
    }

    private var totalKg: Double { result?.totalCo2Kg ?? 0 }
    private var totalTonnes: Double { result?.totalCo2Tonnes ?? (totalKg / 1000) }
    private var offsetCost: Double { result?.carbonOffsetCostUsd ?? 0 }

    private var esangHeadline: String {
        guard let baseline = allRoadTonnes, baseline > 0, totalTonnes > 0, baseline > totalTonnes else {
            return "ESang: multimodal routing keeps this lane carbon-light"
        }
        let saving = Int(((baseline - totalTonnes) / baseline * 100).rounded())
        return "ESang: the rail + ocean legs cut \(saving)% vs all-truck"
    }

    private func tonnesText(_ t: Double) -> String {
        if t >= 10 { return "\(String(format: "%.1f", t)) t" }
        return "\(String(format: "%.1f", t))t"
    }
    private func kgText(_ kg: Double) -> String { "\(Int(kg).formatted(.number.grouping(.automatic))) kg" }
    private func money(_ v: Double) -> String {
        if v == v.rounded() { return "$\(Int(v).formatted(.number.grouping(.automatic)))" }
        return "$\(String(format: "%.0f", v))"
    }

    // MARK: - Wire helpers

    private struct LegIn798: Encodable {
        let mode: String
        let distanceNm: Double?
        let distanceMiles: Double?
        let weightTons: Double
        let fuelType: String?
    }
    private struct MultiModalIn798: Encodable { let legs: [LegIn798] }

    /// The modeled lane translated to the server leg schema.
    private var actualLegs: [LegIn798] {
        [
            LegIn798(mode: "vessel", distanceNm: 5720, distanceMiles: nil, weightTons: 20, fuelType: "vlsfo"),
            LegIn798(mode: "rail", distanceNm: nil, distanceMiles: 2010, weightTons: 20, fuelType: nil),
            LegIn798(mode: "truck", distanceNm: nil, distanceMiles: 38, weightTons: 20, fuelType: nil),
        ]
    }
    /// The same lane distances, but every leg as truck — the all-road baseline.
    /// Ocean nm converted to statute miles (1 nm = 1.15078 mi).
    private var allRoadLegs: [LegIn798] {
        [
            LegIn798(mode: "truck", distanceNm: nil, distanceMiles: 5720 * 1.15078, weightTons: 20, fuelType: nil),
            LegIn798(mode: "truck", distanceNm: nil, distanceMiles: 2010, weightTons: 20, fuelType: nil),
            LegIn798(mode: "truck", distanceNm: nil, distanceMiles: 38, weightTons: 20, fuelType: nil),
        ]
    }

    // MARK: - Actions

    private func load() async {
        loading = true; loadError = nil
        do {
            async let actual: MultiModalResult798 = EusoTripAPI.shared.query(
                "co2Calculator.calculateMultiModal", input: MultiModalIn798(legs: actualLegs))
            async let baseline: MultiModalResult798 = EusoTripAPI.shared.query(
                "co2Calculator.calculateMultiModal", input: MultiModalIn798(legs: allRoadLegs))
            let (a, b) = try await (actual, baseline)
            self.result = a
            self.allRoadTonnes = b.totalCo2Tonnes ?? (b.totalCo2Kg.map { $0 / 1000 })
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func buyOffsets() async {
        guard totalTonnes > 0 else { return }
        buying = true; buyAck = nil; buyError = nil
        struct BuyIn: Encodable { let tonnesCO2e: Double }
        do {
            let res: BuyOffsetsResult798 = try await EusoTripAPI.shared.mutation(
                "sustainability.buyOffsets", input: BuyIn(tonnesCO2e: totalTonnes))
            if res.success == true {
                let usd = res.totalUSD.map { money($0) } ?? money(offsetCost)
                buyAck = "Offsets booked · \(tonnesText(res.tonnesCO2e ?? totalTonnes)) · \(usd)\(res.handle.map { " · \($0)" } ?? "")."
            } else {
                buyError = "Offset purchase did not confirm. Try again."
            }
        } catch {
            buyError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        buying = false
    }
}

#Preview("798 · Vessel Multimodal CO2 · Night") {
    VesselMultimodalCO2Screen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("798 · Vessel Multimodal CO2 · Light") {
    VesselMultimodalCO2Screen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
