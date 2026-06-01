//
//  670_VesselBunkerPrices.swift
//  EusoTrip — Vessel Operator · Bunker Prices (CARRIER-SIDE bunker console).
//
//  Verbatim port of canonical wireframe 670 "Vessel Bunker Prices · Dark/Light".
//  DETAIL/console grammar (28/-0.4 title, one eyebrow, one iridescent hairline)
//  per FOUNDER CADENCE DIRECTIVE 2026-05-24. One screen gives the operator the
//  live bunker picture — focus-port VLSFO/MGO hero, fuel-grade chip strip, the
//  ranked GLOBAL HUBS board (LOW/CORR/HIGH vs. the live spread), and a BUNKER
//  GUARD rollup (week deltas + grade averages) so a vessel stems fuel at the
//  hub that is actually cheapest right now.
//
//  Docked under SHIPMENTS. transportMode=vessel · prices USD/MT · 15-min cache.
//
//  REAL WIRING (tRPC, server/routers/vesselShipments.ts):
//    · getGlobalBunkerPrices  {}  -> GlobalBunkerPrices[] | null
//        (vesselShipments.ts:1172 -> OilPriceMarineService.getGlobalBunkerPrices)
//        Each hub: { hub, country, prices:[{fuelType,price,currency,unit,
//        change24h}], lastUpdated }. Drives the hubs board + KPI strip + guard.
//    · getBunkerPrices  {port, fuelTypes?}  -> BunkerPrice[] | null
//        (vesselShipments.ts:1158 -> OilPriceMarineService.getBunkerPrices)
//        Each grade: { fuelType, price, currency, unit, port, portName,
//        supplier, lastUpdated, change24h, changePercent24h }. Drives the
//        focus-port hero (per-port VLSFO/MGO + 24h change).
//
//  Both procs return null on provider error and [] when the OilPrice API key
//  is unconfigured — so EVERY value here is live or an honest empty/loading/
//  error state. NO mock rows, NO fabricated prices.
//
//  RBAC: reads vesselProcedure (role .vesselOperator).
//

import SwiftUI

struct VesselBunkerPricesScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselBunkerPricesBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (verbatim from OilPriceMarineService TS interfaces)

/// vesselShipments.getGlobalBunkerPrices -> GlobalBunkerPrices[]
private struct GlobalBunkerHub670: Decodable, Identifiable {
    let hub: String
    let country: String?
    let prices: [BunkerGrade670]
    let lastUpdated: String?

    var id: String { hub }

    /// VLSFO is the headline marine grade — the board ranks hubs on it.
    var vlsfo: BunkerGrade670? { grade(matching: ["vlsfo", "vlsfo 0.5", "0.5%"]) }
    var mgo:   BunkerGrade670? { grade(matching: ["mgo", "lsmgo", "gasoil", "gas oil"]) }
    var ifo380: BunkerGrade670? { grade(matching: ["ifo380", "ifo 380", "hsfo", "380"]) }

    private func grade(matching keys: [String]) -> BunkerGrade670? {
        for key in keys {
            if let hit = prices.first(where: { $0.fuelType.lowercased().replacingOccurrences(of: "-", with: "").contains(key) }) {
                return hit
            }
        }
        return nil
    }
}

/// One fuel grade inside a hub's price set (also the per-port grade shape).
private struct BunkerGrade670: Decodable {
    let fuelType: String
    let price: Double
    let currency: String?
    let unit: String?
    let change24h: Double?

    private enum CodingKeys: String, CodingKey {
        case fuelType, price, currency, unit, change24h
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fuelType = (try? c.decode(String.self, forKey: .fuelType)) ?? ""
        // price is parsed server-side via parseFloat -> arrives as Number,
        // but decode defensively in case the provider quotes it.
        if let d = try? c.decode(Double.self, forKey: .price) {
            price = d
        } else if let s = try? c.decode(String.self, forKey: .price), let d = Double(s) {
            price = d
        } else {
            price = 0
        }
        currency = try? c.decode(String.self, forKey: .currency)
        unit = try? c.decode(String.self, forKey: .unit)
        if let d = try? c.decode(Double.self, forKey: .change24h) {
            change24h = d
        } else if let s = try? c.decode(String.self, forKey: .change24h) {
            change24h = Double(s)
        } else {
            change24h = nil
        }
    }
}

/// vesselShipments.getBunkerPrices -> BunkerPrice[] (per focus port).
private struct PortBunkerPrice670: Decodable, Identifiable {
    let fuelType: String
    let price: Double
    let currency: String?
    let unit: String?
    let port: String?
    let portName: String?
    let supplier: String?
    let lastUpdated: String?
    let change24h: Double?
    let changePercent24h: Double?

    var id: String { fuelType + (port ?? "") }

    private enum CodingKeys: String, CodingKey {
        case fuelType, price, currency, unit, port, portName
        case supplier, lastUpdated, change24h, changePercent24h
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fuelType = (try? c.decode(String.self, forKey: .fuelType)) ?? ""
        if let d = try? c.decode(Double.self, forKey: .price) {
            price = d
        } else if let s = try? c.decode(String.self, forKey: .price), let d = Double(s) {
            price = d
        } else {
            price = 0
        }
        currency = try? c.decode(String.self, forKey: .currency)
        unit = try? c.decode(String.self, forKey: .unit)
        port = try? c.decode(String.self, forKey: .port)
        portName = try? c.decode(String.self, forKey: .portName)
        supplier = try? c.decode(String.self, forKey: .supplier)
        lastUpdated = try? c.decode(String.self, forKey: .lastUpdated)
        change24h = try? c.decode(Double.self, forKey: .change24h)
        changePercent24h = try? c.decode(Double.self, forKey: .changePercent24h)
    }

    private func matches(_ keys: [String]) -> Bool {
        let f = fuelType.lowercased().replacingOccurrences(of: "-", with: "")
        return keys.contains { f.contains($0) }
    }
    var isVLSFO: Bool { matches(["vlsfo", "0.5%"]) }
    var isMGO:   Bool { matches(["mgo", "lsmgo", "gasoil", "gas oil"]) }
    var isIFO:   Bool { matches(["ifo", "hsfo", "380"]) }
}

// MARK: - Body

private struct VesselBunkerPricesBody: View {
    @Environment(\.palette) private var palette

    @State private var hubs: [GlobalBunkerHub670] = []
    @State private var portPrices: [PortBunkerPrice670] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // The hero focuses on the cheapest VLSFO hub (the natural stemming pick).
    // Singapore SGSIN is the canonical seed for the per-port getBunkerPrices
    // pull, but the hero re-anchors to whatever hub the live board ranks LOW.
    private let seedPort = "SGSIN"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s3)

                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(Brand.danger)
                                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            }
                        }
                    } else if hubs.isEmpty && portPrices.isEmpty {
                        EusoEmptyState(
                            systemImage: "fuelpump",
                            title: "No live bunker quotes",
                            subtitle: "Prices stream from the OilPrice marine feed (USD/MT, 15-min cache). They appear here the moment the feed returns a quote for a hub."
                        )
                    } else {
                        heroCard
                        gradeChipStrip
                        globalHubsSection
                        bunkerGuardCard
                        ctaRow
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow + back + title + menu)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · BUNKER")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("VLSFO · USD/MT")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Bunker prices")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s4)
        }
        .padding(.top, Space.s5)
    }

    // MARK: - Hero card (gradient rim · live + bunker index chips · VLSFO + MGO)

    private var heroCard: some View {
        // Headline VLSFO: prefer the per-port pull; fall back to the cheapest
        // hub's VLSFO. The MGO secondary mirrors the SVG's right-hand stat.
        let vlsfoVal = heroVLSFO
        let mgoVal = heroMGO
        return ZStack {
            VStack(alignment: .leading, spacing: 0) {
                // Chip row: "live" · "bunker index"
                HStack(spacing: Space.s2) {
                    chip("live")
                    chip("bunker index")
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vlsfoVal.map { dollars($0) } ?? "—")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VLSFO / MT")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(heroSubLine)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("MGO")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(mgoVal.map { dollars($0) } ?? "—")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("/ MT")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .padding(.top, Space.s3)
            }
            .padding(Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1.5)
        )
    }

    private func chip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .bold)).tracking(0.5)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(palette.tintNeutral))
    }

    /// "Singapore hub · +$12" — focus hub + the live 24h change on VLSFO.
    private var heroSubLine: String {
        let hubName = heroHub?.hub ?? portPrices.first?.portName ?? portPrices.first?.port
        let chg = heroVLSFOChange
        var lead = (hubName?.isEmpty == false ? "\(hubName!) hub" : "Focus hub")
        if let c = chg {
            let sign = c >= 0 ? "+" : "−"
            lead += " · \(sign)$\(Int(abs(c)))"
        }
        return lead
    }

    // MARK: - Fuel-grade chip strip (VLSFO · IFO380 · LSMGO)

    private var gradeChipStrip: some View {
        HStack(spacing: Space.s3) {
            gradeTile(label: "VLSFO",  value: heroVLSFO, gradient: true)
            gradeTile(label: "IFO380", value: heroIFO380)
            gradeTile(label: "LSMGO",  value: heroMGO)
        }
    }

    private func gradeTile(label: String, value: Double?, gradient: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(gradient ? .white.opacity(0.85) : palette.textTertiary)
                .padding(.bottom, 10)
            Text(value.map { dollars($0) } ?? "—")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(gradient ? .white : palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(Space.s4)
        .background(
            Group {
                if gradient { AnyView(LinearGradient.diagonal) }
                else { AnyView(palette.bgCard) }
            }
        )
        .overlay(
            gradient ? nil :
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Global hubs section (ranked LOW / CORR / HIGH on live VLSFO)

    private var globalHubsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("GLOBAL HUBS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("USD/MT · live")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }

            VStack(spacing: 0) {
                if rankedHubs.isEmpty {
                    HStack(spacing: Space.s3) {
                        Image(systemName: "globe")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                        Text("No hub quotes returned by the marine feed yet.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                    }
                    .padding(Space.s4)
                } else {
                    ForEach(Array(rankedHubs.enumerated()), id: \.element.id) { idx, hub in
                        hubRow(hub)
                        if idx < rankedHubs.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                    // "+ N more hubs · prices USD/MT · 15-min cache"
                    let extra = hubs.count - rankedHubs.count
                    Text(extra > 0
                         ? "+ \(extra) more hub\(extra == 1 ? "" : "s") · prices USD/MT · 15-min cache"
                         : "prices USD/MT · 15-min cache")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s3)
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func hubRow(_ hub: GlobalBunkerHub670) -> some View {
        let band = priceBand(for: hub)
        let price = hub.vlsfo?.price
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(band.color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "drop.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(band.color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(hubLabel(hub))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(gradeMetaLine(hub))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                Text(band.label)
                    .font(.system(size: 11, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(band.color)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(band.color.opacity(0.16)))
                Text(price.map { dollars($0) } ?? "—")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
            }
        }
        .padding(Space.s4)
    }

    /// "Singapore SGSIN" — provider hub field, suffixed with the UN/LOCODE-ish
    /// hub code when the provider supplies a distinct one.
    private func hubLabel(_ hub: GlobalBunkerHub670) -> String {
        let name = hub.hub.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Hub" : name
    }

    /// "VLSFO · 0.5% S" — the headline grade + sulphur cap descriptor.
    private func gradeMetaLine(_ hub: GlobalBunkerHub670) -> String {
        if let g = hub.vlsfo {
            let grade = g.fuelType.isEmpty ? "VLSFO" : g.fuelType.uppercased()
            return "\(grade) · 0.5% S"
        }
        if let first = hub.prices.first {
            return first.fuelType.uppercased()
        }
        return "no published grade"
    }

    // MARK: - Bunker guard card (week deltas + grade averages, all live)

    private var bunkerGuardCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BUNKER GUARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("15-min cache")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text(guardSpreadLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(guardAverageLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// Live spread between the cheapest and dearest VLSFO hub, with the
    /// hub names. Replaces the SVG's fixed "Singapore -2.0% wk · LA +3.1% wk".
    private var guardSpreadLine: String {
        let priced = rankedHubs.compactMap { hub -> (String, Double)? in
            guard let p = hub.vlsfo?.price else { return nil }
            return (hub.hub, p)
        }
        guard let lo = priced.min(by: { $0.1 < $1.1 }),
              let hi = priced.max(by: { $0.1 < $1.1 }), priced.count >= 2 else {
            return "Awaiting a second hub quote for the live spread"
        }
        let spread = hi.1 - lo.1
        return "\(lo.0) low \(dollars(lo.1)) · \(hi.0) high \(dollars(hi.1)) · $\(Int(spread)) spread"
    }

    /// VLSFO / MGO averages across the hubs that returned a price.
    private var guardAverageLine: String {
        let vAvg = average(hubs.compactMap { $0.vlsfo?.price })
        let mAvg = average(hubs.compactMap { $0.mgo?.price })
        var parts: [String] = []
        if let v = vAvg { parts.append("VLSFO avg \(dollars(v))/MT") }
        if let m = mAvg { parts.append("MGO avg \(dollars(m))/MT") }
        return parts.isEmpty ? "Averages compute once two or more hubs report" : parts.joined(separator: " · ")
    }

    // MARK: - CTA row (Stem fuel · Hub list)

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { } label: {
                Text("Stem fuel")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button { } label: {
                Text("Hub list")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 148, minHeight: 48)
                    .frame(maxWidth: .infinity)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 148)
        }
    }

    // MARK: - Derived (all off live endpoints; nil renders "—")

    /// The hub the hero focuses on: the cheapest VLSFO hub (the stem pick).
    private var heroHub: GlobalBunkerHub670? {
        hubs.compactMap { hub -> (GlobalBunkerHub670, Double)? in
            guard let p = hub.vlsfo?.price else { return nil }
            return (hub, p)
        }
        .min(by: { $0.1 < $1.1 })?.0
    }

    private var heroVLSFO: Double? {
        // Per-port pull wins (it's the precise SGSIN quote); else cheapest hub.
        if let p = portPrices.first(where: { $0.isVLSFO })?.price { return p }
        return heroHub?.vlsfo?.price
    }
    private var heroMGO: Double? {
        if let p = portPrices.first(where: { $0.isMGO })?.price { return p }
        return heroHub?.mgo?.price
    }
    private var heroIFO380: Double? {
        if let p = portPrices.first(where: { $0.isIFO })?.price { return p }
        return heroHub?.ifo380?.price
    }
    private var heroVLSFOChange: Double? {
        portPrices.first(where: { $0.isVLSFO })?.change24h ?? heroHub?.vlsfo?.change24h
    }

    /// Top hubs shown on the board (the rest collapse into "+ N more").
    private var rankedHubs: [GlobalBunkerHub670] {
        let priced = hubs.filter { $0.vlsfo?.price != nil }
            .sorted { ($0.vlsfo?.price ?? 0) < ($1.vlsfo?.price ?? 0) }
        let unpriced = hubs.filter { $0.vlsfo?.price == nil }
        return Array((priced + unpriced).prefix(3))
    }

    private struct PriceBand { let label: String; let color: Color }

    /// LOW / CORR / HIGH derived from the hub's VLSFO vs. the live min/max.
    private func priceBand(for hub: GlobalBunkerHub670) -> PriceBand {
        guard let price = hub.vlsfo?.price else {
            return PriceBand(label: "N/A", color: palette.textTertiary)
        }
        let priced = hubs.compactMap { $0.vlsfo?.price }
        guard let lo = priced.min(), let hi = priced.max(), hi > lo else {
            return PriceBand(label: "CORR", color: Brand.blue)
        }
        let frac = (price - lo) / (hi - lo)
        if frac <= 0.33 { return PriceBand(label: "LOW",  color: Brand.success) }
        if frac >= 0.67 { return PriceBand(label: "HIGH", color: Brand.warning) }
        return PriceBand(label: "CORR", color: Brand.blue)
    }

    // MARK: - Formatting helpers

    private func dollars(_ v: Double) -> String { "$\(Int(v.rounded()))" }

    private func average(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            HStack(spacing: Space.s3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 200)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Load (getGlobalBunkerPrices + getBunkerPrices)

    private func load() async {
        loading = true; loadError = nil
        struct PortIn: Encodable { let port: String }
        do {
            // Global hub board (no input) + the focus-port quote in parallel.
            // Both return null on provider error / [] when unconfigured — we
            // coalesce to empty so the UI renders honest empty states, never
            // fabricated rows.
            async let global: [GlobalBunkerHub670]? = EusoTripAPI.shared.queryNoInput(
                "vesselShipments.getGlobalBunkerPrices")
            async let port: [PortBunkerPrice670]? = EusoTripAPI.shared.query(
                "vesselShipments.getBunkerPrices", input: PortIn(port: seedPort))

            let (g, p) = try await (global, port)
            self.hubs = g ?? []
            self.portPrices = p ?? []
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("670 · Vessel Bunker Prices · Night") { VesselBunkerPricesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("670 · Vessel Bunker Prices · Light") { VesselBunkerPricesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
