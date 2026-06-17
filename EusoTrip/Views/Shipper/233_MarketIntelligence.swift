//
//  233_MarketIntelligence.swift
//  EusoTrip — Shipper · Market Intelligence (Operations).
//
//  Registry id: "330" (2026-06-09 dedup — formerly mis-registered as
//  "233", which the 231-240 system-integration series owns for the
//  Watch Complication; the duplicate id shadowed the Watch screen).
//  The disk number stays 233 per the iOS-numbering-vs-SVG-catalog
//  doctrine (reconcile by purpose, never renumber working files).
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

// MARK: - Consolidated Market Hub (Hot Zones + Market Intelligence tabs)

/// Founder 2026-06-17: consolidate Hot Zones and Market Intelligence into one
/// screen separated by labeled tabs. Both bodies render `embedded` (their own
/// headers suppressed) under a single shared scaffold + a segmented tab bar.
/// Registered for BOTH the 225 (Hot Zones) and 330 (Market Intelligence)
/// slots + voice routes — each entry just opens its corresponding tab.
enum MarketHubTab: String, CaseIterable, Hashable {
    case hotZones = "Hot Zones"
    case market   = "Market Intelligence"
}

struct MarketHubScreen: View {
    let theme: Theme.Palette
    @State private var tab: MarketHubTab

    init(theme: Theme.Palette, initialTab: MarketHubTab = .hotZones) {
        self.theme = theme
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        Shell(theme: theme) {
            VStack(spacing: 0) {
                MarketHubTabBar(selected: $tab)
                Group {
                    if tab == .hotZones {
                        ShipperHotZones(embedded: true)
                    } else {
                        MarketIntelligenceBody(embedded: true)
                    }
                }
            }
        } nav: { shipperLifecycleNav() }
    }
}

/// Bespoke segmented tab bar — pill selection on the brand gradient.
private struct MarketHubTabBar: View {
    @Binding var selected: MarketHubTab
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MarketHubTab.allCases, id: \.self) { t in
                let isOn = (t == selected)
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { selected = t }
                } label: {
                    Text(t.rawValue)
                        .font(EType.bodyStrong)
                        .foregroundStyle(isOn ? Color.white : palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isOn
                                      ? AnyShapeStyle(LinearGradient.primary)
                                      : AnyShapeStyle(palette.bgCardSoft))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(palette.borderFaint, lineWidth: isOn ? 0 : 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(t.rawValue) tab")
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.top, Space.s3)
        .padding(.bottom, Space.s2)
    }
}

// MARK: - Wire types (mirror frontend/server/routers/marketPricing.ts)

/// Numeric fields on the commodity feed are stringified by some
/// upstream sources (CommodityPriceAPI returns "71.25" instead of
/// 71.25 on a fraction of symbols; FRED's tail values too). A strict
/// Double decoder crashed the entire screen on
/// `commodities[5].price` whenever a single symbol from a 30+ row
/// list happened to come in as a string. This decoder accepts both
/// representations transparently. Founder bug 2026-05-24.
private func decodeFlexibleDouble(_ container: KeyedDecodingContainer<CommodityRow.CodingKeys>, _ key: CommodityRow.CodingKeys) throws -> Double {
    if let d = try? container.decode(Double.self, forKey: key) { return d }
    if let s = try? container.decode(String.self, forKey: key), let d = Double(s) { return d }
    if let i = try? container.decode(Int.self, forKey: key) { return Double(i) }
    throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Expected number or numeric string for \(key.stringValue)")
}

private func decodeFlexibleDoubleOpt(_ container: KeyedDecodingContainer<CommodityRow.CodingKeys>, _ key: CommodityRow.CodingKeys) -> Double? {
    if let d = try? container.decode(Double.self, forKey: key) { return d }
    if let s = try? container.decode(String.self, forKey: key), let d = Double(s) { return d }
    if let i = try? container.decode(Int.self, forKey: key) { return Double(i) }
    return nil
}

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

    enum CodingKeys: String, CodingKey {
        case symbol, name, category, price, change, changePercent
        case previousClose, open, high, low, volume
        case intraday, daily, weekly, unit, sparkline
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol         = try c.decode(String.self, forKey: .symbol)
        name           = try c.decode(String.self, forKey: .name)
        category       = try c.decode(String.self, forKey: .category)
        price          = try decodeFlexibleDouble(c, .price)
        change         = try decodeFlexibleDouble(c, .change)
        changePercent  = try decodeFlexibleDouble(c, .changePercent)
        previousClose  = decodeFlexibleDoubleOpt(c, .previousClose)
        open           = decodeFlexibleDoubleOpt(c, .open)
        high           = decodeFlexibleDoubleOpt(c, .high)
        low            = decodeFlexibleDoubleOpt(c, .low)
        volume         = try? c.decode(String.self, forKey: .volume)
        intraday       = try? c.decode(String.self, forKey: .intraday)
        daily          = try? c.decode(String.self, forKey: .daily)
        weekly         = try? c.decode(String.self, forKey: .weekly)
        unit           = try? c.decode(String.self, forKey: .unit)
        // Sparkline can come in as [Double] or [String] — be lenient there too.
        if let arr = try? c.decode([Double].self, forKey: .sparkline) {
            sparkline = arr
        } else if let arr = try? c.decode([String].self, forKey: .sparkline) {
            sparkline = arr.compactMap { Double($0) }
        } else {
            sparkline = nil
        }
    }
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

// MARK: - Ticker search wire types (mirror marketPricing.searchCommodity / getQuote)

/// Lenient Double box. Yahoo Finance and CommodityPriceAPI occasionally
/// stringify numeric fields (and the seed feed already does so for a
/// fraction of symbols — see decodeFlexibleDouble above). Wrapping the
/// search/quote envelopes in this box means a single stringified field
/// never aborts the whole decode and blanks the search results. Every
/// numeric field on the search/quote contracts is therefore optional +
/// lenient: a partial envelope renders honest "N/A"/"—" rather than
/// crashing the screen.
private struct FlexDouble: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let i = try? c.decode(Int.self) { value = Double(i); return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        // null / missing / non-numeric — honest absence, never a fabricated 0.
        value = nil
    }
}

private struct SearchInput: Encodable {
    let query: String
}

private struct SearchResultRow: Decodable, Identifiable, Hashable {
    let symbol: String
    let name: String
    let category: String
    let unit: String?
    let source: String?          // "local" | "api"
    private let priceBox: FlexDouble?
    private let changePercentBox: FlexDouble?

    var price: Double? { priceBox?.value }
    var changePercent: Double? { changePercentBox?.value }
    var id: String { symbol }
    var isLive: Bool { (source ?? "").lowercased() == "api" }

    enum CodingKeys: String, CodingKey {
        case symbol, name, category, unit, source
        case priceBox = "price"
        case changePercentBox = "changePercent"
    }
    // Identity is the symbol — the displayed numbers update freely.
    static func == (l: SearchResultRow, r: SearchResultRow) -> Bool { l.symbol == r.symbol }
    func hash(into h: inout Hasher) { h.combine(symbol) }
}

private struct SearchResp: Decodable {
    let results: [SearchResultRow]
    let totalLocal: Int?
    let totalApi: Int?
}

private struct QuoteInput: Encodable {
    let symbol: String
}

/// marketPricing.getQuote. `price` is `Double?` — the server returns null
/// when no source (seed / CommodityPriceAPI / Yahoo) resolves the symbol;
/// the detail card renders "N/A" in that case and NEVER fabricates a price.
/// All OHLC/volume fields are optional + lenient for the same reason.
private struct QuoteResp: Decodable {
    let symbol: String
    let name: String?
    let category: String?
    let unit: String?
    let volume: String?
    let bestSource: String?
    private let priceBox: FlexDouble?
    private let changeBox: FlexDouble?
    private let changePercentBox: FlexDouble?
    private let highBox: FlexDouble?
    private let lowBox: FlexDouble?
    private let openBox: FlexDouble?
    private let previousCloseBox: FlexDouble?

    var price: Double? { priceBox?.value }
    var change: Double? { changeBox?.value }
    var changePercent: Double? { changePercentBox?.value }
    var high: Double? { highBox?.value }
    var low: Double? { lowBox?.value }
    var open: Double? { openBox?.value }
    var previousClose: Double? { previousCloseBox?.value }

    enum CodingKeys: String, CodingKey {
        case symbol, name, category, unit, volume, bestSource
        case priceBox = "price"
        case changeBox = "change"
        case changePercentBox = "changePercent"
        case highBox = "high"
        case lowBox = "low"
        case openBox = "open"
        case previousCloseBox = "previousClose"
    }
}

// MARK: - Body

struct MarketIntelligenceBody: View {
    /// When hosted inside the consolidated Market Hub, the hub owns the
    /// header + tab bar, so this suppresses its own header to avoid a
    /// redundant double title.
    var embedded: Bool = false

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

    // marketPricing.searchCommodity / getQuote (Yahoo-Finance ticker search,
    // parity with the web /market-pricing search box).
    @State private var searchText: String = ""
    @State private var searchResults: [SearchResultRow] = []
    @State private var searchLoading: Bool = false
    @State private var searchError: String? = nil
    @State private var selectedSymbol: String? = nil
    @State private var quote: QuoteResp? = nil
    @State private var quoteLoading: Bool = false
    @State private var quoteError: String? = nil
    @State private var debounceTask: Task<Void, Never>? = nil

    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                if !embedded { header }

                // Yahoo-Finance ticker search (web parity). Sits above the
                // commodity grid so any stock / ETF / commodity is reachable
                // from a single field. Local seed + Yahoo + CommodityPriceAPI
                // are merged server-side; key-free.
                searchField
                if !searchText.isEmpty && searchText.count >= 2 {
                    searchResultsSection
                }
                if let q = quote { quoteCard(q) }

                if loading && commodities.isEmpty && macro == nil && diesel.isEmpty {
                    LifecycleCard {
                        HStack(spacing: 8) {
                            ProgressView().tint(LinearGradient.diagonal).scaleEffect(0.8)
                            Text("Loading live commodity feed…")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                } else {
                    if !commodities.isEmpty {
                        breadthBar
                        if !categories.isEmpty { categoryChips }
                        commodityGrid
                    } else if !loading {
                        // Honest empty state when the canonical feed
                        // returns no rows. Surfaces the error if any
                        // (was silently swallowed before) + retry.
                        commodityFallbackCard
                    }
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
                Spacer(minLength: 4)
                // Explicit refresh affordance (founder 2026-06-11):
                // pull-to-refresh alone is undiscoverable — mirror the
                // brief widget's visible ↻ button. Spins while a manual
                // reload is in flight; disabled to prevent stacking.
                Button {
                    guard !loading else { return }
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(loading
                                         ? AnyShapeStyle(palette.textTertiary)
                                         : AnyShapeStyle(LinearGradient.diagonal))
                        .rotationEffect(.degrees(loading ? 360 : 0))
                        .animation(loading
                                   ? .linear(duration: 1).repeatForever(autoreverses: false)
                                   : .default,
                                   value: loading)
                }
                .buttonStyle(.plain)
                .disabled(loading)
                .accessibilityLabel("Refresh market data")
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

    // MARK: Ticker search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            TextField(
                "",
                text: $searchText,
                prompt: Text("Search any ticker, stock or commodity…")
                    .foregroundColor(palette.textTertiary)
            )
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(palette.textPrimary)
            // Don't force-uppercase: the field accepts both tickers ("AAPL")
            // and plain names ("soybeans"); the server matches case-
            // insensitively, so we preserve exactly what the user types.
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .submitLabel(.search)
            .onSubmit {
                let q = searchText.trimmingCharacters(in: .whitespaces)
                if q.count >= 2 { Task { await searchTickers(q) } }
            }
            .onChange(of: searchText) { _, newValue in
                // Debounce 300ms (mirror HereAddressField.swift:169-175):
                // cancel the prior task, sleep, bail if cancelled, then fire.
                debounceTask?.cancel()
                let q = newValue.trimmingCharacters(in: .whitespaces)
                if q.count < 2 {
                    searchResults = []
                    searchError = nil
                    searchLoading = false
                    return
                }
                searchLoading = true
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if Task.isCancelled { return }
                    await searchTickers(q)
                }
            }
            if searchLoading {
                ProgressView().tint(LinearGradient.diagonal).scaleEffect(0.7)
            } else if !searchText.isEmpty {
                Button {
                    debounceTask?.cancel()
                    searchText = ""
                    searchResults = []
                    searchError = nil
                    selectedSymbol = nil
                    quote = nil
                    quoteError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear ticker search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    // MARK: Search results

    @ViewBuilder
    private var searchResultsSection: some View {
        if let err = searchError {
            LifecycleCard(accentWarning: true) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Couldn't reach market data")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text(err)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button {
                        Task { await searchTickers(searchText.trimmingCharacters(in: .whitespaces)) }
                    } label: {
                        Text("Retry")
                            .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(LinearGradient.diagonal))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if !searchResults.isEmpty {
            VStack(spacing: 8) {
                ForEach(searchResults) { row in
                    searchResultRow(row)
                }
            }
        } else if !searchLoading {
            // Honest empty state — debounce settled, no matches. Never a
            // fabricated row.
            LifecycleCard {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                    Text("No matches for “\(searchText)”")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultRow(_ row: SearchResultRow) -> some View {
        let selected = (selectedSymbol == row.symbol)
        Button {
            selectedSymbol = row.symbol
            Task { await loadQuote(row.symbol) }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 6) {
                        Text(row.symbol)
                            .font(EType.mono(.micro)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        Text(row.category.uppercased())
                            .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(LinearGradient.diagonal)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(palette.bgCardSoft))
                        if row.isLive {
                            Text("LIVE")
                                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Brand.success))
                        }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    // Honest: server can omit a price on a stringify miss.
                    Text(row.price.map(formatPrice) ?? "N/A")
                        .font(.system(size: 15, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    if let pct = row.changePercent {
                        let positive = pct >= 0
                        HStack(spacing: 3) {
                            Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 8, weight: .heavy))
                            Text(formatChange(pct))
                                .font(.system(size: 11, weight: .heavy)).monospacedDigit()
                        }
                        .foregroundStyle(positive ? Brand.success : Brand.danger)
                    } else {
                        Text("—")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(selected ? palette.bgCardSoft : palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Quote detail card

    @ViewBuilder
    private func quoteCard(_ q: QuoteResp) -> some View {
        let pct = q.changePercent
        let positive = (pct ?? 0) >= 0
        let trendColor: Color = positive ? Brand.success : Brand.danger
        LifecycleCard(accentGradient: true) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(q.name ?? q.symbol)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 6) {
                        Text(q.symbol)
                            .font(EType.mono(.micro)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        if let cat = q.category, !cat.isEmpty {
                            Text(cat.uppercased())
                                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(LinearGradient.diagonal)
                        }
                    }
                }
                Spacer(minLength: 0)
                if quoteLoading {
                    ProgressView().tint(LinearGradient.diagonal).scaleEffect(0.7)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Honest: price is Double? — server returns null when no
                // source resolves the symbol. Render "N/A", never a fake 0.
                Text(q.price.map(formatPrice) ?? "N/A")
                    .font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(q.price == nil ? AnyShapeStyle(palette.textTertiary) : AnyShapeStyle(palette.textPrimary))
                if let unit = q.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                if let pct {
                    HStack(spacing: 4) {
                        Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .heavy))
                        Text(formatChange(pct))
                            .font(.system(size: 14, weight: .heavy)).monospacedDigit()
                    }
                    .foregroundStyle(trendColor)
                }
            }
            if let err = quoteError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(palette.borderFaint).padding(.vertical, 2)
            // Compact OHLC / volume grid — honest "—" for any field the
            // server didn't resolve.
            let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 10) {
                quoteStat("OPEN", q.open.map(formatPrice))
                quoteStat("HIGH", q.high.map(formatPrice))
                quoteStat("LOW", q.low.map(formatPrice))
                quoteStat("PREV", q.previousClose.map(formatPrice))
                quoteStat("CHG", q.change.map { String(format: $0 >= 0 ? "+%.2f" : "%.2f", $0) })
                quoteStat("VOL", (q.volume == "N/A" ? nil : q.volume))
            }
            if let src = q.bestSource, !src.isEmpty {
                Text("Source · \(src)")
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func quoteStat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value ?? "—")
                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                .foregroundStyle(value == nil ? palette.textTertiary : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            // Honest: when the reconciled signal hasn't blended a value
            // yet (n<3 providers / unconvertible units), surface a
            // graceful "Awaiting blend" instead of a stiff em-dash.
            if let signal = m.blendedSignal {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "$%.2f", signal))
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Text("/ mi blended")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            } else {
                Text("Awaiting blended signal · needs 3+ providers")
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
                        if let rpm = p.rateRpm {
                            Text(String(format: "$%.2f / mi", rpm))
                                .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                                .foregroundStyle(palette.textPrimary)
                        } else {
                            // Provider observed but no rate this cycle —
                            // honest status, not a stiff dash.
                            Text(p.status?.capitalized ?? "No quote")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func dieselCard(_ rows: [DieselRow]) -> some View {
        // Only show PADD regions the EIA has actually reported a price
        // for — a region with no observation is omitted rather than
        // rendered as a stiff "-".
        let priced = rows.filter { $0.priceUsdPerGallon != nil }
        return LifecycleCard {
            LifecycleSection(label: "DIESEL REGIONALS · EIA", icon: "fuelpump.fill")
            if priced.isEmpty {
                Text("EIA weekly diesel report not yet posted for this cycle.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(priced) { r in
                    LifecycleRow(
                        label: r.region,
                        value: String(format: "$%.3f / gal", r.priceUsdPerGallon ?? 0)
                    )
                }
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
                loadError = nil
            }
        } catch {
            // Founder bug 2026-05-07: silent catch hid the failure
            // so the screen sat on 'Loading live commodity feed…'
            // forever. Capture the error for the fallback card so
            // the user gets a real signal + retry action.
            await MainActor.run {
                loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Empty-state / error card surfaced when marketPricing.getCommodities
    /// returns nothing or errors. Macro + diesel cards still render
    /// independently when they DO load — this card only covers the
    /// commodities slot.
    private var commodityFallbackCard: some View {
        LifecycleCard(accentWarning: loadError != nil) {
            HStack(spacing: 8) {
                Image(systemName: loadError == nil
                      ? "chart.line.flattrend.xyaxis"
                      : "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(loadError == nil
                                     ? AnyShapeStyle(palette.textTertiary)
                                     : AnyShapeStyle(Brand.warning))
                VStack(alignment: .leading, spacing: 2) {
                    Text(loadError == nil
                         ? "Live commodity feed is empty"
                         : "Commodity feed unavailable")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(loadError ?? "FRED + EIA + BLS sources may be in a maintenance window. Pull to refresh in a few minutes.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { Task { await loadCommodities() } } label: {
                    Text("Retry")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(LinearGradient.diagonal))
                }
                .buttonStyle(.plain)
            }
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

    // MARK: Ticker search loaders

    /// marketPricing.searchCommodity — merges local seed + Yahoo Finance +
    /// CommodityPriceAPI server-side (key-free). Honest empty/error states;
    /// never fabricates a result.
    private func searchTickers(_ q: String) async {
        await MainActor.run { searchLoading = true; searchError = nil }
        do {
            let r: SearchResp = try await EusoTripAPI.shared.query(
                "marketPricing.searchCommodity",
                input: SearchInput(query: q)
            )
            await MainActor.run {
                // Guard against a stale debounce landing after the user
                // cleared / changed the field.
                guard searchText.trimmingCharacters(in: .whitespaces) == q else { return }
                searchResults = r.results
                searchError = nil
                searchLoading = false
            }
        } catch {
            await MainActor.run {
                guard searchText.trimmingCharacters(in: .whitespaces) == q else { return }
                searchResults = []
                searchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                searchLoading = false
            }
        }
    }

    /// marketPricing.getQuote — cross-referenced single-symbol quote. `price`
    /// may be null; the card renders "N/A". Inline honest error on failure.
    private func loadQuote(_ symbol: String) async {
        await MainActor.run { quoteLoading = true; quoteError = nil }
        do {
            let q: QuoteResp = try await EusoTripAPI.shared.query(
                "marketPricing.getQuote",
                input: QuoteInput(symbol: symbol)
            )
            await MainActor.run {
                // Ignore a late quote for a row the user moved off of.
                guard selectedSymbol == symbol else { return }
                quote = q
                quoteError = nil
                quoteLoading = false
            }
        } catch {
            await MainActor.run {
                guard selectedSymbol == symbol else { return }
                quote = nil
                quoteError = "Couldn't load \(symbol) quote · pull to refresh or retry."
                quoteLoading = false
            }
        }
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
