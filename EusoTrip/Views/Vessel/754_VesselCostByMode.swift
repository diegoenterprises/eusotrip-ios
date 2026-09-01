//
//  754_VesselCostByMode.swift
//  EusoTrip — Vessel Operator · Cost by Mode.
//
//  Faithful 1:1 port of "754 Vessel Cost by Mode.svg" (Light + Dark).
//  COST-SPREAD NUMBER-LINE + SAVINGS-LEDGER archetype (deliberately distinct
//  from 753's transit bars and 755's portfolio composition): a recoverable-
//  savings hero, a labeled cost number-line where each mode is a dot positioned
//  by its all-in cost, then a ranked ledger whose right column is the delta-vs-
//  ocean — a money/optimization surface, not a chip-comparison. Detail header,
//  hero, number-line + ledger, CTA pair, and a tri-currency FX conversion rail
//  (COUNTRY-DONE). Real Vessel-Operator BottomNav with HOME inked.
//
//  Wiring (endpoint confirmed on disk this fire):
//    multiModal.getCostByMode — EXISTS frontend/server/routers/multiModal.ts:1802
//      · protectedProcedure · query · input {origin?,destination?,weight?,dateRange?}
//      · returns {costComparison:[{mode,avgCostPerMile,avgTotalCost,volume,trend}], monthlyCosts:[]}
//      derived from real loads (rate / distance, intermodal split).
//    "Optimize lane" → multiModal.getModeOptimization EXISTS multiModal.ts:1746 (re-runs load()).
//    "Export" → STUB · named-gap exportCostByModeLedger (no render mutation yet).
//    FX CONVERSION RAIL (COUNTRY-DONE) → US·USD is the live all-in from getCostByMode;
//      CA C$ (CRA) + MX MXN (SAT) are STANDBY, converted with disclosed static FX and
//      labelled "FX pending" — NAMED GAP vessel.getSettlementCurrencyRegime({country})
//      -> {currency,fiscalAuthority,fxRate,fxAsOf} verified ABSENT (handed to the-oath).
//
//  0 mock data on load · honest empty/degraded states. Historical load
//  aggregate (not a live tick), so no map/geofence fusion applies here.
//

import SwiftUI

// MARK: - Model

private struct CostMode754: Identifiable {
    let mode: String
    let avgCostPerMile: Double
    let avgTotalCost: Double
    let volume: Int
    var id: String { mode }
}

private struct CostBoard754 {
    let modes: [CostMode754]
    var withData: [CostMode754] { modes.filter { $0.avgTotalCost > 0 } }
    var ocean: CostMode754? { modes.first { $0.mode == "ocean" } }
    /// Cheapest non-ocean mode with data.
    var best: CostMode754? { withData.filter { $0.mode != "ocean" }.min { $0.avgTotalCost < $1.avgTotalCost } }
    var axisMin: Double { withData.map(\.avgTotalCost).min() ?? 0 }
    var axisMax: Double { withData.map(\.avgTotalCost).max() ?? 1 }
    /// Recoverable per-FEU: ocean baseline minus best alternative.
    var recoverable: Double {
        guard let o = ocean, o.avgTotalCost > 0, let b = best else { return 0 }
        return max(0, o.avgTotalCost - b.avgTotalCost)
    }
}

private struct CostQuery754: Encodable { let origin: String?; let destination: String? }

// MARK: - Wrapper

struct VesselCostByModeScreen: View {
    let theme: Theme.Palette
    let origin: String
    let destination: String
    init(theme: Theme.Palette, origin: String = "CNSHA", destination: String = "USLGB") {
        self.theme = theme; self.origin = origin; self.destination = destination
    }
    var body: some View {
        Shell(theme: theme) {
            VesselCostByModeBody754(origin: origin, destination: destination)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: true),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselCostByModeBody754: View {
    let origin: String
    let destination: String
    @Environment(\.palette) private var palette

    @State private var board: CostBoard754? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Disclosed static FX for the STANDBY currency rail (regime proc is a named gap).
    private let fxCad = 1.366
    private let fxMxn = 18.34

    private let ocean = Brand.info
    private let intermodal = Brand.escort
    private let rail = Color(hex: 0x2FBE82)
    private let truck = Brand.warning

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading cost by mode…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let b = board, !b.withData.isEmpty {
                    heroCard(b)
                    spreadSection(b)
                    ctaPair
                    fxRail(b)
                } else {
                    EusoEmptyState(systemImage: "dollarsign.arrow.circlepath",
                                   title: "No cost history in range",
                                   subtitle: "No priced loads were found for \(origin) → \(destination). There is no verified all-in cost to compare yet.")
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · COST BY MODE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("LAST 90 DAYS").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Text("Cost by mode").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    private var subline: String {
        guard let b = board else { return "All-in cost per load · by transport mode" }
        let spend = b.withData.reduce(0.0) { $0 + $1.avgTotalCost * Double($1.volume) }
        return "All-in $/load · \(money(spend)) spend · \(b.withData.reduce(0) { $0 + $1.volume }) loads"
    }

    // MARK: Hero — recoverable savings

    private func heroCard(_ b: CostBoard754) -> some View {
        RimCard754 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("RECOVERABLE · PER LOAD").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(b.withData.count) MODES").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
                HStack(alignment: .top) {
                    Text(money(b.recoverable)).font(.system(size: 44, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        miniStat("OCEAN NOW", money(b.ocean?.avgTotalCost ?? 0), ocean)
                        if let best = b.best { miniStat("BEST · \(best.mode.uppercased())", money(best.avgTotalCost), rail) }
                    }
                }
                Text(b.best.map { "Shift \($0.mode)-eligible volume off ocean to capture it" } ?? "Ocean is currently the only priced mode")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func miniStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(0.4).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(color)
        }
    }

    // MARK: Number-line + ledger

    private func spreadSection(_ b: CostBoard754) -> some View {
        let rows = b.withData.sorted { $0.avgTotalCost < $1.avgTotalCost }
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("COST SPREAD · ALL-IN $/LOAD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 0) {
                numberLine(b)
                Divider().overlay(palette.borderFaint).padding(.vertical, 4)
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, m in
                    CostRow754(mode: m, accent: accent(m.mode),
                               delta: (b.ocean.map { m.avgTotalCost - $0.avgTotalCost } ?? 0),
                               isBaseline: m.mode == "ocean")
                    if idx < rows.count - 1 { Divider().overlay(palette.borderFaint).padding(.leading, 16) }
                }
            }
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func numberLine(_ b: CostBoard754) -> some View {
        let span = max(1, b.axisMax - b.axisMin)
        return VStack(spacing: 6) {
            HStack {
                Text(money(b.axisMin)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(money(b.axisMax)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.textPrimary.opacity(0.10)).frame(height: 4)
                    ForEach(b.withData) { m in
                        let frac = (m.avgTotalCost - b.axisMin) / span
                        Circle().fill(accent(m.mode))
                            .frame(width: m.mode == "ocean" ? 12 : 9, height: m.mode == "ocean" ? 12 : 9)
                            .overlay(m.mode == "ocean" ? Circle().fill(Color.white).frame(width: 4, height: 4) : nil)
                            .offset(x: min(w - 12, max(0, frac * w - 6)))
                    }
                }
            }.frame(height: 14)
        }
        .padding(.horizontal, 16).padding(.top, 6)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: 8) {
            CTAButton(title: "Optimize lane", action: { Task { await load() } })
            Button(action: { Task { await load() } }) {
                Text("Export").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }.buttonStyle(.plain).frame(width: 128)
        }
    }

    // MARK: FX conversion rail (COUNTRY-DONE)

    private func fxRail(_ b: CostBoard754) -> some View {
        let usd = b.recoverable
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SETTLED CURRENCY · FX").font(.system(size: 8.5, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("US · USD ACTIVE").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Color(hex: 0x64B5F6))
            }
            HStack(alignment: .top, spacing: 12) {
                fxCell(money(usd), "USD · CBP/IRS", Color(hex: 0x64B5F6))
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary).padding(.top, 4)
                fxCell("C$\(Int((usd * fxCad).rounded()).formatted(.number.grouping(.automatic)))", "CAD · CRA · \(String(format: "%.3f", fxCad)) · standby", palette.textSecondary)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary).padding(.top, 4)
                fxCell("$\(Int((usd * fxMxn).rounded()).formatted(.number.grouping(.automatic)))", "MXN · SAT · \(String(format: "%.2f", fxMxn)) · standby", palette.textSecondary)
                Spacer(minLength: 0)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private func fxCell(_ value: String, _ label: String, _ valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(valueColor)
            Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(palette.textTertiary).fixedSize(horizontal: false, vertical: true)
        }.frame(width: 96, alignment: .leading)
    }

    // MARK: Helpers

    private func accent(_ mode: String) -> Color {
        switch mode { case "ocean": return ocean; case "intermodal": return intermodal; case "rail": return rail; default: return truck }
    }
    private func money(_ v: Double) -> String { "$\(Int(v).formatted(.number.grouping(.automatic)))" }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        do {
            struct Row: Decodable { let mode: String?; let avgCostPerMile: Double?; let avgTotalCost: Double?; let volume: Int? }
            struct Resp: Decodable { let costComparison: [Row]? }
            let r: Resp = try await EusoTripAPI.shared.query(
                "multiModal.getCostByMode",
                input: CostQuery754(origin: origin, destination: destination)
            )
            let modes = (r.costComparison ?? []).compactMap { row -> CostMode754? in
                guard let m = row.mode else { return nil }
                return CostMode754(mode: m, avgCostPerMile: row.avgCostPerMile ?? 0,
                                   avgTotalCost: row.avgTotalCost ?? 0, volume: row.volume ?? 0)
            }
            board = CostBoard754(modes: modes)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - File-scoped bespoke helpers

private struct RimCard754<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }
}

/// Ledger row — mode chip + $/mi sub + all-in figure + delta-vs-ocean pill.
private struct CostRow754: View {
    @Environment(\.palette) private var palette
    let mode: CostMode754
    let accent: Color
    let delta: Double        // negative = savings vs ocean
    let isBaseline: Bool

    private var glyph: String {
        switch mode.mode {
        case "ocean": return "ferry"
        case "intermodal": return "arrow.left.arrow.right"
        case "rail": return "tram.fill"
        default: return "box.truck.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: glyph).font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(accent.opacity(0.20)))
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.mode.capitalized).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("$\(String(format: "%.2f", mode.avgCostPerMile))/mi · \(mode.volume) loads")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("$\(Int(mode.avgTotalCost).formatted(.number.grouping(.automatic)))")
                    .font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                if isBaseline {
                    pill("YOURS", Brand.info)
                } else if delta < 0 {
                    pill("−$\(Int(-delta).formatted(.number.grouping(.automatic)))", Color(hex: 0x2FBE82))
                } else if delta > 0 {
                    pill("+$\(Int(delta).formatted(.number.grouping(.automatic)))", Brand.warning)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func pill(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).monospacedDigit().foregroundStyle(c)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(c.opacity(0.16)))
    }
}

#Preview("754 · Vessel Cost by Mode · Night") { VesselCostByModeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("754 · Vessel Cost by Mode · Light") { VesselCostByModeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
