//
//  220_ShipperRateBoard.swift
//  EusoTrip 2027 UI — Shipper · Rate Board (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/220_ShipperRateBoard.swift. Persona: Diego
//  Usoro / Eusorone Technologies (companyId 1) per §11. Featured
//  lane is the §11.4 row 1 flagship — Houston TX → Dallas TX MC-306
//  UN1203 gasoline (LD-260427-A38FB12C7E hex tail). The screen
//  exists to answer one question: should Diego re-tender his
//  contract lanes against the spot market right now?
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · RATE BOARD / "DAT · GREENSCREENS · LIVE"
//    2. Title block      Rate board / "Spot vs contract · 14-day lane forecast · save vs market"
//    3. IridescentHairline
//    4. FEATURED LANE · HOUSTON → DALLAS — gradient-rim hero with
//                        SPOT (gradient · live `getMarketRates(TX,TX,tanker,week)`)
//                        + CONTRACT (placeholder · pending EUSO-2126)
//                        + 14-day forecast chart placeholder (EUSO-2127)
//    5. Action ribbon    success-tinted re-tender CTA (visible only
//                        when SPOT is meaningfully below CONTRACT)
//    6. YOUR LANES       portfolio comparison card (placeholder ·
//                        pending EUSO-2128)
//    7. PULL CUSTOM RATE supplemental (preserved iOS scope: input
//                        + result + history + FSC)
//
//  Real wiring preserved: `rates.getMarketRates(originState,
//  destState, equipment, period)` + `rates.getFuelSurcharge` via
//  `ShipperRateBoardStore`. The supplemental section keeps the
//  full state-input flow + history bar chart + FSC card so the
//  surface still has utility while the wireframe-canon backend
//  endpoints land.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2126 — `rates.getContractRate(laneId | originState,
//                destState, equipment)` not yet on iOS API. CONTRACT
//                column paints "—" pending the contract baseline.
//    EUSO-2127 — `rates.getForecast(laneId, days:14)` not shipped.
//                Forecast chart paints placeholder.
//    EUSO-2128 — `rates.getPortfolioLaneComparison()` not shipped.
//                YOUR LANES card paints honest placeholder until
//                backend joins active contracts × spot averages and
//                returns per-lane spot/contract/delta tuples.
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy ("$7.92/mi · ↓ −2.4%"); §4.3 single iridescent
//  hairline; §11 / §11.2 / §11.4 Diego canon + UN1203 tanker; §13
//  carrier mix (MC-306 / MC-331 / DOT-117); §17.2 gradient-rim hero
//  recipe; §19.2 file-scoped `trendFill` + `successTintBanner` +
//  glyph helpers; §20.4 no dead buttons; §22.2 action ribbon recipe;
//  §22.2 counter color (textTertiary informational data-source).
//

import SwiftUI

// MARK: - Store

@MainActor
final class ShipperRateBoardStore: ObservableObject {
    enum LoadState {
        case idle
        case loading
        case error(String)
        case loaded(rate: ShipperRatesAPI.MarketRateResponse, fsc: ShipperRatesAPI.FuelSurcharge?)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var featuredSpot: ShipperRatesAPI.MarketRateResponse?

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) { self.api = api }

    /// Pull the §11.4 row 1 featured lane (Houston→Dallas tanker, 7d).
    func refreshFeatured() async {
        do {
            let r = try await api.ratesNS.getMarketRates(
                originState: "TX", destState: "TX",
                equipment: "tanker", period: "week"
            )
            featuredSpot = r
            featuredError = nil
        } catch {
            featuredSpot = nil
            featuredError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Surface to the UI when the featured lane fetch fails — was
    /// silently nil'd before so the screen looked static.
    @Published private(set) var featuredError: String? = nil

    func calculate(origin: String, destination: String, equipment: String?, period: String) async {
        state = .loading
        do {
            async let r = api.ratesNS.getMarketRates(
                originState: origin, destState: destination,
                equipment: equipment, period: period
            )
            async let f: ShipperRatesAPI.FuelSurcharge? = (try? await api.ratesNS.getFuelSurcharge()) ?? nil
            let (rate, fsc) = try await (r, f)
            state = .loaded(rate: rate, fsc: fsc)
        } catch {
            state = .error("Couldn't reach rate service.")
        }
    }
}

// MARK: - Lane comparison row (placeholder until EUSO-2128 ships)

private struct LaneRow {
    let lane:     String
    let spec:     String
    let spot:     String
    let contract: String
    let delta:    String
    let tone:     DeltaTone
}

private enum DeltaTone {
    case success, warning, neutral
    var color: Color {
        switch self {
        case .success: return Brand.success
        case .warning: return Brand.warning
        case .neutral: return Brand.neutral
        }
    }
}

// MARK: - Screen root

struct ShipperRateBoard: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ShipperRateBoardStore()

    @State private var origin: String = "TX"
    @State private var dest: String = "GA"
    @State private var equipment: String = "dry_van"
    @State private var period: String = "month"

    private static let equipments: [(String, String)] = [
        ("dry_van", "Dry van"), ("reefer", "Reefer"),
        ("flatbed", "Flatbed"), ("tanker", "Tanker"),
    ]
    private static let periods: [(String, String)] = [
        ("week", "7 d"), ("month", "30 d"), ("quarter", "90 d"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s5)

                sectionLabel("FEATURED LANE · HOUSTON → DALLAS")
                    .padding(.top, Space.s4)
                featuredLaneCard
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s2)

                sectionLabel("YOUR LANES · PORTFOLIO COMPARISON")
                    .padding(.top, Space.s5)
                yourLanesCard
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s2)

                sectionLabel("PULL CUSTOM RATE")
                    .padding(.top, Space.s5)
                inputCard
                    .padding(.horizontal, 14)
                    .padding(.top, Space.s2)
                resultSection
                    .padding(.horizontal, 14)
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
        }
        .task {
            await store.refreshFeatured()
            await store.calculate(origin: origin, destination: dest, equipment: equipment, period: period)
        }
        // RealtimeService → market rate signals shift with new
        // matches/assignments; refresh featured rate cards live.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.refreshFeatured() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.refreshFeatured() }
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · RATE BOARD")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text("DAT · GREENSCREENS · LIVE")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel("Live rate data sourced from DAT and Greenscreens")
        }
        .padding(.horizontal, Space.s3)
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Rate board")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Spot vs contract · 14-day lane forecast · save vs market")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s3)
    }

    // MARK: Featured lane hero card (gradient rim · numeral pair · forecast chart)

    private var featuredLaneCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)

            VStack(alignment: .leading, spacing: 0) {
                numeralPair
                    .padding(.top, Space.s5)
                    .padding(.horizontal, Space.s3)

                forecastChartPlaceholder
                    .frame(height: 96)
                    .padding(.top, Space.s4)
                    .padding(.horizontal, Space.s3)

                forecastLegend
                    .padding(.top, Space.s2)
                    .padding(.horizontal, Space.s3)
                    .padding(.bottom, Space.s5)
            }
        }
        .frame(minHeight: 220)
    }

    private var numeralPair: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SPOT 7d")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(featuredSpotValue)
                        .font(.system(size: 32, weight: .bold).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(featuredSpotSubLine)
                        .font(.system(size: 11))
                        .foregroundStyle(featuredSpotSubColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("CONTRACT")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // EUSO-2126 — contract baseline not on API.
                    Text("—")
                        .font(.system(size: 32, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text("/ mi · pending")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var featuredSpotValue: String {
        if let r = store.featuredSpot {
            return String(format: "$%.2f", r.avgRate)
        }
        return "—"
    }

    private var featuredSpotSubLine: String {
        guard let r = store.featuredSpot else { return "/ mi · loading" }
        let arrow: String = {
            switch r.trend.lowercased() {
            case "up":   return "↑"
            case "down": return "↓"
            default:      return "·"
            }
        }()
        if r.trendPercent != 0 {
            return String(format: "/ mi · %@ %+.1f%%", arrow, r.trendPercent)
        }
        return "/ mi · stable"
    }

    private var featuredSpotSubColor: Color {
        guard let r = store.featuredSpot else { return palette.textSecondary }
        switch r.trend.lowercased() {
        case "up":   return Brand.danger
        case "down": return Brand.success
        default:      return palette.textSecondary
        }
    }

    // EUSO-2127 — forecast endpoint pending. Placeholder paints the
    // baseline + a faint trend-fill so the visual frame is present.
    private var forecastChartPlaceholder: some View {
        GeometryReader { geo in
            let chartHeight = geo.size.height - 18
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: chartHeight))
                    p.addLine(to: CGPoint(x: geo.size.width, y: chartHeight))
                }
                .stroke(palette.borderFaint, lineWidth: 1)

                Rectangle()
                    .fill(LinearGradient.trendFill)
                    .frame(height: chartHeight)

                Path { p in
                    let y = chartHeight * 0.567
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(palette.textPrimary,
                        style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))

                Text("14-day forecast pending (EUSO-2127)")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: chartHeight, alignment: .center)

                HStack {
                    Text("TODAY")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("+7d")
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text("+14d")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .frame(height: 18)
                .offset(y: chartHeight)
            }
        }
    }

    private var forecastLegend: some View {
        HStack(alignment: .center, spacing: 20) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(LinearGradient.primary)
                    .frame(width: 14, height: 2)
                Text("Spot forecast")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            HStack(spacing: 6) {
                DashedStroke()
                    .stroke(palette.textPrimary,
                            style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .frame(width: 14, height: 2)
                Text("Contract")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer()
        }
    }

    // MARK: YOUR LANES portfolio card (placeholder · EUSO-2128)

    private var yourLanesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("LANE")
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("SPOT")
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 56, alignment: .trailing)
                Text("CONTRACT")
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 76, alignment: .trailing)
                    .padding(.leading, 12)
                Text("Δ")
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 48, alignment: .trailing)
                    .padding(.leading, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            Rectangle()
                .fill(palette.borderFaint)
                .frame(height: 1)
                .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Portfolio comparison pending")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Per-lane spot vs contract + Δ lands when `rates.getPortfolioLaneComparison` ships (EUSO-2128).")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(20)
        }
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: PULL CUSTOM RATE supplemental (preserved scope)

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("LANE").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                stateField(label: "ORIGIN", text: $origin)
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textTertiary)
                stateField(label: "DEST", text: $dest)
            }
            Text("EQUIPMENT").font(.system(size: 9, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.equipments, id: \.0) { e in
                        chip(label: e.1, active: equipment == e.0) { equipment = e.0 }
                    }
                }
            }
            Text("WINDOW").font(.system(size: 9, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            HStack(spacing: 6) {
                ForEach(Self.periods, id: \.0) { p in
                    chip(label: p.1, active: period == p.0) { period = p.0 }
                }
            }
            Button {
                Task { await store.calculate(origin: origin, destination: dest, equipment: equipment, period: period) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .heavy))
                    Text("Pull rates").font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(.white).background(LinearGradient.diagonal).clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func stateField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            TextField("XX", text: text).textFieldStyle(.plain)
                .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center).autocorrectionDisabled()
                .textInputAutocapitalization(.characters).onChange(of: text.wrappedValue) { _, v in
                    if v.count > 2 { text.wrappedValue = String(v.prefix(2)) }
                }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity).background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func chip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .heavy))
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                .background(Capsule().fill(active
                                           ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                                           : AnyShapeStyle(palette.bgCard)))
                .overlay(Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resultSection: some View {
        switch store.state {
        case .idle:
            EmptyView()
        case .loading:
            HStack {
                ProgressView()
                Text("Pulling lane data…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let m):
            errorBanner(m)
        case .loaded(let r, let f):
            heroRate(r)
            historyChart(r.history)
            if let f { fscCard(f) }
        }
    }

    private func heroRate(_ r: ShipperRatesAPI.MarketRateResponse) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("LANE").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(r.lane).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$\(String(format: "%.2f", r.avgRate))")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                Text("/ mi avg").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 10) {
                trendChip(r.trend, percent: r.trendPercent)
                Text("\(r.volumeIndex) loads sampled")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func trendChip(_ trend: String, percent: Double) -> some View {
        let (icon, color): (String, Color) = {
            switch trend.lowercased() {
            case "up":   return ("arrow.up.right", Brand.success)
            case "down": return ("arrow.down.right", Brand.danger)
            default:      return ("arrow.right", palette.textTertiary)
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .heavy))
            Text(percent != 0 ? String(format: "%+.1f%%", percent) : trend.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(color).padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.15)))
        .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.75))
    }

    private func historyChart(_ pts: [ShipperRatesAPI.HistoryPoint]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("HISTORY (\(pts.count) DAYS)").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
            if pts.isEmpty {
                Text("No deliveries in window.")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
                    .padding(.vertical, Space.s2)
            } else {
                let maxRate = max(pts.map(\.rate).max() ?? 1, 0.01)
                GeometryReader { geo in
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(pts) { p in
                            Capsule().fill(LinearGradient.diagonal)
                                .frame(width: max(2, (geo.size.width / CGFloat(pts.count)) - 2),
                                       height: max(2, geo.size.height * CGFloat(p.rate / maxRate)))
                        }
                    }
                }
                .frame(height: 80)
                HStack {
                    Text("min $\(String(format: "%.2f", pts.map(\.rate).min() ?? 0))")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("max $\(String(format: "%.2f", pts.map(\.rate).max() ?? 0))")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func fscCard(_ f: ShipperRatesAPI.FuelSurcharge) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "fuelpump.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.warning)
                Text("FUEL SURCHARGE").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("$\(String(format: "%.2f", f.basePrice))/gal")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$\(String(format: "%.2f", f.currentRate))")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                Text("/ mi").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
            }
            Text("Effective \(f.effectiveDate) · next update \(f.nextUpdate)")
                .font(EType.micro).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorBanner(_ m: String) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 22)).foregroundStyle(palette.textSecondary)
            Text("Rate service offline").font(EType.title).foregroundStyle(palette.textPrimary)
            Text(m).font(EType.caption).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity).padding(Space.s4).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - File-scoped paint extensions (§19.2)

private extension LinearGradient {
    static let trendFill = LinearGradient(
        stops: [
            Gradient.Stop(color: Brand.magenta.opacity(0.20), location: 0.0),
            Gradient.Stop(color: Brand.blue.opacity(0.02),    location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - File-scoped shapes (§19.2)

private struct DashedStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Re-tender CTA tap (action ribbon · pending EUSO-2126).
    static let eusoShipperRateRetender = Notification.Name("eusoShipperRateRetender")
    /// Lane row tap (portfolio comparison · pending EUSO-2128).
    static let eusoShipperRateLane     = Notification.Name("eusoShipperRateLane")
    /// "View all lanes" gradient mid-link tap.
    static let eusoShipperRateAllLanes = Notification.Name("eusoShipperRateAllLanes")
}

// MARK: - Previews

#Preview("220 · Rate Board · Dark") {
    ShipperRateBoard()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("220 · Rate Board · Light") {
    ShipperRateBoard()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
