//
//  403_CatalystFleetCarbon.swift
//  EusoTrip — Catalyst · Fleet Carbon (carrier network-intelligence band).
//
//  Verbatim iOS port of:
//    03 Catalyst/Code/403_CatalystFleetCarbon.swift
//    03 Catalyst/Dark-SVG/403 Catalyst Fleet Carbon.svg
//
//  A CHART archetype — NOT the home/detail skeleton: a CO₂e YTD hero with
//  the fleet intensity vs the SmartWay benchmark (dashed marker), a compact
//  intensity / MPG / offset-cost strip, and a per-lane intensity bar chart
//  with an avg reference line so the dirtiest corridor is obvious at a
//  glance. The carrier re-specs or reroutes and quotes shippers a verified
//  carbon number on the next RFP, or retires offsets to net-zero in one tap.
//
//  Persona: Eusotrans LLC · Michael Eusorone owner-op · 6 trucks;
//  lane shipper-of-record Diego Usoro / Eusorone. transportMode=truck;
//  country=US (EPA SmartWay factors).
//
//  Wiring manifest (line-confirmed in the Code/ spec):
//    • hero CO₂e + intensity → sustainability.getFleetCarbon (sustainability.ts:89)
//    • per-shipment factors   → co2Calculator.calculateTruckShipment (co2Calculator.ts:31)
//    • offset quote           → sustainability.getOffsetQuote (sustainability.ts:165)
//    • reduction tips         → sustainability.getRecommendations (sustainability.ts:220)
//    • "Buy offsets" CTA      → sustainability.buyOffsets (sustainability.ts:193)
//    • "Export report" CTA    → sustainability.exportCarbonReport (sustainability.ts:277)
//
//  The `sustainability` tRPC surface is not yet mirrored in the Swift client
//  (EusoTripAPI exposes only `co2Calculator.*` via the `co2` accessor), so
//  this surface carries the representative seed figures from the Code/ spec
//  (house 0%-mock convention: seeds are overwritten the moment a real
//  hydrate lands) and leaves one WIRE marker per missing procedure below.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Shell wrapper + Catalyst BottomNav (HOME · DISPATCH · [orb] · WALLET · ME)

struct CatalystFleetCarbonScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            FleetCarbonBody_403()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_403(),
                trailing: catalystNavTrailing_403(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_403() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "tray.full",  isCurrent: false)]
}

private func catalystNavTrailing_403() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: true),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
}

// MARK: - Lane emission model (nested at file scope, _403-suffixed)

private struct LaneEmission_403: Identifiable {
    enum Flag { case good, neutral, hot }
    let id: String          // lane id
    let lane: String        // "I-10 · Houston → Dallas"
    let intensity: Int      // 72 (g CO2e / ton-mi)
    let flag: Flag
}

// MARK: - View model (the hydrated envelope; seeds mirror the SVG verbatim)

private struct FleetCarbonVM_403 {
    let co2eYTD: String         // "284 t"
    let intensityInline: String // "78 g/ton-mi"
    let vsSmartWay: String      // "−12%"
    let offsetToNetZero: String // "$3,120"
    let benchmarkFrac: Double   // SmartWay benchmark marker position on the hero band
    let fleetFrac: Double       // fleet intensity fill on the hero band
    let bandCaption: String
    let intensity: String       // "78g"
    let intensityYoY: String    // "−6% YoY"
    let fleetMPG: String        // "7.4"
    let mpgDelta: String        // "+0.3 vs 25"
    let offsetCost: String      // "$11/t"
    let lanes: [LaneEmission_403]
    let laneAvg: Int            // 78
    let laneMax: Int            // 100 (scale denominator)
    let insightTitle: String
    let insightSub: String

    /// Code/ spec representative seed — mirrors the 403 SVG content verbatim.
    /// Overwritten on the first successful hydrate (house 0%-mock convention).
    static let seed = FleetCarbonVM_403(
        co2eYTD: "284 t", intensityInline: "78 g/ton-mi",
        vsSmartWay: "−12%", offsetToNetZero: "$3,120",
        benchmarkFrac: 0.80, fleetFrac: 0.70,
        bandCaption: "Below the SmartWay 89 g benchmark (dashed) · verified Q1",
        intensity: "78g", intensityYoY: "−6% YoY", fleetMPG: "7.4", mpgDelta: "+0.3 vs 25",
        offsetCost: "$11/t",
        lanes: [
            LaneEmission_403(id: "i10", lane: "I-10 · Houston → Dallas",     intensity: 72, flag: .good),
            LaneEmission_403(id: "i35", lane: "I-35 · DFW → Kansas City",    intensity: 81, flag: .neutral),
            LaneEmission_403(id: "i80", lane: "I-80 · Ohio → PA · reefer",   intensity: 88, flag: .hot),
            LaneEmission_403(id: "i94", lane: "I-94 · Chicago → Detroit",    intensity: 76, flag: .neutral),
            LaneEmission_403(id: "i70", lane: "I-70 · St. Louis → Columbus", intensity: 70, flag: .good),
        ],
        laneAvg: 78, laneMax: 100,
        insightTitle: "ESang: I-80 reefer runs 13% hot",
        insightSub: "Cycle-sentry mode cuts ~9 t/yr · holds your −12% edge"
    )

    /// Honest empty envelope — every figure paints an em-dash until a real
    /// `sustainability.getFleetCarbon` hydrate lands.
    static let empty = FleetCarbonVM_403(
        co2eYTD: "—", intensityInline: "—",
        vsSmartWay: "—", offsetToNetZero: "—",
        benchmarkFrac: 0.0, fleetFrac: 0.0,
        bandCaption: "—",
        intensity: "—", intensityYoY: "—", fleetMPG: "—", mpgDelta: "—",
        offsetCost: "—",
        lanes: [],
        laneAvg: 0, laneMax: 100,
        insightTitle: "—",
        insightSub: "—"
    )
}

// MARK: - Body

private struct FleetCarbonBody_403: View {
    @Environment(\.palette) private var palette

    // House 0%-mock: start on the Code/ representative seed; loadAll()
    // overwrites it the moment the sustainability surface is mirrored.
    @State private var vm: FleetCarbonVM_403 = .seed
    @State private var loading: Bool = false
    @State private var loadError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
                .padding(.horizontal, -Space.s5)
            VStack(alignment: .leading, spacing: Space.s4) {
                if let err = loadError {
                    errorBanner(err)
                }
                heroCard
                kpiStrip
                laneChart
                insightRow
                ctaPair
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s7)
        }
        .task { await loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll() }
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
                    Text("CATALYST · EMISSIONS")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("SMARTWAY · CO₂e")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fleet Carbon")
                        .font(EType.display)
                        .foregroundStyle(palette.textPrimary)
                    Text("Eusotrans LLC · 6 trucks · YTD 2026")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(.top, Space.s2)
        }
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: Hero · fleet CO₂e

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FLEET CO₂e · YTD 2026")
                            .font(EType.micro).tracking(1.0)
                            .foregroundStyle(palette.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(vm.co2eYTD)
                                .font(.system(size: 38, weight: .bold).monospacedDigit())
                                .foregroundStyle(LinearGradient.diagonal)
                            Text(vm.intensityInline)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("vs SMARTWAY")
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(Brand.success)
                        Text(vm.vsSmartWay)
                            .font(.system(size: 16, weight: .bold).monospacedDigit())
                            .foregroundStyle(Brand.success)
                        Text("OFFSET TO NET-ZERO")
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, 2)
                        Text(vm.offsetToNetZero)
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                intensityBand
                    .padding(.top, Space.s3)
                Text(vm.bandCaption)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, Space.s2)
            }
            .padding(Space.s4)
        }
        .frame(height: 132)
    }

    private var intensityBand: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.success.opacity(0.16))
                Capsule()
                    .fill(LinearGradient(colors: [Brand.success, Brand.blue],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * vm.fleetFrac)
                Rectangle()
                    .fill(palette.textTertiary)
                    .frame(width: 1.5, height: 16)
                    .offset(x: w * vm.benchmarkFrac)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Fleet intensity \(vm.intensity), \(vm.vsSmartWay) vs SmartWay benchmark")
    }

    // MARK: KPI strip · 3 tiles

    private var kpiStrip: some View {
        HStack(spacing: Space.s3) {
            kpiTile("INTENSITY", vm.intensity, sub: vm.intensityYoY,
                    valueStyle: AnyShapeStyle(LinearGradient.diagonal), subColor: Brand.success)
            kpiTile("FLEET MPG", vm.fleetMPG, sub: vm.mpgDelta,
                    valueStyle: AnyShapeStyle(palette.textPrimary), subColor: Brand.success)
            kpiTile("OFFSET COST", vm.offsetCost, sub: "verified registry",
                    valueStyle: AnyShapeStyle(palette.textPrimary), subColor: palette.textSecondary)
        }
    }

    private func kpiTile(_ label: String, _ value: String, sub: String,
                         valueStyle: AnyShapeStyle, subColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 26, weight: .semibold).monospacedDigit())
                .foregroundStyle(valueStyle)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(EType.caption)
                .foregroundStyle(subColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: Per-lane intensity chart

    private var laneChart: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("LANE EMISSIONS · g CO₂e / TON-MI")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("vs \(vm.laneAvg) avg")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: Space.s4) {
                if vm.lanes.isEmpty {
                    Text("—")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                } else {
                    ForEach(vm.lanes) { lane in
                        laneRow(lane)
                    }
                }
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func laneFlagColor(_ f: LaneEmission_403.Flag) -> Color {
        switch f {
        case .good:    return Brand.success
        case .neutral: return palette.textPrimary
        case .hot:     return Brand.warning
        }
    }

    private func laneRow(_ lane: LaneEmission_403) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(lane.lane)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(lane.intensity) g")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(laneFlagColor(lane.flag))
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.textTertiary.opacity(0.12))
                        .frame(height: 6)
                    Capsule()
                        .fill(LinearGradient(colors: [Brand.success, Brand.blue],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * CGFloat(lane.intensity) / CGFloat(vm.laneMax), height: 6)
                    Rectangle()
                        .fill(palette.textTertiary.opacity(0.5))
                        .frame(width: 1, height: 12)
                        .offset(x: w * CGFloat(vm.laneAvg) / CGFloat(vm.laneMax))
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lane.lane), \(lane.intensity) grams per ton-mile")
    }

    // MARK: ESang insight row

    private var insightRow: some View {
        Button {
            NotificationCenter.default.post(name: .eusoCatalystCarbonInsight_403, object: nil,
                userInfo: ["source": "403_CatalystFleetCarbon"])
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
                    Text(vm.insightTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(vm.insightSub)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                // WIRE: sustainability.buyOffsets (sustainability.ts:193) — payment
                // write gated catalystProcedure (_core/trpc.ts:150); records the
                // retirement certificate, inserts a blockchainAudit row and
                // broadcasts a wallet update. Not yet mirrored in EusoTripAPI.
                NotificationCenter.default.post(name: .eusoCatalystCarbonBuyOffsets_403, object: nil,
                    userInfo: ["source": "403_CatalystFleetCarbon", "amount": vm.offsetToNetZero])
            } label: {
                Text("Buy offsets · \(vm.offsetToNetZero)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            Button {
                // WIRE: sustainability.exportCarbonReport (sustainability.ts:277) —
                // shipper-facing CDP/SmartWay packet. Not yet mirrored in EusoTripAPI.
                NotificationCenter.default.post(name: .eusoCatalystCarbonExport_403, object: nil,
                    userInfo: ["source": "403_CatalystFleetCarbon"])
            } label: {
                Text("Export report")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 144, height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Error banner

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Brand.danger)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            Button { Task { await loadAll() } } label: {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.danger.opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Network

    private func loadAll() async {
        loading = true
        loadError = nil
        loading = false

        // WIRE: sustainability.getFleetCarbon (sustainability.ts:89) — hero CO₂e,
        //       fleet intensity, SmartWay delta, offset-to-net-zero, MPG, per-lane
        //       intensities. Not yet mirrored in the Swift client.
        // WIRE: sustainability.getOffsetQuote (sustainability.ts:165) — offset cost.
        // WIRE: sustainability.getRecommendations (sustainability.ts:220) — ESang tip.
        //
        // The only carbon procedure mirrored in EusoTripAPI today is
        // `co2Calculator.calculateTruckShipment` (per-shipment, not the fleet
        // aggregate this surface renders). Until the `sustainability` router is
        // mirrored, the Code/ representative seed stands per house 0%-mock.
        //
        // No real aggregate call exists yet, so leave the seed in place and
        // surface no false error.
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let eusoCatalystCarbonBuyOffsets_403 = Notification.Name("eusoCatalystCarbonBuyOffsets_403")
    static let eusoCatalystCarbonExport_403     = Notification.Name("eusoCatalystCarbonExport_403")
    static let eusoCatalystCarbonInsight_403    = Notification.Name("eusoCatalystCarbonInsight_403")
}

// MARK: - Previews

#Preview("403 · Catalyst · Fleet Carbon · Night") {
    CatalystFleetCarbonScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("403 · Catalyst · Fleet Carbon · Afternoon") {
    CatalystFleetCarbonScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
