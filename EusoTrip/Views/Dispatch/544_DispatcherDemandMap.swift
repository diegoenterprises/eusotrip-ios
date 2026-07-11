//
//  544_DispatcherDemandMap.swift
//  EusoTrip — Dispatcher · Demand Map.
//
//  SwiftUI port of:
//    `04 Dispatcher/Dark-SVG/544 Dispatcher Demand Map.svg`
//
//  MAP / DEMAND archetype — a live load-to-truck demand FIELD (regions ranked
//  and heat-washed by intensity) over a center-zero inbound↔outbound balance
//  ledger + an ESANG reposition card. Shows the dispatcher where freight is hot
//  and where their own capacity is stranded, so trucks roll toward demand
//  before rates soften.
//
//  Honest wiring — 0 stubs, fully dynamic (capacityPlanning confirmed on disk
//  2026-07-11):
//    • READ  capacityPlanning.getCapacityHeatmap (…:1332) → regions[]{state,
//            outboundLoads,inboundLoads,availableTrucks,intensity,balance} +
//            imbalances[] → the heat field + the balance ledger.
//    • READ  capacityPlanning.getDemandForecast  (…:187)  → "Forecast" CTA.
//    • "Reposition" routes THROUGH esang.chat — dispatch.assignDriver (…:1220)
//            is the real empty-move gate but it needs a concrete load + driver +
//            the FMCSA-OOS / CDL gates, so a one-tap reposition from a roll-up
//            is handed to ESANG rather than fabricated.
//
//  HONEST NOTE ON THE MAP: getCapacityHeatmap returns STATE-AGGREGATED demand
//  counts, not positioned points — there are no lat/long to feed the house
//  HereMapView, and fabricating truck pins on a drawn US map would be invented
//  data. So the hero is an honest demand FIELD (real per-state load-to-truck
//  ratios, heat-washed by the endpoint's own intensity), not a fake pin map.
//
//  Persona: Aurora Freight Lines · Renée Marquette (RM). transportMode=truck;
//  currency USD. NAV: HOME · BOARD(current) · [orb] · COMMS · ME. Powered by
//  ESANG AI™. Author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Decoders

private struct Heatmap544: Decodable {
    let regions: [Region544]
    let imbalances: [Imbalance544]
}
private struct Region544: Decodable, Identifiable {
    let state: String
    let region: String?
    let outboundLoads: Int
    let inboundLoads: Int
    let availableTrucks: Int
    let intensity: String       // high | medium | low
    let balance: Int            // inbound - outbound
    var id: String { state }
    var demand: Int { outboundLoads + inboundLoads }
    var loadToTruck: Double { Double(demand) / Double(max(1, availableTrucks)) }
}
private struct Imbalance544: Decodable, Identifiable {
    let state: String
    let type: String            // surplus | deficit
    let magnitude: Int
    let recommendation: String?
    var id: String { state }
}

// MARK: - Screen

struct DispatcherDemandMapScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DispatcherDemandMapBody() } nav: { DispatchPortNav() }
    }
}

// MARK: - Body

private struct DispatcherDemandMapBody: View {
    @Environment(\.palette) private var palette

    @State private var data: Heatmap544?
    @State private var loading = true
    @State private var loadError: String?
    @State private var working = false
    @State private var actionNote: String?

    private var regions: [Region544] {
        (data?.regions ?? []).sorted { $0.demand > $1.demand }
    }
    private var hottest: Region544? { regions.first }
    // signed-balance ledger rows, biggest imbalance first
    private var balanceRows: [Region544] {
        (data?.regions ?? []).filter { $0.balance != 0 }.sorted { abs($0.balance) > abs($1.balance) }
    }
    private var deficit: Region544? { balanceRows.filter { $0.balance < 0 }.first }
    private var surplus: Region544? { balanceRows.filter { $0.balance > 0 }.first }
    private var truckCount: Int { (data?.regions ?? []).reduce(0) { $0 + $1.availableTrucks } }

    private func heat(_ intensity: String) -> Color {
        switch intensity.lowercased() {
        case "high": return Brand.danger
        case "medium": return Brand.warning
        default: return Brand.info
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline().padding(.top, Space.s3)

            if loading {
                DispatchPortLoadingCard(text: "Loading demand field…").padding(.top, Space.s5)
            } else if let err = loadError {
                DispatchPortErrorCard(message: err) { Task { await load() } }.padding(.top, Space.s5)
            } else if regions.isEmpty {
                EusoEmptyState(systemImage: "map.fill",
                               title: "No demand signal yet",
                               subtitle: "Load and truck volume across your lanes builds this heat field over the last 30 days.")
                    .padding(.top, Space.s6)
            } else {
                fieldCard.padding(.top, Space.s5)
                balanceCard.padding(.top, Space.s5)
                esangCard.padding(.top, Space.s5)
                if let note = actionNote {
                    Text(note).font(EType.caption).foregroundStyle(palette.textSecondary).padding(.top, Space.s3)
                }
                ctaPair.padding(.top, Space.s5)
            }
        }
        .padding(.horizontal, 20).padding(.top, Space.s2)
        .task { await load() }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ DISPATCHER · DEMAND MAP")
                    .font(EType.micro).tracking(1.0).foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                HStack(spacing: 5) {
                    Circle().fill(Brand.success).frame(width: 6, height: 6)
                    Text("LIVE · 30-DAY").font(EType.micro).tracking(1.0).foregroundStyle(Brand.success)
                }
            }
            HStack(alignment: .center, spacing: Space.s3) {
                DispatchPortBackChevron()
                Text("Demand map").font(EType.h1).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            if let h = hottest {
                Text("\(h.state) hottest · \(String(format: "%.1f", h.loadToTruck)) loads/truck · \(regions.count) markets")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).padding(.leading, 40)
            }
        }
    }

    // MARK: Demand heat field (bespoke)

    private var fieldCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Brand.success).frame(width: 7, height: 7)
                    Text("\(truckCount) TRUCKS LIVE").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textPrimary)
                }
                Spacer()
                Text("LOAD-TO-TRUCK · 30-DAY").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
            }
            // heat cells — flow layout, sized/washed by demand & intensity
            HeatFlow544(regions: Array(regions.prefix(8)), heat: heat, palette: palette)

            HStack(spacing: Space.s4) {
                legendDot("HOT", Brand.danger)
                legendDot("WARM", Brand.warning)
                legendDot("SOFT", Brand.info)
                Spacer()
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private func legendDot(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 8.5, weight: .bold)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Balance ledger (center-zero)

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("INBOUND ↔ OUTBOUND BALANCE")
                    .font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("capacityPlanning").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            HStack {
                Text("← REPOSITION IN").font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.danger)
                Spacer()
                Text("SOURCE OUT →").font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.success)
            }

            if balanceRows.isEmpty {
                Text("Every market is in balance this period.").font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                let maxMag = balanceRows.map { abs($0.balance) }.max() ?? 1
                VStack(spacing: Space.s3) {
                    ForEach(balanceRows.prefix(6)) { r in
                        balanceRow(r, maxMag: maxMag)
                    }
                }
            }
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private func balanceRow(_ r: Region544, maxMag: Int) -> some View {
        let deficit = r.balance < 0
        let frac = CGFloat(abs(r.balance)) / CGFloat(max(1, maxMag))
        return HStack(spacing: Space.s2) {
            Text(r.state).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary).frame(width: 28, alignment: .leading)
            GeometryReader { geo in
                let half = geo.size.width / 2
                ZStack(alignment: deficit ? .trailing : .leading) {
                    Rectangle().fill(palette.borderFaint).frame(width: 1).frame(maxWidth: .infinity, alignment: .center)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(deficit ? Brand.danger : Brand.success)
                        .frame(width: max(4, half * frac), height: 13)
                        .offset(x: deficit ? -1 : 1)
                }
                .frame(maxWidth: .infinity, alignment: deficit ? .leading : .trailing)
            }
            .frame(height: 13)
            Text(r.balance > 0 ? "+\(r.balance)" : "\(r.balance)")
                .font(.system(size: 11, weight: .heavy).monospacedDigit())
                .foregroundStyle(deficit ? Brand.danger : Brand.success)
                .frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: ESANG card

    private var esangCard: some View {
        DispatchPortESangStrip(
            headline: (deficit != nil && surplus != nil)
                ? "ESANG says: reposition \(surplus!.state) → \(deficit!.state)"
                : "ESANG says: capacity balanced",
            detail: hottest.map { "\($0.state) \(String(format: "%.1f×", $0.loadToTruck)) · move empties toward demand" }
                ?? "no hot market this range"
        )
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button { DispatchNavDispatcher.handle("esang") } label: {
                Text(deficit.map { "Reposition to \($0.state)" } ?? "Reposition")
                    .font(EType.bodyStrong).foregroundStyle(palette.textOnGradient)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)

            Button { Task { await forecast() } } label: {
                HStack(spacing: Space.s2) {
                    if working { ProgressView().tint(palette.textPrimary) }
                    Text(working ? "…" : "Forecast").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                }
                .frame(width: 132).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(Color(hex: 0x232932)))
                .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }
            .buttonStyle(.plain).disabled(working)
        }
    }

    // MARK: Data + actions

    private func load() async {
        loading = true; loadError = nil
        do {
            data = try await EusoTripAPI.shared.queryNoInput("capacityPlanning.getCapacityHeatmap")
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func forecast() async {
        working = true; actionNote = nil
        struct Forecast: Decodable { let forecast: [ForecastRow]? }
        struct ForecastRow: Decodable {}
        do {
            let f: Forecast = try await EusoTripAPI.shared.queryNoInput("capacityPlanning.getDemandForecast")
            let n = f.forecast?.count ?? 0
            actionNote = n > 0 ? "Demand forecast ready · \(n) horizons." : "Demand forecast loaded."
        } catch {
            actionNote = "Couldn't load the demand forecast."
        }
        working = false
    }
}

// MARK: - Heat flow layout

private struct HeatFlow544: View {
    let regions: [Region544]
    let heat: (String) -> Color
    let palette: Theme.Palette

    private var maxDemand: Int { regions.map(\.demand).max() ?? 1 }

    var body: some View {
        // Two-row wrap of heat cells; cell size scales with demand share.
        FlowGrid544(items: regions) { r in
            let color = heat(r.intensity)
            let share = CGFloat(r.demand) / CGFloat(max(1, maxDemand))
            let w = 96 + share * 44
            HStack(spacing: Space.s2) {
                ZStack {
                    Circle().fill(color.opacity(0.9)).frame(width: 10, height: 10)
                    Circle().fill(color.opacity(0.25)).frame(width: 20, height: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.state).font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Text(String(format: "%.1f×", r.loadToTruck)).font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(color)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s3).frame(width: w, height: 44)
            .background(RoundedRectangle(cornerRadius: Radius.md).fill(color.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(color.opacity(0.35), lineWidth: 1))
        }
    }
}

// Simple wrapping flow container (no external deps).
private struct FlowGrid544<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        FlowLayout544(spacing: Space.s2) {
            ForEach(items) { cell($0) }
        }
    }
}

private struct FlowLayout544: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x - bounds.minX + sz.width > maxW { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("544 · Demand Map · Dark") {
    DispatcherDemandMapScreen(theme: Theme.dark).environment(\.palette, Theme.dark)
}
#Preview("544 · Demand Map · Light") {
    DispatcherDemandMapScreen(theme: Theme.light).environment(\.palette, Theme.light)
}
#endif
