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

    /// The user's pinned commodity/stock symbols + customize state. When
    /// `customized` the grid renders only `selectedSymbols`; otherwise it
    /// shows the full server feed (preserves the pre-customize behavior).
    /// Mutated by `MarketCustomizeView` (pushed in-stack via the canonical
    /// `\.rolePushDetail` layer — NOT a slide-up modal).
    @EnvironmentObject private var watchlist: MarketWatchlistStore

    /// Canonical in-stack push closure (slides in from the trailing edge,
    /// topped with a `BespokeBackBar`). Injected by the shipper surface's
    /// `RoleDetailLayer`; `NavigationLink`/`NavigationStack` are banned
    /// platform-wide, so this is the push-nav mechanism for the Customize
    /// editor.
    @Environment(\.rolePushDetail) private var pushDetail

    /// Which commodity/stock tiles are showing their flip-back face. Keyed
    /// by `row.symbol`, owned here per the FlipTile contract (the primitive
    /// carries no flip state of its own).
    @State private var flippedSymbols: Set<String> = []

    /// Default browse tiles stay compact. Only the tapped/flipped row expands
    /// to the detail height, so customization does not trade a usable grid for
    /// large invisible gutters.
    private let frontTileHeight: CGFloat = 192
    private let detailTileHeight: CGFloat = 296

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
    private let commodityLoadTimeoutNanoseconds: UInt64 = 10_000_000_000

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

                if loading && commodities.isEmpty && macro == nil && diesel.isEmpty && loadError == nil {
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
                        gridToolbar
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
                // Floating-nav clearance. This body runs inside MarketHubScreen
                // as an INNER ScrollView (under the segmented tab bar), so the
                // Shell's own bottom inset sits below this scroller — not inside
                // it. Match the Shell's canonical floating-nav clearance
                // (Device.navHeight + safeBottom + Space.s4 = 120pt) so the last
                // tile row (e.g. Ultra-Low Sulfur Diesel) fully clears the nav
                // plate AND the lifted ESANG orb. A bare 96 left the last row
                // behind the orb (founder 2026-06-18).
                Color.clear.frame(height: Device.navHeight + Device.safeBottom + Space.s8)
            }
            .padding(.horizontal, 14)
            .padding(.top, embedded ? Device.safeTop + Space.s4 : 56)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value ?? "—")
                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                .foregroundStyle(value == nil ? palette.textTertiary : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: Customize toolbar

    /// Opens the Customize editor in-stack (trailing-edge slide + back bar)
    /// via the canonical push layer. `NavigationLink`/`NavigationStack` are
    /// banned platform-wide, so this is the push-nav mechanism. No-op if
    /// the surface didn't inject the closure (e.g. SwiftUI preview).
    ///
    /// The editor reads the SAME `MarketWatchlistStore` via
    /// `@EnvironmentObject` (NOT a constructor-passed `@ObservedObject` —
    /// a store captured once inside the type-erased `AnyView` the surface
    /// holds in `@State` did not reliably re-publish into the editor's own
    /// rows, so toggles "didn't complete"; the environment object resolves
    /// fresh on every body pass through the AnyView). `onDone` posts the
    /// shipper NavBack so the bespoke "Done" button dismisses the editor
    /// back to the grid exactly like the back chevron.
    private func openCustomize() {
        let all = commodities
        pushDetail?("Customize tiles") {
            AnyView(
                MarketCustomizeView(
                    allCommodities: all,
                    onDone: {
                        NotificationCenter.default.post(
                            name: .eusoShipperNavBack, object: nil)
                    }
                )
            )
        }
    }

    /// Inline toolbar above the grid — always rendered (so the Customize
    /// affordance is reachable even when the consolidated Market Hub
    /// suppresses this body's own header). Shows the count + a bespoke
    /// Customize pill.
    private var gridToolbar: some View {
        HStack(spacing: 8) {
            Text(watchlist.customized ? "YOUR TILES" : "ALL COMMODITIES")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            if watchlist.customized {
                Text("\(visibleCommodities.count)")
                    .font(.system(size: 9, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            Spacer(minLength: 0)
            Button { openCustomize() } label: {
                HStack(spacing: 5) {
                    SlidersGlyph()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .frame(width: 12, height: 12)
                    Text(watchlist.customized ? "Edit" : "Customize")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(watchlist.customized
                                ? "Edit your tiles"
                                : "Customize tiles")
        }
    }

    // MARK: Commodity grid

    /// The rows the grid actually renders. When the user has customized,
    /// filter the loaded feed down to their pinned symbols (preserving the
    /// feed's order); otherwise show the full feed. Never fabricates a row —
    /// a pinned symbol not present in the current category/feed simply
    /// doesn't appear (the editor lists every loaded + searchable symbol so
    /// the user can re-add it).
    private var visibleCommodities: [CommodityRow] {
        guard watchlist.customized else { return commodities }
        let pinned = Set(watchlist.selectedSymbols)
        return commodities.filter { pinned.contains($0.symbol) }
    }

    @ViewBuilder
    private var commodityGrid: some View {
        let visible = visibleCommodities
        if watchlist.customized && visible.isEmpty {
            customizedEmptyCard
        } else {
            let cols = [
                GridItem(.flexible(), spacing: 12, alignment: .top),
                GridItem(.flexible(), spacing: 12, alignment: .top)
            ]
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(visible) { row in
                    let isFlipped = flippedSymbols.contains(row.symbol)
                    FlipTile(isFlipped: isFlipped) {
                        commodityCard(row)
                    } back: {
                        commodityCardBack(row)
                    }
                    .frame(height: isFlipped ? detailTileHeight : frontTileHeight)
                    .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isFlipped)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                            if isFlipped { flippedSymbols.remove(row.symbol) }
                            else { flippedSymbols.insert(row.symbol) }
                        }
                    }
                    .sensoryFeedback(.selection, trigger: isFlipped)
                }
            }
        }
    }

    /// Honest empty-state when the user customized but none of their pinned
    /// symbols are in the current feed/category. Never auto-fabricates tiles.
    private var customizedEmptyCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("No tiles selected — tap Customize to choose commodities or stocks")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your pinned symbols may also live under a different category filter above.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { openCustomize() } label: {
                        HStack(spacing: 6) {
                            SlidersGlyph()
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                                .frame(width: 13, height: 13)
                            Text("Customize")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(LinearGradient.diagonal))
                    }
                    .buttonStyle(.plain)
                    Button { watchlist.resetToDefault() } label: {
                        Text("Show all")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(palette.bgCardSoft))
                            .overlay(Capsule().strokeBorder(palette.borderFaint))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
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
                // Trend chip mirrors the flip-back's hero chip — a small
                // colored badge in the header now that the sparkline moved
                // full-bleed below.
                Text(positive ? "▲" : "▼")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(trendColor))
            }
            // Full-bleed sparkline (matches the flip-back's live pulse) that
            // FLEXES to fill the taller front face, so it reads as a
            // deliberate hero card instead of a short card padded with dead
            // space. (Replaces the old fixed 42pt height + trailing Spacer —
            // the flex now pins price/change/hint to the bottom.)
            MiniSparkline(values: row.sparkline ?? [], color: trendColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(formatPrice(row.price))
                .font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
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
            // Tap-to-flip hint — earns the extra height + tells the user the
            // card is interactive (drawn ellipsis, no SF Symbol).
            HStack(spacing: 4) {
                FlipHintGlyph()
                    .stroke(palette.textTertiary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 14, height: 4)
                Text("Tap for detail")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            // On-brand EusoTrip gradient outline (blue→magenta) instead of the
            // flat faint hairline, so the commodity tiles read as branded cards.
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
        // Hard clip: front content can never bleed past the tile into a neighbour.
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Commodity flip-back (the bespoke drill-down)

    /// The flip-back face of a commodity/stock tile — the "catch my eyes"
    /// drill-down replacement for the boring stat-list detail screens. Same
    /// outer frame as the front (Radius.md, palette.bgCard fill) with a
    /// trend-tinted border. Built ENTIRELY from already-decoded
    /// `CommodityRow` fields (no new network call — the grid already carries
    /// OHLC + sparkline). Zero SF Symbols: the chevron + CTA arrow are drawn
    /// shapes. Every value is real or an em-dash; absent rows drop out.
    @ViewBuilder
    private func commodityCardBack(_ row: CommodityRow) -> some View {
        let positive = row.changePercent >= 0
        let trendColor: Color = positive ? Brand.success : Brand.danger
        let pinned = watchlist.selectedSymbols.contains(row.symbol)
        VStack(alignment: .leading, spacing: 9) {
            // 1 — HEADER ROW: name + drawn back chevron, diagonal underline.
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Text(row.name)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    // Drawn chevron-back glyph — a flip affordance, NOT an
                    // SF Symbol. The tap is owned by the FlipTile container.
                    ChevronBackGlyph()
                        .stroke(trendColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 8, height: 12)
                        .accessibilityLabel("Flip back")
                }
                LinearGradient.diagonal
                    .frame(height: 2)
                    .clipShape(Capsule())
            }

            // 2 — HERO METRIC: the price, large, with a colored change% chip.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatPrice(row.price))
                    .font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 3) {
                    ChangeArrowGlyph(up: positive)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 7, height: 7)
                    Text(formatChange(row.changePercent))
                        .font(.system(size: 11, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(positive ? Brand.success : Brand.danger))
                Spacer(minLength: 0)
            }

            // 3 — LIVE PULSE: full-width sparkline. Honest — an empty series
            // draws a flat baseline (MiniSparkline handles it), never faked.
            MiniSparkline(values: row.sparkline ?? [], color: trendColor)
                .frame(maxWidth: .infinity)
                .frame(height: 40)

            // 4 — STAT GRID: the remaining REAL OHLC/volume fields. Absent
            // optional → em-dash; unit only when present.
            let cols = [GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading)]
            LazyVGrid(columns: cols, spacing: 8) {
                backStat("OPEN", row.open.map(formatPrice))
                backStat("HIGH", row.high.map(formatPrice))
                backStat("LOW", row.low.map(formatPrice))
                backStat("PREV", row.previousClose.map(formatPrice))
                backStat("VOLUME", (row.volume == "N/A" ? nil : row.volume))
                if let unit = row.unit, !unit.isEmpty {
                    backStat("UNIT", unit)
                }
            }

            // 5 — CTA PILL: pin/unpin to the watchlist (the real action). No
            // Platts/Argus/Baltic/DAT benchmark — unlicensed + absent from
            // the feed, so never surfaced here.
            Button {
                if pinned { watchlist.remove(row.symbol) }
                else { watchlist.add(row.symbol) }
            } label: {
                HStack(spacing: 6) {
                    Text(pinned ? "Remove from watchlist" : "Add to watchlist")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                    CtaArrowGlyph()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 12, height: 9)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(pinned
                                   ? AnyShapeStyle(palette.bgCardSoft)
                                   : AnyShapeStyle(LinearGradient.diagonal))
                )
                .overlay(
                    Capsule().strokeBorder(pinned ? palette.borderFaint : Color.clear)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        // Identical outer frame to the FRONT face — fills the FlipTile's
        // expanded detail height and clips inside the card.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(trendColor.opacity(0.55), lineWidth: 1)
        )
        // Hard clip: back content can never bleed past the tile into a neighbour.
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// One micro-label-over-value stat for the flip-back grid. Absent value
    /// renders an em-dash in textTertiary — never a fabricated number.
    @ViewBuilder
    private func backStat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value ?? "—")
                .font(EType.bodyStrong).monospacedDigit()
                .foregroundStyle(value == nil ? palette.textTertiary : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        let categoryArg = category == "ALL" ? nil : category
        let searchArg = search.isEmpty ? nil : search
        let timeout = commodityLoadTimeoutNanoseconds
        let result: Result<CommoditiesResp, Error> = await withTaskGroup(
            of: Result<CommoditiesResp, Error>.self
        ) { group in
            group.addTask {
                do {
                    let r: CommoditiesResp = try await EusoTripAPI.shared.query(
                        "marketPricing.getCommodities",
                        input: CommoditiesInput(category: categoryArg, search: searchArg)
                    )
                    return .success(r)
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeout)
                return .failure(URLError(.timedOut))
            }
            let first = await group.next() ?? .failure(URLError(.unknown))
            group.cancelAll()
            return first
        }

        switch result {
        case .success(let r):
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
        case .failure(let error):
            // Founder bug 2026-05-07: silent catch hid the failure
            // so the screen sat on 'Loading live commodity feed…'
            // forever. Capture the error for the fallback card so
            // the user gets a real signal + retry action.
            await MainActor.run {
                loadError = error.eusoUserCopy
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

// MARK: - Bespoke drawn glyphs (zero SF Symbols on the flip-backs / editor)

/// A chevron pointing left — the flip-back affordance. Drawn, never an SF
/// Symbol. Sized by the caller's frame; stroked by the caller.
private struct ChevronBackGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

/// A small up/down trend arrow (diagonal stem + two barbs) for the change
/// chip. `up == true` points up-right; otherwise down-right.
private struct ChangeArrowGlyph: Shape {
    let up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if up {
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.move(to: CGPoint(x: r.maxX - r.width * 0.62, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.62))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.move(to: CGPoint(x: r.maxX - r.width * 0.62, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.62))
        }
        return p
    }
}

/// A right-pointing arrow (shaft + head) for the CTA pill — drawn, not an
/// SF Symbol.
private struct CtaArrowGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.move(to: CGPoint(x: r.maxX - r.width * 0.4, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.4, y: r.maxY))
        return p
    }
}

/// Three horizontal sliders (the "customize" affordance) — drawn, not the
/// `slider.horizontal.3` SF Symbol.
private struct SlidersGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let rows: [(CGFloat, CGFloat)] = [(0.18, 0.66), (0.50, 0.34), (0.82, 0.58)]
        for (yFrac, knobFrac) in rows {
            let y = r.minY + r.height * yFrac
            p.move(to: CGPoint(x: r.minX, y: y))
            p.addLine(to: CGPoint(x: r.maxX, y: y))
            let kx = r.minX + r.width * knobFrac
            p.addEllipse(in: CGRect(x: kx - 1.4, y: y - 1.4, width: 2.8, height: 2.8))
        }
        return p
    }
}

/// Three dots in a row (the "more / tap for detail" hint) for the front
/// face — drawn, never the `ellipsis` SF Symbol.
private struct FlipHintGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let d = min(r.height, r.width / 5)
        let y = r.midY
        for frac in [CGFloat(0.0), 0.5, 1.0] {
            let cx = r.minX + (r.width - d) * frac + d / 2
            p.addEllipse(in: CGRect(x: cx - d / 2, y: y - d / 2, width: d, height: d))
        }
        return p
    }
}

/// A drawn check mark for the editor's "selected" affordance — never the
/// `checkmark` SF Symbol.
private struct CheckGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

// MARK: - Market Customize editor (pushed in-stack)
//
// Lists every loaded commodity/stock row with an add/remove toggle bound to
// watchlist membership, a "Show all (default)" reset, and the live ticker
// search so the user can add ANY resolvable symbol. Reorder is out of
// scope. Bespoke styling — palette + Capsule pills + LinearGradient.diagonal
// selection + a DRAWN check glyph. Zero SF Symbols. The view is pushed (NOT
// presented as a slide-up modal) via `\.rolePushDetail` so the
// `BespokeBackBar` provides the back affordance.
private struct MarketCustomizeView: View {
    let allCommodities: [CommodityRow]
    /// Posts the shipper NavBack so the bespoke "Done" button dismisses the
    /// editor back to the grid (parity with the back chevron).
    let onDone: () -> Void

    /// The SAME store the grid reads. Resolved via `@EnvironmentObject` (NOT
    /// a constructor-passed `@ObservedObject`): the editor is pushed as a
    /// type-erased `AnyView` held in the surface's `@State`, and an
    /// `@ObservedObject` captured inside that one-time AnyView snapshot did
    /// NOT reliably re-publish into the editor's own rows — so toggles
    /// mutated the store but the check glyph / count / PINNED label never
    /// repainted ("nothing completes the action"). The environment object
    /// resolves fresh on every body pass through the AnyView, so a pin now
    /// reflects instantly in BOTH the editor and the grid behind it.
    @EnvironmentObject private var watchlist: MarketWatchlistStore
    @Environment(\.palette) private var palette

    // Live ticker search (reuses the same marketPricing.searchCommodity
    // proc as the main screen, so the user can pin ANY resolvable symbol —
    // not just the ones currently in the feed).
    @State private var searchText: String = ""
    @State private var searchResults: [SearchResultRow] = []
    @State private var searchLoading: Bool = false
    @State private var searchError: String? = nil
    @State private var debounceTask: Task<Void, Never>? = nil

    /// How many tiles the grid will actually render after this edit — the
    /// honest count for the "Done · Showing N tiles" confirm. When the user
    /// hasn't customized, the grid shows the FULL feed; once customized it
    /// shows the intersection of their pins with the loaded feed (a pinned
    /// symbol not in the current feed simply doesn't render a tile yet).
    private var visibleTileCount: Int {
        guard watchlist.customized else { return allCommodities.count }
        let pinned = Set(watchlist.selectedSymbols)
        return allCommodities.filter { pinned.contains($0.symbol) }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                intro
                searchField
                if searchText.trimmingCharacters(in: .whitespaces).count >= 2 {
                    searchResultsSection
                }
                resetRow
                feedList
                doneButton
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
    }

    // MARK: Done / Save (the explicit COMPLETING affordance)

    /// The bespoke confirm. Every toggle already persists through the store
    /// (UserDefaults-authoritative), so this button doesn't "save" new data —
    /// it CONFIRMS the selection and dismisses back to the grid, and the
    /// label surfaces the honest live tile count so the founder's "no
    /// confirming or saving" is answered with an explicit, visible action.
    private var doneButton: some View {
        let count = visibleTileCount
        let label = watchlist.customized
            ? "Done · Showing \(count) tile\(count == 1 ? "" : "s")"
            : "Done · Showing all \(count) tiles"
        return Button { onDone() } label: {
            HStack(spacing: 8) {
                CheckGlyph()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                    .frame(width: 14, height: 11)
                Text(label)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(LinearGradient.diagonal))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("CUSTOMIZE TILES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                // Live selected-count chip — updates the instant a row
                // toggles so the action visibly "completes" in the editor
                // (founder: "definitely not reflecting").
                Text(watchlist.customized
                     ? "\(watchlist.selectedSymbols.count) PINNED"
                     : "ALL")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            Text("Choose your grid")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(watchlist.customized
                 ? "Showing only your \(watchlist.selectedSymbols.count) pinned symbol\(watchlist.selectedSymbols.count == 1 ? "" : "s"). Tap to add or remove; search to pin any ticker."
                 : "Showing the full live feed. Tap any symbol to pin it — pinned symbols become your grid. Search to add any stock or commodity.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Reset row

    @ViewBuilder
    private var resetRow: some View {
        let isDefault = !watchlist.customized
        Button { watchlist.resetToDefault() } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isDefault ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
                        .frame(width: 22, height: 22)
                    if isDefault {
                        CheckGlyph()
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            .frame(width: 10, height: 8)
                    }
                }
                .overlay(Circle().strokeBorder(isDefault ? Color.clear : palette.borderFaint).frame(width: 22, height: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show all (default)")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Render the full live feed; clear all pins.")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isDefault ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Feed list

    @ViewBuilder
    private var feedList: some View {
        if allCommodities.isEmpty {
            LifecycleCard {
                Text("The live feed hasn't loaded any symbols yet. Use search above to pin a ticker, or pull to refresh on the main screen.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("FROM THE LIVE FEED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                ForEach(allCommodities) { row in
                    feedRow(
                        symbol: row.symbol,
                        name: row.name,
                        category: row.category,
                        selected: watchlist.selectedSymbols.contains(row.symbol)
                    )
                }
            }
        }
    }

    /// A single selectable symbol row — drawn check on a gradient disc when
    /// pinned. Toggling calls `watchlist.add` / `watchlist.remove`.
    @ViewBuilder
    private func feedRow(symbol: String, name: String, category: String, selected: Bool) -> some View {
        Button {
            if selected { watchlist.remove(symbol) }
            else { watchlist.add(symbol) }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
                        .frame(width: 22, height: 22)
                    if selected {
                        CheckGlyph()
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            .frame(width: 10, height: 8)
                    }
                }
                .overlay(Circle().strokeBorder(selected ? Color.clear : palette.borderFaint).frame(width: 22, height: 22))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 6) {
                        Text(symbol)
                            .font(EType.mono(.micro)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        if !category.isEmpty {
                            Text(category.uppercased())
                                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(LinearGradient.diagonal)
                        }
                    }
                }
                Spacer(minLength: 0)
                Text(selected ? "PINNED" : "ADD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Search (reuses marketPricing.searchCommodity)

    private var searchField: some View {
        HStack(spacing: 10) {
            // Drawn magnifier — no SF Symbol on this bespoke surface.
            MagnifierGlyph()
                .stroke(palette.textTertiary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .frame(width: 15, height: 15)
            TextField(
                "",
                text: $searchText,
                prompt: Text("Search any ticker, stock or commodity…")
                    .foregroundColor(palette.textTertiary)
            )
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(palette.textPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .submitLabel(.search)
            .onSubmit {
                let q = searchText.trimmingCharacters(in: .whitespaces)
                if q.count >= 2 { Task { await runSearch(q) } }
            }
            .onChange(of: searchText) { _, newValue in
                debounceTask?.cancel()
                let q = newValue.trimmingCharacters(in: .whitespaces)
                if q.count < 2 {
                    searchResults = []; searchError = nil; searchLoading = false
                    return
                }
                searchLoading = true
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if Task.isCancelled { return }
                    await runSearch(q)
                }
            }
            if searchLoading {
                ProgressView().tint(LinearGradient.diagonal).scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        if let err = searchError {
            LifecycleCard(accentWarning: true) {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if !searchResults.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("SEARCH RESULTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                ForEach(searchResults) { row in
                    feedRow(
                        symbol: row.symbol,
                        name: row.name,
                        category: row.category,
                        selected: watchlist.selectedSymbols.contains(row.symbol)
                    )
                }
            }
        } else if !searchLoading {
            LifecycleCard {
                Text("No matches for “\(searchText)”")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func runSearch(_ q: String) async {
        await MainActor.run { searchLoading = true; searchError = nil }
        do {
            let r: SearchResp = try await EusoTripAPI.shared.query(
                "marketPricing.searchCommodity",
                input: SearchInput(query: q)
            )
            await MainActor.run {
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
}

/// A drawn magnifying glass (circle + handle) — the editor's search glyph,
/// never the `magnifyingglass` SF Symbol.
private struct MagnifierGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let d = min(r.width, r.height) * 0.68
        let lens = CGRect(x: r.minX, y: r.minY, width: d, height: d)
        p.addEllipse(in: lens)
        p.move(to: CGPoint(x: lens.maxX - d * 0.16, y: lens.maxY - d * 0.16))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
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
        .environmentObject(MarketWatchlistStore())
        .preferredColorScheme(.dark)
}
#Preview("233 · Market Intelligence · Afternoon") {
    MarketIntelligenceScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .environmentObject(MarketWatchlistStore())
        .preferredColorScheme(.light)
}
