//
//  233_MarketIntelligence.swift
//  EusoTrip — Shipper · Market Intelligence (Operations).
//
//  Founder mandate 2026-05-05: web platform's Market Intelligence
//  has commodity prices (WTI / Brent / Gold etc) — iOS Operations
//  was rendering blank because the original implementation only
//  called `marketIntelligence.*` (macro signal + diesel regionals)
//  and skipped `marketPricing.getCommodities`, which is what the
//  web /market-pricing surface actually uses.
//
//  This screen now ports the canonical web feed:
//    • `marketPricing.getCommodities` — full ticker grid (WTI,
//      Brent, Natural Gas, RBOB, Diesel, Ethanol, Propane, Gold,
//      Silver, Copper, Aluminum, Steel HRC, Nickel LME, Corn,
//      Soybeans, Wheat, Cotton, Sugar, Coffee, plus freight
//      indices DVAN/REEF/HAZM/TANK and fuel surcharge FSC/DEF).
//      Includes market-breadth bar + category filter chips.
//    • `marketIntelligence.getReconciledMacroSignal` — kept as a
//      header card so the "blended $/mi" macro line still surfaces
//      alongside the live ticker grid.
//    • `marketIntelligence.getDieselRegionalLatest` — kept as the
//      EIA PADD-region detail strip below commodities.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct MarketIntelligenceScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { MarketIntelligenceBody() } nav: { shipperLifecycleNav() }
    }
}

// MARK: - Wire types (mirror frontend/server/routers/marketPricing.ts)

private struct CommodityRow: Decodable, Hashable, Identifiable {
    let symbol: String
    let name: String
    let category: String
    let price: Double
    let change: Double
    let changePercent: Double
    let previousClose: Double?
    let open: Double?
    let high: Double?
    let low: Double?
    let volume: String?
    let intraday: String?
    let daily: String?
    let weekly: String?
    let unit: String?
    let sparkline: [Double]?
    var id: String { symbol }
}

private struct MarketBreadth: Decodable, Hashable {
    let advancing: Int
    let declining: Int
    let unchanged: Int
}

private struct CommoditiesResp: Decodable {
    let commodities: [CommodityRow]
    let categories: [String]
    let marketBreadth: MarketBreadth
    let lastUpdated: String?
    let isLiveData: Bool?
    let source: String?
}

private struct CommoditiesInput: Encodable {
    let category: String?
    let search: String?
}

private struct MacroProvider: Decodable, Hashable, Identifiable {
    var id: String { provider }
    let provider: String
    let rateRpm: Double?
    let observedAt: String?
    let status: String?
}

private struct MacroSignal: Decodable {
    let available: Bool
    let blendedSignal: Double?
    let confidence: Double?
    let providers: [MacroProvider]?
}

private struct DieselRow: Decodable, Hashable, Identifiable {
    let region: String
    let priceUsdPerGallon: Double?
    let observedAt: String?
    var id: String { region }
}

// MARK: - Body

private struct MarketIntelligenceBody: View {
    @Environment(\.palette) private var palette

    // marketPricing.getCommodities (canonical web feed)
    @State private var commodities: [CommodityRow] = []
    @State private var categories: [String] = []
    @State private var breadth: MarketBreadth = MarketBreadth(advancing: 0, declining: 0, unchanged: 0)
    @State private var sourceLine: String = ""
    @State private var isLive: Bool = false
    @State private var category: String = "ALL"
    @State private var search: String = ""

    // marketIntelligence (legacy panels, kept for parity with the
    // pre-2026-05-05 build — macro $/mi + EIA PADD diesel)
    @State private var macro: MacroSignal? = nil
    @State private var diesel: [DieselRow] = []

    @State private var loading = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && commodities.isEmpty {
                    LifecycleCard {
                        Text("Loading live commodity feed…")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                } else {
                    breadthBar
                    if !categories.isEmpty { categoryChips }
                    commodityGrid
                    if let m = macro { macroCard(m) }
                    if !diesel.isEmpty { dieselCard(diesel) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · MARKET INTELLIGENCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Market Intelligence")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(sourceLine.isEmpty
                 ? "FRED + EIA + BLS + Yahoo Finance · live tickers"
                 : sourceLine)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Market breadth

    private var breadthBar: some View {
        let total = max(breadth.advancing + breadth.declining + breadth.unchanged, 1)
        let advFrac = CGFloat(breadth.advancing) / CGFloat(total)
        let decFrac = CGFloat(breadth.declining) / CGFloat(total)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MARKET BREADTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("+\(breadth.advancing) · -\(breadth.declining)")
                    .font(.system(size: 11, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 6)
                    HStack(spacing: 0) {
                        Capsule().fill(Brand.success).frame(width: w * advFrac, height: 6)
                        Capsule().fill(palette.borderFaint).frame(width: w * (1 - advFrac - decFrac), height: 6)
                        Capsule().fill(Brand.danger).frame(width: w * decFrac, height: 6)
                    }
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: Category chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "All", value: "ALL")
                ForEach(categories, id: \.self) { c in
                    chip(label: c.capitalized, value: c)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(label: String, value: String) -> some View {
        let active = (category == value)
        Button {
            withAnimation(.easeOut(duration: 0.18)) { category = value }
            Task { await load() }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: active ? .heavy : .semibold))
                .foregroundStyle(active ? Color.white : palette.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(
                    Capsule().fill(active ? AnyShapeStyle(LinearGradient.primary)
                                          : AnyShapeStyle(palette.bgCard))
                )
                .overlay(Capsule().strokeBorder(active ? Color.clear : palette.borderFaint))
        }
        .buttonStyle(.plain)
    }

    // MARK: Commodity grid

    private var commodityGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(commodities) { row in
                commodityCard(row)
            }
        }
    }

    @ViewBuilder
    private func commodityCard(_ row: CommodityRow) -> some View {
        let positive = row.changePercent >= 0
        let trendColor: Color = positive ? Brand.success : Brand.danger
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 4) {
                        Text(row.symbol)
                            .font(EType.mono(.micro)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        Text(row.category.uppercased())
                            .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                }
                Spacer(minLength: 0)
                MiniSparkline(values: row.sparkline ?? [], color: trendColor)
                    .frame(width: 56, height: 22)
            }
            Text(formatPrice(row.price))
                .font(.system(size: 19, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            HStack(spacing: 4) {
                Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(trendColor)
                Text(formatChange(row.changePercent))
                    .font(.system(size: 11, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(trendColor)
                Spacer(minLength: 0)
                if let unit = row.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    private func formatPrice(_ v: Double) -> String {
        if v >= 100 { return String(format: "%.2f", v) }
        if v >= 10  { return String(format: "%.3f", v) }
        return String(format: "%.4f", v)
    }
    private func formatChange(_ v: Double) -> String {
        String(format: v >= 0 ? "+%.2f%%" : "%.2f%%", v)
    }

    // MARK: Macro / diesel cards (legacy panels — kept for parity)

    private func macroCard(_ m: MacroSignal) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "MACRO BLENDED $/MI", icon: "chart.line.uptrend.xyaxis")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(m.blendedSignal.map { String(format: "$%.2f", $0) } ?? "—")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("/ mi blended")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            if let conf = m.confidence {
                LifecycleRow(label: "Confidence", value: String(format: "%.0f%%", conf * 100))
            }
            if let providers = m.providers, !providers.isEmpty {
                Divider().overlay(palette.borderFaint).padding(.vertical, 4)
                ForEach(providers) { p in
                    HStack {
                        Text(p.provider.uppercased())
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Spacer(minLength: 0)
                        Text(p.rateRpm.map { String(format: "$%.2f / mi", $0) } ?? "—")
                            .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func dieselCard(_ rows: [DieselRow]) -> some View {
        LifecycleCard {
            LifecycleSection(label: "DIESEL REGIONALS · EIA", icon: "fuelpump.fill")
            ForEach(rows) { r in
                LifecycleRow(
                    label: r.region,
                    value: r.priceUsdPerGallon.map { String(format: "$%.3f / gal", $0) } ?? "—"
                )
            }
        }
    }

    // MARK: Loaders

    private func load() async {
        loading = true
        defer { Task { @MainActor in loading = false } }
        async let commoditiesT: Void = loadCommodities()
        async let macroT: Void = loadMacro()
        async let dieselT: Void = loadDiesel()
        _ = await (commoditiesT, macroT, dieselT)
    }

    private func loadCommodities() async {
        do {
            let r: CommoditiesResp = try await EusoTripAPI.shared.query(
                "marketPricing.getCommodities",
                input: CommoditiesInput(
                    category: category == "ALL" ? nil : category,
                    search: search.isEmpty ? nil : search
                )
            )
            await MainActor.run {
                commodities = r.commodities
                categories = r.categories
                breadth = r.marketBreadth
                isLive = r.isLiveData ?? false
                if let s = r.source, !s.isEmpty {
                    sourceLine = s
                }
            }
        } catch {
            // Silent — keeps prior data on failure so a transient
            // outage doesn't blank the board.
        }
    }

    private func loadMacro() async {
        do {
            let m: MacroSignal = try await EusoTripAPI.shared.queryNoInput(
                "marketIntelligence.getReconciledMacroSignal"
            )
            await MainActor.run { macro = m }
        } catch { /* silent */ }
    }

    private func loadDiesel() async {
        struct Resp: Decodable { let rows: [DieselRow]? }
        do {
            let r: Resp = try await EusoTripAPI.shared.queryNoInput(
                "marketIntelligence.getDieselRegionalLatest"
            )
            await MainActor.run { diesel = r.rows ?? [] }
        } catch { /* silent */ }
    }
}

// MARK: - Mini sparkline

private struct MiniSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = values.isEmpty ? [0.5, 0.5] : normalized(values)
            Path { p in
                guard pts.count >= 2 else { return }
                let stepX = geo.size.width / CGFloat(pts.count - 1)
                p.move(to: CGPoint(x: 0, y: geo.size.height * (1 - pts[0])))
                for i in 1..<pts.count {
                    p.addLine(to: CGPoint(
                        x: stepX * CGFloat(i),
                        y: geo.size.height * (1 - pts[i])
                    ))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }

    private func normalized(_ vs: [Double]) -> [CGFloat] {
        guard let lo = vs.min(), let hi = vs.max(), hi > lo else {
            return vs.map { _ in 0.5 }
        }
        return vs.map { CGFloat(($0 - lo) / (hi - lo)) }
    }
}

#Preview("233 · Market Intelligence · Night") {
    MarketIntelligenceScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("233 · Market Intelligence · Afternoon") {
    MarketIntelligenceScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
