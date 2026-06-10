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
//  LIVE WIRING (zero-fallback purge · 2026-06-09 · audit B13): loadAll()
//  hydrates from the REAL sustainability.getFleetCarbon (totalTonnes /
//  loadCount / savedTonnes / netZeroProgressPct, all computed from actual
//  load rows) and prices the offset CTA with a REAL getOffsetQuote. Fields
//  the live rollup does not carry (g/ton-mi intensity, SmartWay delta,
//  fleet MPG, per-lane intensities) render an honest em-dash / empty state
//  — the old "284 t / −12% / $3,120" seed is GONE.
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
    let offsetToNetZero: String // live offset quote total, or em-dash
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

    /// Honest empty envelope — every figure paints an em-dash until a real
    /// `sustainability.getFleetCarbon` hydrate lands. (The old SVG seed with
    /// "284 t / −12% / $3,120" was fabricated and is GONE — audit B13.)
    static let empty = FleetCarbonVM_403(
        co2eYTD: "—", intensityInline: "—",
        vsSmartWay: "—", offsetToNetZero: "—",
        benchmarkFrac: 0.0, fleetFrac: 0.0,
        bandCaption: "—",
        intensity: "—", intensityYoY: "—", fleetMPG: "—", mpgDelta: "—",
        offsetCost: "—",
        lanes: [],
        laneAvg: 0, laneMax: 100,
        insightTitle: "No emissions insight yet",
        insightSub: "Live load data populates this surface."
    )
}

// MARK: - Body

private struct FleetCarbonBody_403: View {
    @Environment(\.palette) private var palette

    // Live VM — honest em-dash envelope until sustainability.getFleetCarbon answers.
    @State private var vm: FleetCarbonVM_403 = .empty
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var offsetQuoteTotal: Double? = nil

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
                    Text("EPA SmartWay factors · YTD \(Calendar.current.component(.year, from: Date()))")
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
                        Text("FLEET CO₂e · YTD \(Calendar.current.component(.year, from: Date()))")
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
                Text(vm.lanes.isEmpty ? "—" : "vs \(vm.laneAvg) avg")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: Space.s4) {
                if vm.lanes.isEmpty {
                    EusoEmptyState(
                        systemImage: "leaf",
                        title: loading ? "Loading emissions…" : "Per-lane intensity not yet available",
                        subtitle: loading ? "" : "Lane-level CO₂e intensity isn't exposed by the live emissions rollup yet."
                    )
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
                // Hands the REAL live quote to the host action layer
                // (sustainability.buyOffsets not yet bridged for the write).
                guard let total = offsetQuoteTotal else { return }
                NotificationCenter.default.post(name: .eusoCatalystCarbonBuyOffsets_403, object: nil,
                    userInfo: ["source": "403_CatalystFleetCarbon", "amount": total])
            } label: {
                Text(offsetQuoteTotal != nil ? "Buy offsets · \(vm.offsetToNetZero)" : "Buy offsets")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(offsetQuoteTotal == nil)
            .opacity(offsetQuoteTotal == nil ? 0.5 : 1.0)
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

    // MARK: - Network (LIVE — sustainability.getFleetCarbon + getOffsetQuote)

    private struct FleetCarbonWire_403: Decodable {
        let totalKg: Double
        let totalTonnes: Double
        let loadCount: Int
        let netZeroProgressPct: Double
        let savedTonnes: Double
        let ytdYear: Int
    }
    private struct OffsetQuoteWire_403: Decodable {
        let tonnesCO2e: Double
        let usdPerTonne: Double
        let subtotal: Double
        let platformFee: Double
        let total: Double
        let provider: String?
    }
    private struct OffsetQuoteInput_403: Encodable { let tonnesCO2e: Double }

    private func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }

        do {
            let carbon: FleetCarbonWire_403 =
                try await EusoTripAPI.shared.queryNoInput("sustainability.getFleetCarbon")

            var quote: OffsetQuoteWire_403? = nil
            if carbon.totalTonnes > 0 {
                quote = try? await EusoTripAPI.shared.query(
                    "sustainability.getOffsetQuote",
                    input: OffsetQuoteInput_403(tonnesCO2e: carbon.totalTonnes))
            }
            offsetQuoteTotal = quote?.total

            let progress = min(1.0, max(0.0, carbon.netZeroProgressPct / 100.0))
            vm = FleetCarbonVM_403(
                co2eYTD: carbon.totalTonnes > 0
                    ? String(format: "%.1f t", carbon.totalTonnes)
                    : (carbon.loadCount > 0 ? "0 t" : "—"),
                intensityInline: carbon.loadCount > 0
                    ? "\(carbon.loadCount) load\(carbon.loadCount == 1 ? "" : "s") YTD" : "—",
                vsSmartWay: "—",   // no SmartWay benchmark on the live rollup
                offsetToNetZero: quote.map { money_403($0.total) } ?? "—",
                benchmarkFrac: 0,
                fleetFrac: progress,
                bandCaption: carbon.loadCount > 0
                    ? String(format: "%.1f t saved vs dry-van baseline · net-zero progress %d%%",
                             carbon.savedTonnes, Int(carbon.netZeroProgressPct.rounded()))
                    : "No load emissions recorded yet this year",
                intensity: "—",        // g/ton-mi intensity not on the live rollup
                intensityYoY: "—",
                fleetMPG: "—",         // no MPG rollup on any wired proc
                mpgDelta: "—",
                offsetCost: quote.map { String(format: "$%.0f/t", $0.usdPerTonne) } ?? "—",
                lanes: [],             // per-lane intensity not on the live rollup
                laneAvg: 0, laneMax: 100,
                insightTitle: carbon.savedTonnes > 0
                    ? String(format: "%.1f t CO₂e saved vs dry-van baseline", carbon.savedTonnes)
                    : "No emissions insight yet",
                insightSub: carbon.loadCount > 0
                    ? "Computed from \(carbon.loadCount) real load\(carbon.loadCount == 1 ? "" : "s") · EPA SmartWay factors"
                    : "Live load data populates this surface."
            )
        } catch {
            vm = .empty
            offsetQuoteTotal = nil
            loadError = "Couldn't reach the sustainability service - retry."
        }
    }

    private func money_403(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
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
