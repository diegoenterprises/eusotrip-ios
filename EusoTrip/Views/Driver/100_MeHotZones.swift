//
//  100_MeHotZones.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · Hot Zones)
//
//  Screen 100 · Me · Hot Zones — dedicated market-intelligence
//  cockpit. Pulls the same `hotZones.getRateFeed` feed the Driver
//  Home widget uses, but with room for a richer layout: market-
//  pulse hero, equipment filter, full critical-zone cards with
//  the server's "why" reasons, compact list of the long tail, and
//  cold-zone callouts so drivers know which corridors to AVOID
//  when repositioning between loads.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Zones + pulse + cold-zones all ship from `hotZones.
//      getRateFeed` — MCP-verified at
//      `frontend/server/routers/hotZones.ts`. Server computes
//      load-to-truck ratios, rate change %, demand tier
//      (CRITICAL / HIGH / ELEVATED), and attaches FMCSA +
//      weather + fuel enrichment per zone.
//    • Equipment filter round-trips to the server so the feed
//      narrows to zones whose `topEquipment` carries the
//      requested code (REEFER / FLATBED / etc.).
//    • Reuses the existing `HotZonesStore` + `HotZoneDemand`
//      helpers (owned by the home-screen widget) so the widget
//      and this deep-dive always agree on the same numbers.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on critical / rising zones.
//         Brand.warning on high, Brand.magenta on wildfire /
//         weather risk. Cold zones rendered as neutral strokes.
//    §4   Tokenized Space/Radius/EType throughout.
//

import SwiftUI

// MARK: - Screen root

struct MeHotZones: View {
    @Environment(\.palette) var palette
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store = HotZonesStore()

    private let equipmentOptions: [(label: String, raw: String?)] = [
        ("All", nil),
        ("Dry Van", "DRY_VAN"),
        ("Reefer", "REEFER"),
        ("Flatbed", "FLATBED"),
        ("Tanker", "TANKER"),
        ("Step Deck", "STEP_DECK"),
        ("Container", "CONTAINER"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                marketPulse
                heatMap
                equipmentPicker
                criticalSection
                allZonesSection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.bootstrap() }
        .refreshable { await store.refresh() }
    }

    // MARK: Heat map

    /// Full-bleed heatmap deep-dive — same `HotZonesHeatmapWebView`
    /// powering the Driver Home widget, sized for the standalone
    /// screen's vertical budget so the gradient density actually
    /// reads from across the cab.
    private var heatMap: some View {
        ZStack(alignment: .topLeading) {
            HotZonesHeatmapWebView(
                points: HotZonesHeatMapView.points(from: store.zones),
                colorScheme: colorScheme
            )
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )

            HStack(spacing: 4) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .bold))
                Text("HEATMAP")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(LinearGradient.diagonal)
            )
            .padding(Space.s3)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Hot Zones")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Where loads pay · where to reposition")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Market pulse

    @ViewBuilder
    private var marketPulse: some View {
        if let p = store.marketPulse {
            VStack(spacing: Space.s2) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NATIONAL AVG")
                            .font(EType.micro)
                            .tracking(1.3)
                            .foregroundStyle(palette.textTertiary)
                        Text(String(format: "$%.2f/mi", p.avgRate ?? 0))
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                    }
                    Spacer()
                    trendChip(from: p.avgRate ?? 0)
                }
                HStack(spacing: Space.s2) {
                    pulseTile(label: "LOADS",   value: compactNumber(Double(p.totalLoads ?? 0)))
                    pulseTile(label: "TRUCKS",  value: compactNumber(Double(p.totalTrucks ?? 0)))
                    pulseTile(label: "RATIO",   value: String(format: "%.2f", p.avgRatio ?? 0))
                    pulseTile(label: "CRIT",    value: "\(p.criticalZones ?? 0)")
                }
                if (p.avgFuelPrice ?? 0) > 0 || (p.activeWeatherAlerts ?? 0) > 0 {
                    HStack(spacing: Space.s3) {
                        if let fuel = p.avgFuelPrice, fuel > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "fuelpump")
                                Text(String(format: "$%.2f/gal avg", fuel))
                                    .monospacedDigit()
                            }
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                        }
                        if let alerts = p.activeWeatherAlerts, alerts > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "cloud.bolt")
                                Text("\(alerts) weather alert\(alerts == 1 ? "" : "s")")
                            }
                            .font(EType.caption)
                            .foregroundStyle(Brand.warning)
                        }
                        Spacer()
                    }
                }
            }
            .padding(Space.s4)
            .eusoCard(radius: Radius.lg)
        } else if store.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s4)
        } else if let err = store.errorMessage {
            Text(err)
                .font(EType.caption)
                .foregroundStyle(Brand.warning)
                .padding(Space.s3)
                .frame(maxWidth: .infinity)
                .eusoCard(radius: Radius.md)
        }
    }

    private func pulseTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s2)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.45))
        )
    }

    private func trendChip(from avgRate: Double) -> some View {
        let (label, tint): (String, Color) = {
            if avgRate >= 3.0 { return ("BULLISH", .green) }
            if avgRate >= 2.5 { return ("NEUTRAL", palette.textSecondary) }
            return ("BEARISH", Brand.magenta)
        }()
        return Text(label)
            .font(EType.micro)
            .tracking(1.3)
            .foregroundStyle(tint)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(tint, lineWidth: 1))
    }

    // MARK: Equipment picker

    private var equipmentPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(equipmentOptions, id: \.label) { opt in
                    let selected = store.equipmentFilter == opt.raw
                    Button {
                        store.equipmentFilter = opt.raw
                        Task { await store.refresh() }
                    } label: {
                        Text(opt.label)
                            .font(EType.caption)
                            .foregroundStyle(selected ? Color.white : palette.textSecondary)
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(selected
                                               ? AnyShapeStyle(LinearGradient.diagonal)
                                               : AnyShapeStyle(palette.tintNeutral.opacity(0.55)))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Critical zones

    private var criticalSection: some View {
        let critical = store.zones.filter { HotZoneDemand($0.demandLevel) == .critical }.prefix(5)
        return VStack(alignment: .leading, spacing: Space.s2) {
            if !critical.isEmpty {
                Text("CRITICAL ZONES · REPOSITION NOW")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(Brand.magenta)
                ForEach(Array(critical)) { zone in
                    criticalCard(zone)
                }
            } else if store.zones.isEmpty && !store.isLoading && store.errorMessage == nil {
                EusoEmptyState(
                    systemImage: "flame",
                    title: "Market is calm",
                    subtitle: "No critical zones right now — load-to-truck ratios are in balance nationally."
                )
            }
        }
    }

    private func criticalCard(_ z: HotZoneEntry) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(z.zoneName.uppercased())
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(z.state)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                demandChip(z.demandLevel)
            }
            HStack(spacing: Space.s3) {
                rateBlock(rate: z.liveRate, change: z.rateChangePercent)
                Spacer()
                ratioBlock(ratio: z.liveRatio, surge: z.liveSurge)
            }
            if let reasons = z.reasons, !reasons.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(reasons.prefix(3), id: \.self) { reason in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                                .foregroundStyle(LinearGradient.diagonal)
                            Text(reason)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                if !z.topEquipment.isEmpty {
                    equipmentPill(z.topEquipment.prefix(3).joined(separator: ", "))
                }
                if z.femaDisasterActive == true {
                    riskPill(icon: "shield.lefthalf.filled", text: "FEMA", tint: Brand.magenta)
                }
                if (z.activeWildfires ?? 0) > 0 {
                    riskPill(icon: "flame.fill", text: "WILDFIRE", tint: Brand.warning)
                }
                if let forecast = z.nextWeekForecast, !forecast.isEmpty {
                    Spacer()
                    Text(forecast.uppercased())
                        .font(EType.micro)
                        .tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Brand.magenta.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private func rateBlock(rate: Double, change: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LIVE RATE")
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(palette.textTertiary)
            Text(String(format: "$%.2f/mi", rate))
                .font(EType.bodyStrong)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            if let chg = change, chg != 0 {
                HStack(spacing: 2) {
                    Image(systemName: chg > 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(String(format: "%+.1f%%", chg))
                        .monospacedDigit()
                }
                .font(EType.micro)
                .foregroundStyle(chg > 0 ? .green : Brand.magenta)
            }
        }
    }

    private func ratioBlock(ratio: Double, surge: Double) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("L:T")
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(palette.textTertiary)
            Text(String(format: "%.2f", ratio))
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            if surge > 1 {
                Text(String(format: "%.1f× SURGE", surge))
                    .font(EType.micro)
                    .tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func demandChip(_ raw: String) -> some View {
        let (label, tint, filled): (String, Color, Bool) = {
            switch HotZoneDemand(raw) {
            case .critical: return ("CRITICAL", Brand.magenta, true)
            case .high:     return ("HIGH",     Brand.warning, false)
            case .elevated: return ("ELEVATED", palette.textSecondary, false)
            case .unknown:  return (raw.uppercased(), palette.textTertiary, false)
            }
        }()
        Text(label)
            .font(EType.micro)
            .tracking(1.2)
            .foregroundStyle(filled ? .white : tint)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .background(
                Group {
                    if filled {
                        Capsule().fill(LinearGradient.diagonal)
                    } else {
                        Capsule().stroke(tint, lineWidth: 1)
                    }
                }
            )
    }

    private func equipmentPill(_ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "truck.box")
                .font(.system(size: 10, weight: .semibold))
            Text(text)
        }
        .font(EType.micro)
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(palette.tintNeutral.opacity(0.55))
        )
    }

    private func riskPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
        }
        .font(EType.micro)
        .tracking(1.1)
        .foregroundStyle(tint)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 3)
        .overlay(Capsule().stroke(tint, lineWidth: 1))
    }

    // MARK: All zones

    private var allZonesSection: some View {
        let rest = store.zones.filter { HotZoneDemand($0.demandLevel) != .critical }
        return VStack(alignment: .leading, spacing: Space.s2) {
            if !rest.isEmpty {
                Text("OTHER ACTIVE")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                ForEach(rest) { zone in
                    compactRow(zone)
                }
            }
        }
    }

    private func compactRow(_ z: HotZoneEntry) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(z.zoneName)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                HStack(spacing: 4) {
                    Text(z.state)
                    Text("·")
                    Text(String(format: "L:T %.2f", z.liveRatio))
                        .monospacedDigit()
                    if z.liveSurge > 1 {
                        Text("·")
                        Text(String(format: "%.1f×", z.liveSurge))
                            .monospacedDigit()
                    }
                }
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "$%.2f", z.liveRate))
                    .font(EType.bodyStrong)
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                demandChip(z.demandLevel)
            }
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Footer

    private var footer: some View {
        Text("Data refreshes from the market-intel feed every 5 minutes. L:T = load-to-truck ratio. Ratios > 2.8 signal critical imbalance — reposition carefully.")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.s2)
    }

    // MARK: Helpers

    private func compactNumber(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 10_000   { return String(format: "%.0fK", value / 1_000) }
        if value >= 1_000    { return String(format: "%.1fK", value / 1_000) }
        return String(format: "%.0f", value)
    }
}

// MARK: - Screen wrapper

struct MeHotZonesScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeHotZones()
        } nav: {
            BottomNav(
                leading: driverNavLeading_100(),
                trailing: driverNavTrailing_100(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_100() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_100() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill",      isCurrent: true)]
}

// MARK: - Previews

#Preview("100 · Hot Zones · Night") {
    MeHotZonesScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("100 · Hot Zones · Afternoon") {
    MeHotZonesScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
