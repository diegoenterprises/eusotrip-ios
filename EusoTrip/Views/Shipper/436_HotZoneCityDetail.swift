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

private struct HotZoneDetail: Decodable, Hashable {
    let city: String
    let state: String?
    let demandIndex: Double?      // -100 to +100
    let avgRate: Double?
    let avgRateDelta30d: Double?
    let topCommodities: [String]?
    let topLanes: [String]?
    let carriersAvailable: Int?
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
                else if let d = detail { demandCard(d); ratesCard(d); commodityCard(d); lanesCard(d) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
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
            LifecycleSection(label: "DEMAND INDEX", icon: "chart.line.uptrend.xyaxis")
            Text(d.demandIndex.map { String(format: "%+.0f", $0) } ?? "—")
                .font(.system(size: 36, weight: .heavy)).foregroundStyle(palette.textPrimary).monospacedDigit()
            LifecycleRow(label: "Carriers available", value: d.carriersAvailable.map { "\($0)" } ?? "—")
        }
    }

    private func ratesCard(_ d: HotZoneDetail) -> some View {
        LifecycleCard {
            LifecycleSection(label: "RATES", icon: "dollarsign.circle")
            LifecycleRow(label: "Avg rate", value: usd(d.avgRate))
            LifecycleRow(label: "30-day Δ", value: d.avgRateDelta30d.map { String(format: "%+.0f", $0) } ?? "—")
        }
    }

    @ViewBuilder
    private func commodityCard(_ d: HotZoneDetail) -> some View {
        if let cs = d.topCommodities, !cs.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "TOP COMMODITIES", icon: "shippingbox")
                Text(cs.joined(separator: " · ")).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func lanesCard(_ d: HotZoneDetail) -> some View {
        if let ls = d.topLanes, !ls.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "TOP LANES", icon: "map")
                ForEach(ls, id: \.self) { lane in
                    HStack {
                        Image(systemName: "arrow.right").foregroundStyle(LinearGradient.diagonal)
                        Text(lane).font(EType.body).foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let city: String }
        do {
            let d: HotZoneDetail = try await EusoTripAPI.shared.api.query("hotZones.getCity", input: In(city: city))
            detail = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("436 · Hot zone · Night") { HotZoneCityDetailScreen(theme: Theme.dark, city: "Houston").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("436 · Hot zone · Afternoon") { HotZoneCityDetailScreen(theme: Theme.light, city: "Houston").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
