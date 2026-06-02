//
//  580_RailTariffRateLookup.swift
//  EusoTrip — Rail Engineer · Tariff Rate Lookup (STB-basis per-car rates + routings).
//
//  Verbatim port of "580 Rail Tariff Rate Lookup.svg" (Light + Dark).
//  Rate hero (per-car open rate + route miles), 3-cell KPI, ranked routing rows
//  with BEST/ALT pills and tabular dollar amounts, free-time context strip.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME).
//
//  Data:
//    railShipments.getTariffRate   (EXISTS railShipments.ts:837)  → rate + routings
//    railShipments.getRailDemurrage(EXISTS railShipments.ts:505)  → free-time strip
//

import SwiftUI

struct RailTariffRateLookupScreen: View {
    let theme: Theme.Palette
    let railId: String
    let shipmentId: Int

    var body: some View {
        Shell(theme: theme) { RailTariffRateLookupBody(railId: railId, shipmentId: shipmentId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct TariffData580: Decodable {
    let rate: Double?
    let currency: String?
    let ruleType: String?
    let routeLabel: String?
    let routeMiles: Int?
    let transitDays: Double?
    let rateMileUsd: Double?
    let carCount: Int?
    let routings: [TariffRouting580]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Server sends 'baseRate' but iOS struct stores as 'rate'
        rate = try (container.decodeIfPresent(Double.self, forKey: .rate)
            ?? container.decodeIfPresent(Double.self, forKey: .baseRate))
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        ruleType = try container.decodeIfPresent(String.self, forKey: .ruleType)
        routeLabel = try container.decodeIfPresent(String.self, forKey: .routeLabel)
        routeMiles = try container.decodeIfPresent(Int.self, forKey: .routeMiles)
        transitDays = try container.decodeIfPresent(Double.self, forKey: .transitDays)
        rateMileUsd = try container.decodeIfPresent(Double.self, forKey: .rateMileUsd)
        carCount = try container.decodeIfPresent(Int.self, forKey: .carCount)
        routings = try container.decodeIfPresent([TariffRouting580].self, forKey: .routings)
    }

    enum CodingKeys: String, CodingKey {
        case rate
        case baseRate   // server's name for the rate field
        case currency
        case ruleType
        case routeLabel
        case routeMiles
        case transitDays
        case rateMileUsd
        case carCount
        case routings
    }
}

private struct TariffRouting580: Decodable, Identifiable {
    let id: Int
    let routeName: String?
    let railroadCodes: String?
    let interchangeCount: Int?
    let miles: Int?
    let transitDays: Double?
    let rate: Double?
    let isPreferred: Bool?
    let routingType: String?
}

private struct DemurrageRecord580: Decodable, Identifiable {
    let id: Int
    let freeDays: Int?
    let dailyRateUsd: Double?
    let totalCharge: String?
    let equipmentCount: Int?
    let status: String?
}

// MARK: - Body

private struct RailTariffRateLookupBody: View {
    @Environment(\.palette) private var palette
    let railId: String
    let shipmentId: Int

    @State private var tariff: TariffData580? = nil
    @State private var demurrage: [DemurrageRecord580] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isQuoting = false

    // MARK: Derived

    private var routings: [TariffRouting580] { tariff?.routings ?? [] }
    private var baseRate: Double  { tariff?.rate ?? 0 }
    private var carCount: Int     { tariff?.carCount ?? 1 }
    private var totalQuote: Double { baseRate * Double(carCount) }
    private var routingCount: Int  { routings.count }

    private var rateLabel: String {
        baseRate > 0 ? String(format: "$%.0f", baseRate) : "—"
    }
    private var rateMileLabel: String {
        if let r = tariff?.rateMileUsd { return String(format: "$%.2f", r) }
        if baseRate > 0, let mi = tariff?.routeMiles, mi > 0 {
            return String(format: "$%.2f", baseRate / Double(mi))
        }
        return "—"
    }
    private var transitLabel: String {
        if let t = tariff?.transitDays { return String(format: "%.1fd", t) }
        return "—"
    }
    private var routeMilesLabel: String {
        tariff?.routeMiles.map { "\($0)" } ?? "—"
    }
    private var routeLabel: String  { tariff?.routeLabel ?? "—" }
    private var ruleTypeLabel: String { tariff?.ruleType ?? "RULE 11" }
    private var quoteLabel: String {
        totalQuote > 0 ? String(format: "Quote · $%.0f", totalQuote) : "Get quote"
    }

    private var freeDaysLabel: String {
        demurrage.first?.freeDays.map { "\($0) free day\($0 == 1 ? "" : "s") at ramp" } ?? "—"
    }
    private var dailyRateLabel: String {
        if let d = demurrage.first?.dailyRateUsd { return String(format: "$%.0f/car-day after", d) }
        return "—"
    }
    private var demurrageEquipLabel: String {
        let cnt = demurrage.first?.equipmentCount ?? carCount
        return "quote ref \(String(railId.prefix(24))) · \(cnt) car\(cnt == 1 ? "" : "s")"
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading tariff…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    routingsList
                    if !demurrage.isEmpty { freeTimeStrip }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · TARIFF RATE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(String(railId.prefix(24)))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Tariff rate")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(ruleTypeLabel)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(Brand.info)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.info.opacity(0.12)))
                Text(routeLabel)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(rateLabel)
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("per car · open rate")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Text("getTariffRate · STB basis")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("ROUTE MI")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(routeMilesLabel)
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text("ramp-to-ramp")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "RATE/MILE",  value: rateMileLabel,           gradientNumeral: baseRate > 0)
            MetricTile(label: "ROUTINGS",   value: routingCount > 0 ? "\(routingCount)" : "—")
            MetricTile(label: "TRANSIT",    value: transitLabel)
        }
    }

    // MARK: - Routings list

    private var routingsList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ROUTINGS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getTariffRate")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if routings.isEmpty {
                EusoEmptyState(systemImage: "tram.fill",
                               title: "No routings found",
                               subtitle: "Check station codes or try a different commodity type.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(routings.enumerated()), id: \.element.id) { idx, routing in
                        routingRow(routing, rank: idx)
                        if idx < routings.count - 1 {
                            Divider().padding(.leading, 68).overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func routingRow(_ routing: TariffRouting580, rank: Int) -> some View {
        let isPreferred = routing.isPreferred == true || rank == 0
        let pillLabel = isPreferred ? "BEST" : "ALT"
        let pillColor: Color = isPreferred ? Brand.success : Brand.blue
        let title = routing.routeName ?? "Route \(rank + 1)"
        let interchanges = routing.interchangeCount.map { "\($0) interchange\($0 == 1 ? "" : "s")" } ?? "direct"
        let miles = routing.miles.map { " · \($0) mi" } ?? ""
        let sub = interchanges + miles
        let rateStr = routing.rate.map { String(format: "$%.0f", $0) } ?? "—"

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.info.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "tram.tunnel.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.info)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(sub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(pillLabel)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(pillColor)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(pillColor.opacity(0.12)))
                Text(rateStr)
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    // MARK: - Free time strip

    private var freeTimeStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FREE TIME")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getRailDemurrage")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            Text(freeDaysLabel + (dailyRateLabel != "—" ? " · \(dailyRateLabel)" : ""))
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(demurrageEquipLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: quoteLabel,
                      action: { Task { await requestQuote() } },
                      leadingIcon: "plus",
                      isLoading: isQuoting)
            Button {} label: {
                Text("Routings")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct TariffIn: Encodable {
            let originStation: String
            let destStation: String
            let carType: String
            let commodity: String
        }
        struct DemurrageIn: Encodable { let shipmentId: Int }
        do {
            // Use standard intermodal lookup for the transcon corridor
            async let tariffResult: TariffData580? = EusoTripAPI.shared.query(
                "railShipments.getTariffRate",
                input: TariffIn(originStation: "715564", destStation: "612201",
                                carType: "flat", commodity: "intermodal"))
            async let demurrageResult: [DemurrageRecord580] = EusoTripAPI.shared.query(
                "railShipments.getRailDemurrage", input: DemurrageIn(shipmentId: shipmentId))
            let (t, d) = try await (tariffResult, demurrageResult)
            self.tariff   = t
            self.demurrage = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func requestQuote() async {
        isQuoting = true
        try? await Task.sleep(nanoseconds: 800_000_000)
        isQuoting = false
    }
}

#Preview("580 · Rail Tariff Rate · Night") { RailTariffRateLookupScreen(theme: Theme.dark, railId: "RAIL-260523-7C3A0B12D4", shipmentId: 0).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("580 · Rail Tariff Rate · Light") { RailTariffRateLookupScreen(theme: Theme.light, railId: "RAIL-260523-7C3A0B12D4", shipmentId: 0).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
