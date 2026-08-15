//
//  436_HotZoneCityDetail.swift
//  EusoTrip — Shipper · Hot zone city detail (drills into 225 list).
//

import SwiftUI

struct HotZoneCityDetailScreen: View {
    let theme: Theme.Palette
    let city: String
    var body: some View {
        Shell(theme: theme) { HotZoneDetailBody(city: city) } nav: { shipperLifecycleNav() }
    }
}

private struct HotZoneDetail: Hashable {
    let city: String
    let state: String?
    let demandLevel: String?       // CRITICAL | HIGH | ELEVATED
    let demandRatio: Double?       // live load-to-truck multiplier (e.g. 1.8×)
    let avgRate: Double?           // $/mile
    let avgRateDelta30d: Double?   // percent
    let topEquipment: [String]?
    let whyHot: [String]?          // demand-driver reasons (NOT freight lanes)
    let trucksAvailable: Int?
    let rail: HotZoneRail?         // intermodal: real rail-yard anchors + gated demand
    let vessel: HotZoneVessel?     // intermodal: real port anchors + gated demand
}

/// One intermodal facility row (rail yard / port) for the detail section.
private struct IntermodalRow: Identifiable {
    let id = UUID()
    let name: String
    let sub: String
}

private struct HotZoneDetailBody: View {
    @Environment(\.palette) private var palette
    let city: String
    @State private var detail: HotZoneDetail? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading hot zone…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let d = detail { demandCard(d); ratesCard(d); commodityCard(d); intermodalCard(d); lanesCard(d) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .eusoRefreshTask { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · HOT ZONE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(detail.map { "\($0.city), \($0.state ?? "")" } ?? city).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func demandCard(_ d: HotZoneDetail) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "DEMAND", icon: "chart.line.uptrend.xyaxis")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(d.demandRatio.map { String(format: "%.1f×", $0) } ?? "—")
                    .font(.system(size: 36, weight: .heavy)).foregroundStyle(palette.textPrimary).monospacedDigit()
                if let level = d.demandLevel, !level.isEmpty {
                    Text(level.capitalized)
                        .font(.system(size: 11, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            LifecycleRow(label: "Trucks available", value: d.trucksAvailable.map { $0.formatted() } ?? "—")
        }
    }

    private func ratesCard(_ d: HotZoneDetail) -> some View {
        LifecycleCard {
            LifecycleSection(label: "RATES", icon: "dollarsign.circle")
            LifecycleRow(
                label: "Avg rate",
                value: (d.avgRate.map { $0 > 0 ? String(format: "$%.2f/mi", $0) : "—" }) ?? "—"
            )
            LifecycleRow(
                label: "30-day Δ",
                value: d.avgRateDelta30d.map { String(format: "%+.1f%%", $0) } ?? "—"
            )
        }
    }

    @ViewBuilder
    private func commodityCard(_ d: HotZoneDetail) -> some View {
        if let cs = d.topEquipment, !cs.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "TOP EQUIPMENT", icon: "shippingbox")
                Text(cs.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }.joined(separator: " · "))
                    .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func lanesCard(_ d: HotZoneDetail) -> some View {
        if let ls = d.whyHot, !ls.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "WHY IT'S HOT", icon: "flame")
                ForEach(ls, id: \.self) { reason in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkle").font(.system(size: 11, weight: .bold)).foregroundStyle(LinearGradient.diagonal)
                        Text(reason).font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    /// Intermodal section — real rail-yard + port facilities physically in
    /// the zone, with a demand tier ONLY when the server has real volume;
    /// otherwise an honest "demand building" note. Hidden entirely when the
    /// zone has no rail/port facilities.
    @ViewBuilder
    private func intermodalCard(_ d: HotZoneDetail) -> some View {
        let yardRows = (d.rail?.yards ?? []).map { y in
            IntermodalRow(name: y.name, sub: [y.city, y.intermodal == true ? "Intermodal ramp" : nil].compactMap { $0 }.joined(separator: " · "))
        }
        let portRows = (d.vessel?.ports ?? []).map { p in
            IntermodalRow(name: p.name, sub: [p.city, p.hasRail == true ? "On-dock rail" : nil, p.teu.map { "\($0.formatted()) TEU" }].compactMap { $0 }.joined(separator: " · "))
        }
        if !yardRows.isEmpty || !portRows.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "INTERMODAL", icon: "arrow.triangle.swap")
                if !yardRows.isEmpty {
                    intermodalGroup(title: "Rail", demand: d.rail?.demand, shipments: d.rail?.shipments, rows: yardRows)
                }
                if !portRows.isEmpty {
                    intermodalGroup(title: "Vessel", demand: d.vessel?.demand, shipments: d.vessel?.shipments, rows: portRows)
                }
                if d.rail?.shipments == nil && d.vessel?.shipments == nil {
                    Text("Live rail & vessel demand signals are still building — these are the facilities serving this zone.")
                        .font(EType.micro).foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func intermodalGroup(title: String, demand: String?, shipments: Int?, rows: [IntermodalRow]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title.uppercased()).font(EType.micro).tracking(0.8).foregroundStyle(palette.textSecondary)
                if let dem = demand {
                    Text(dem.capitalized).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text("Demand building").font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                if let s = shipments { Text("\(s) active").font(EType.micro).foregroundStyle(palette.textSecondary) }
            }
            ForEach(rows) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: title == "Rail" ? "tram.fill" : "ferry.fill")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary).frame(width: 14)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textPrimary)
                        if !item.sub.isEmpty { Text(item.sub).font(EType.micro).foregroundStyle(palette.textTertiary) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 2)
    }

    private func load() async {
        loading = true; loadError = nil
        defer { loading = false }
        // Founder bug 2026-05-07: `hotZones.getCity` doesn't exist
        // server-side. The canonical procedure is `getRateFeed`
        // which returns the full national feed; filter to the
        // requested city locally so the drill-down renders honestly
        // off the same authoritative source the heatmap uses.
        do {
            let feed = try await EusoTripAPI.shared.hotZones.getRateFeed()
            let needle = city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Match against zoneName + state. Zone names are typically
            // 'City Cluster · ST' (server-formatted); strip the cluster
            // suffix when comparing.
            let match = feed.zones.first { z in
                let nameOnly = z.zoneName
                    .components(separatedBy: " · ")
                    .first?
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased() ?? ""
                return nameOnly.contains(needle) || needle.contains(nameOnly)
            }
            guard let z = match else {
                loadError = "No live hot-zone data for \(city) right now. Check back when demand patterns update."
                return
            }
            // Map HotZoneEntry → local detail shape so the existing
            // SwiftUI cards render unchanged.
            detail = HotZoneDetail(
                city: z.zoneName.components(separatedBy: " · ").first ?? z.zoneName,
                state: z.state,
                demandLevel: z.demandLevel,
                demandRatio: z.liveRatio,
                avgRate: z.liveRate,
                avgRateDelta30d: z.rateChangePercent,
                topEquipment: z.topEquipment,
                whyHot: z.reasons,                  // demand-driver blurbs ("why this zone is hot")
                trucksAvailable: z.liveTrucks > 0 ? z.liveTrucks : nil,
                rail: z.rail,
                vessel: z.vessel
            )
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("436 · Hot zone · Night") { HotZoneCityDetailScreen(theme: Theme.dark, city: "Houston").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("436 · Hot zone · Afternoon") { HotZoneCityDetailScreen(theme: Theme.light, city: "Houston").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
