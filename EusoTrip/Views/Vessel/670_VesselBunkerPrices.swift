//
//  670_VesselBunkerPrices.swift
//  EusoTrip — Vessel Operator · Bunker Prices.
//
//  Bespoke port of "670 Vessel Bunker Prices.svg" (Light + Dark) — a price-INTELLIGENCE archetype:
//  an N-point fuel-index trend chart (Path-drawn series + gridlines + end dot + legend) over a
//  grade-headline hero, a by-region price table, a fused ESang projection, and an alert/export CTA
//  pair. NOT a stat dashboard, NOT the ledger archetype of 674. Wrapped in the registered vessel
//  Shell + BottomNav (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME) — copied from sibling
//  757_VesselDetentionLetters. Role: VESSEL_OPERATOR (per canonical header).
//
//  Data / wiring (endpoints confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    • fuel.getTrends  (EXISTS · frontend/server/routers/fuel.ts:342 · input {period?,fuelType?,days?}? ·
//        returns [{date:String, price:Number}] from getPriceTrends → eia.history.slice(-days). This is
//        the REAL fuel-price index history that drives the trend chart's primary line + the headline
//        figure + week/week delta. Registered at routers.ts:1859 `fuel: fuelRouter`.)
//    • fuel.getPrices  (EXISTS · fuel.ts:237 · input {location?,radius} · returns
//        {national, regions:[{name,avgPrice,change}]} from getRegionalPrices → EIA regional breakdown.
//        Drives the honest by-region price table.)
//    NAMED GAPS (surfaced to the-oath — confirmed absent this fire, rendered honestly, never faked):
//    • vesselBunker.getPrices  → STUB (no router `vesselBunker` exists; the marine VLSFO/MGO-per-MT
//        spot feed is the proposed gap {ports[],grades[],weeks[]} mirroring fuel.getTrends' shape).
//    • CTA "Set BAF alert" → STUB · vesselBunker.setAlert {grade,port,threshold} (no backing mutation;
//        the generic client exposes no `mutate` — flagged STUB, re-runs load()).
//    • CTA "Export"        → STUB · reports.exportCostSheet (confirmed absent — no router/proc).
//
//  0 mock data on load · honest empty/error states — the chart + table render only from real
//  fuel.getTrends / fuel.getPrices state; if both return nothing the bespoke empty state shows.
//  Seed values live ONLY in #Preview (injected via VesselBunkerPricesBody(previewSeed:)). The two
//  write verbs are honestly flagged STUB rather than faked. Helper types are file-scoped + suffixed
//  670 to avoid cross-file private collisions.
//
import SwiftUI

struct VesselBunkerPricesScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselBunkerPricesBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Models (file-scoped, 670-suffixed)

private struct RegionPrice670: Identifiable {
    let id = UUID()
    let name: String
    let code: String
    let price: Double
    let delta: Double
}

/// Seed bundle — injected ONLY from #Preview so on-device load starts honest/empty.
private struct PreviewSeed670 {
    let series: [Double]
    let regions: [RegionPrice670]
    let esangLine: String
}

private struct VesselBunkerPricesBody: View {
    @Environment(\.palette) private var palette

    let previewSeed: PreviewSeed670?
    init(previewSeed: PreviewSeed670? = nil) { self.previewSeed = previewSeed }

    @State private var loading = true
    @State private var loadError: String? = nil

    // Real fuel-index history (drives the chart). Empty until fuel.getTrends returns.
    @State private var series: [Double] = []
    @State private var regions: [RegionPrice670] = []
    @State private var esangLine = ""
    @State private var unitLabel = "USD / GAL"      // fuel.getTrends is per-gallon (EIA) — labelled honestly.

    private var hasData: Bool { series.count >= 2 || !regions.isEmpty }
    private var latest: Double { series.last ?? 0 }
    private var weekDelta: Double {
        guard series.count >= 2 else { return 0 }
        let prev = series[series.count - 2]
        return prev > 0 ? (latest - prev) / prev * 100 : 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading fuel index…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if !hasData {
                    EusoEmptyState(systemImage: "fuelpump",
                                   title: "No bunker index to show",
                                   subtitle: "No marine bunker price history is available for this lane yet. Pull to refresh once the VLSFO or MGO feed posts data.")
                } else {
                    heroCard
                    if series.count >= 2 {
                        Text("FUEL INDEX TREND · EIA DIESEL · LAST \(series.count) PTS")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                        BunkerTrendChart670(series: series).frame(height: 172)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: Radius.lg)
                                .fill(palette.bgCard)
                                .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(palette.borderFaint, lineWidth: 1)))
                    }
                    if !regions.isEmpty {
                        Text("TODAY · BY REGION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                        regionsCard
                    }
                    if !esangLine.isEmpty { esangRow }
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · BUNKER PRICES").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(unitLabel).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Bunker prices").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                StatusPill(text: "FUEL · INDEX", kind: .info)
            }
        }
    }

    private var heroCard: some View {
        LifecycleCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EIA DIESEL · NATIONAL").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "$%.2f", latest)).font(.system(size: 34, weight: .bold)).foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                        Text("/gal").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textTertiary)
                    }
                    Text(String(format: "%+.1f%% pt/pt", weekDelta))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(weekDelta < 0 ? Brand.success : Brand.warning)
                        .monospacedDigit()
                }
                Spacer()
                if let hi = series.max(), let lo = series.min(), series.count >= 2 {
                    VStack(alignment: .trailing, spacing: 8) {
                        labelValue("HIGH", String(format: "$%.2f", hi), palette.textPrimary)
                        labelValue("LOW",  String(format: "$%.2f", lo), palette.textPrimary)
                        labelValue("RANGE", String(format: "$%.2f", hi - lo), Brand.success)
                    }
                }
            }
        }
    }

    private func labelValue(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(valueColor).monospacedDigit()
        }
    }

    private var regionsCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(regions.enumerated()), id: \.element.id) { idx, p in
                    let tone: Color = p.delta < 0 ? Brand.success : Brand.warning
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "flag")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.info)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Brand.info.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text(p.code).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "$%.2f", p.price)).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).monospacedDigit()
                            Text(String(format: "%+.1f%%", p.delta)).font(.system(size: 11)).foregroundStyle(tone).monospacedDigit()
                        }
                    }
                    .padding(.vertical, 12)
                    if idx < regions.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
        }
    }

    private var esangRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 14)).frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(esangLine).font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("ESang · fuel-index read on your bunker exposure").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg)
            .fill(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(palette.borderFaint, lineWidth: 1)))
    }

    private var ctaRow: some View {
        HStack(spacing: 12) {
            // STUB · vesselBunker.setAlert — no backing mutation (generic client has no `mutate`).
            CTAButton(title: "Set BAF alert", action: { Task { await setAlert() } }, trailingIcon: "bell.badge")
            // STUB · reports.exportCostSheet — confirmed absent this fire.
            Button { Task { await exportSeries() } } label: {
                Text("Export")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 144, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(palette.borderFaint, lineWidth: 1)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Data

    private func load() async {
        // Preview short-circuit: seed renders in #Preview only, never on device.
        if let seed = previewSeed {
            series = seed.series
            regions = seed.regions
            esangLine = seed.esangLine
            loading = false
            loadError = nil
            return
        }

        loading = true; loadError = nil
        do {
            // REAL · fuel.getTrends → [{date,price}] EIA fuel-price history (drives the chart line).
            struct TrendsIn: Encodable { let days: Int }
            struct TrendPoint: Decodable { let date: String?; let price: Double? }
            let pts: [TrendPoint] = try await EusoTripAPI.shared.query("fuel.getTrends", input: TrendsIn(days: 30))
            let vals = pts.compactMap { $0.price }.filter { $0 > 0 }
            if vals.count >= 2 { series = vals } else { series = [] }

            // REAL · fuel.getPrices → {regions:[{name,avgPrice,change}]} EIA regional breakdown.
            struct PricesIn: Encodable { let radius: Int }
            struct Region: Decodable { let name: String?; let avgPrice: Double?; let change: Double? }
            struct PricesOut: Decodable { let national: Double?; let regions: [Region]? }
            if let res: PricesOut = try? await EusoTripAPI.shared.query("fuel.getPrices", input: PricesIn(radius: 25)),
               let rs = res.regions {
                regions = rs.compactMap { r in
                    guard let n = r.name, let p = r.avgPrice else { return nil }
                    let code = String(n.prefix(5)).uppercased()
                    return RegionPrice670(name: n, code: code, price: p, delta: r.change ?? 0)
                }
            } else {
                regions = []
            }

            // ESang line is derived honestly from the real series (no fabricated booking figures).
            if series.count >= 2 {
                let dir = weekDelta >= 0 ? "rising" : "easing"
                esangLine = String(format: "Index %@ %+.1f%% pt/pt - review BAF cover", dir, weekDelta)
            } else {
                esangLine = ""
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// STUB · vesselBunker.setAlert — no backing mutation (the generic client exposes only `query`,
    /// and no `vesselBunker` router exists). Surfaced to the-oath; re-runs load() for honesty.
    private func setAlert() async { await load() }

    /// STUB · reports.exportCostSheet — confirmed absent this fire. Re-runs load().
    private func exportSeries() async { await load() }
}

// MARK: - Trend chart (Path-drawn, no chart lib) — preserves the SVG line + area + gridline + dot look.

private struct BunkerTrendChart670: View {
    @Environment(\.palette) private var palette
    let series: [Double]

    private var yMin: Double { (series.min() ?? 0) * 0.96 }
    private var yMax: Double { (series.max() ?? 1) * 1.04 }

    private func pt(_ i: Int, _ v: Double, _ size: CGSize, plotH: CGFloat) -> CGPoint {
        let n = max(1, series.count - 1)
        let span = max(0.0001, yMax - yMin)
        let x = size.width * CGFloat(i) / CGFloat(n)
        let y = plotH * CGFloat(1 - (v - yMin) / span)
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        GeometryReader { geo in
            let plotH = geo.size.height - 28   // leave room for the legend
            let span = max(0.0001, yMax - yMin)
            let mid = yMin + span * 0.5
            let upper = yMin + span * 0.8
            ZStack(alignment: .topLeading) {
                // gridlines @ mid + upper of the live range
                ForEach([upper, mid], id: \.self) { g in
                    let y = plotH * CGFloat(1 - (g - yMin) / span)
                    Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                        .stroke(palette.borderFaint, lineWidth: 1)
                }
                // area under the line
                Path { p in
                    p.move(to: CGPoint(x: 0, y: plotH))
                    for (i, v) in series.enumerated() { p.addLine(to: pt(i, v, geo.size, plotH: plotH)) }
                    p.addLine(to: CGPoint(x: geo.size.width, y: plotH)); p.closeSubpath()
                }.fill(LinearGradient(colors: [Brand.info.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                // primary line
                Path { p in
                    for (i, v) in series.enumerated() {
                        let q = pt(i, v, geo.size, plotH: plotH)
                        if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                    }
                }.stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                // end dot
                Circle().fill(LinearGradient.diagonal).frame(width: 8, height: 8)
                    .position(pt(series.count - 1, series.last ?? 0, geo.size, plotH: plotH))
                // legend
                HStack(spacing: 6) {
                    Capsule().fill(LinearGradient.primary).frame(width: 12, height: 3)
                    Text(String(format: "EIA DIESEL $%.2f/gal", series.last ?? 0))
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textSecondary)
                }
                .position(x: geo.size.width / 2, y: geo.size.height - 6)
            }
        }
    }
}

// MARK: - Previews (seed lives ONLY here)

private let previewSeed670 = PreviewSeed670(
    series: [3.42, 3.48, 3.51, 3.55, 3.58, 3.62, 3.66, 3.71],
    regions: [
        .init(name: "Gulf Coast", code: "PADD3", price: 3.49, delta: -0.6),
        .init(name: "Midwest",    code: "PADD2", price: 3.62, delta:  1.4),
        .init(name: "West Coast", code: "PADD5", price: 4.18, delta:  2.1),
    ],
    esangLine: "Index rising +1.4% pt/pt - review BAF cover")

/// Preview-only Shell wrapper that injects the seed into the body so the populated bespoke
/// chart/table render in Xcode previews. The seed is referenced ONLY from here — on device the
/// public `VesselBunkerPricesScreen` builds the body with no seed, so it loads live or empty.
private struct VesselBunkerPricesPreview670: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselBunkerPricesBody(previewSeed: previewSeed670)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

#Preview("670 · Vessel Bunker Prices · Night") {
    VesselBunkerPricesPreview670(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("670 · Vessel Bunker Prices · Light") {
    VesselBunkerPricesPreview670(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
