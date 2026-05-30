//
//  712_VesselFinancialSummary.swift
//  EusoTrip — Vessel Operator · Financials (revenue waterfall bridge + KPI
//  strip + by-lane contribution).
//
//  Verbatim port of wireframe "712 Vessel Financial Summary · Dark".
//  CARRIER-SIDE · FINANCIAL/LEDGER class (operator revenue/cost/margin rollup).
//  Web parity: VesselFinancials.tsx (`/vessel/financials`).
//  tRPC: vesselShipments.getVesselFinancialSummary (vesselProcedure).
//  NAV (VesselOperatorNavController): HOME · SHIPMENTS · [orb] · COMPLIANCE · ME(current).
//
//  PORT NOTE — the live `getVesselFinancialSummary` procedure
//  (vesselShipments.ts:1303) returns raw `{ settlements, demurrage }` rows,
//  NOT the precomputed revenue/cost/margin rollup + bridge segments the
//  wireframe <desc> assumes. The bridge, KPI strip, and contribution rows
//  below are therefore derived client-side FROM the real settlement +
//  demurrage rows (no mock data):
//      revenue = Σ totalShipperCharge
//      cost    = Σ (carrierPayment + platformFeeAmount + accessorial) + Σ demurrage.totalCharge
//      margin  = revenue − cost
//  The per-lane contribution rows depend on a lane label + UNLOCODE pair +
//  contribution-margin typing the server does not yet emit on the settlement
//  row — that is the named STUB the wireframe flagged and is surfaced here as
//  a PORT-GAP (see portGaps), grouping instead by settlement status, which
//  IS on the wire. When the typed per-lane rollup ships, swap `byLane`.
//

import SwiftUI

struct VesselFinancialSummaryScreen: View {
    let theme: Theme.Palette
    var id: String = ""
    var body: some View {
        Shell(theme: theme) { VesselFinancialSummaryBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire shapes (vesselShipments.getVesselFinancialSummary)

/// drizzle `decimal()` columns serialize over the wire as JSON strings;
/// some derived/aggregate paths can come back as raw numbers. Decode either.
private struct FlexNum: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        value = nil
    }
}

private struct VesselSettlementRow712: Decodable, Identifiable {
    let id: Int
    let vesselShipmentId: Int?
    let loadRate: FlexNum?
    let platformFeeAmount: FlexNum?
    let carrierPayment: FlexNum?
    let accessorialCharges: FlexNum?
    let accessorialTotal: FlexNum?
    let hazmatSurcharge: FlexNum?
    let totalShipperCharge: FlexNum?
    let status: String?

    var revenue: Double { totalShipperCharge?.value ?? 0 }
    var cost: Double {
        (carrierPayment?.value ?? 0)
        + (platformFeeAmount?.value ?? 0)
        + (accessorialCharges?.value ?? accessorialTotal?.value ?? 0)
        + (hazmatSurcharge?.value ?? 0)
    }
}

private struct VesselDemurrageRow712: Decodable, Identifiable {
    let id: Int
    let chargeType: String?
    let totalCharge: FlexNum?
    let status: String?
    var charge: Double { totalCharge?.value ?? 0 }
}

private struct VesselFinancialSummary712: Decodable {
    let settlements: [VesselSettlementRow712]
    let demurrage: [VesselDemurrageRow712]
}

// MARK: - Derived rollup (client-side from real rows)

private struct LaneContribution: Identifiable {
    let id: String
    let lane: String
    let sub: String
    let bookings: Int
    let revenue: Double
    let marginPct: Double
}

private struct FinancialRollup {
    let revenue: Double
    let oceanCost: Double   // carrier payment (ocean freight bought)
    let opsCost: Double     // platform fee + accessorial + hazmat + demurrage
    var totalCost: Double { oceanCost + opsCost }
    var netMargin: Double { revenue - totalCost }
    var marginPct: Double { revenue > 0 ? (netMargin / revenue) * 100 : 0 }
    let arOpen: Double
    let arInvoices: Int
    let lanes: [LaneContribution]

    static func from(_ s: VesselFinancialSummary712) -> FinancialRollup {
        let revenue   = s.settlements.reduce(0) { $0 + $1.revenue }
        let oceanCost = s.settlements.reduce(0) { $0 + ($1.carrierPayment?.value ?? 0) }
        let settlementOps = s.settlements.reduce(0) {
            $0 + ($1.platformFeeAmount?.value ?? 0)
               + ($1.accessorialCharges?.value ?? $1.accessorialTotal?.value ?? 0)
               + ($1.hazmatSurcharge?.value ?? 0)
        }
        let demurrageOps = s.demurrage.reduce(0) { $0 + $1.charge }
        let opsCost = settlementOps + demurrageOps

        // AR open = settlements not yet completed.
        let open = s.settlements.filter { ($0.status ?? "").lowercased() != "completed" }
        let arOpen = open.reduce(0) { $0 + $1.revenue }

        // PORT-GAP fallback: server emits no lane label / UNLOCODE pair /
        // contribution-margin typing on the settlement row, so we group by
        // settlement status (which IS on the wire) to keep a real,
        // non-fabricated contribution breakdown. Replace with the typed
        // per-lane rollup when the procedure ships it.
        let grouped = Dictionary(grouping: s.settlements) { ($0.status ?? "unknown").lowercased() }
        let lanes: [LaneContribution] = grouped
            .map { (key, rows) -> LaneContribution in
                let rev = rows.reduce(0) { $0 + $1.revenue }
                let cost = rows.reduce(0) { $0 + $1.cost } + (rows.first?.carrierPayment?.value ?? 0)
                let cst = rows.reduce(0) { $0 + $1.cost }
                _ = cost
                let mgn = rev > 0 ? ((rev - cst) / rev) * 100 : 0
                return LaneContribution(
                    id: key,
                    lane: key.replacingOccurrences(of: "_", with: " ").capitalized,
                    sub: "\(rows.count) settlement\(rows.count == 1 ? "" : "s")",
                    bookings: rows.count,
                    revenue: rev,
                    marginPct: mgn
                )
            }
            .sorted { $0.revenue > $1.revenue }

        return FinancialRollup(
            revenue: revenue, oceanCost: oceanCost, opsCost: opsCost,
            arOpen: arOpen, arInvoices: open.count, lanes: lanes
        )
    }
}

// MARK: - Money formatting (matches 650's $X.XM / $XK style)

private func moneyShort(_ v: Double) -> String {
    let a = abs(v)
    let sign = v < 0 ? "−" : ""
    if a >= 1_000_000 { return String(format: "%@$%.2fM", sign, a / 1_000_000) }
    if a >= 1_000     { return String(format: "%@$%.0fK", sign, a / 1_000) }
    return String(format: "%@$%.0f", sign, a)
}

private func moneyKPI(_ v: Double) -> String {
    let a = abs(v)
    if a >= 1_000_000 { return String(format: "$%.2fM", a / 1_000_000) }
    if a >= 1_000     { return String(format: "$%.0fK", a / 1_000) }
    return String(format: "$%.0f", a)
}

// MARK: - Body

private struct VesselFinancialSummaryBody: View {
    @Environment(\.palette) private var palette
    @State private var rollup: FinancialRollup? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var exporting = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s4)
                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        LifecycleCard {
                            Text("Loading financials…").font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if let r = rollup {
                        bridgeHero(r)
                        kpiStrip(r)
                        byLaneList(r)
                        ctaPair
                    }
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (DETAIL · back chevron + eyebrow + title)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ VESSEL OPERATOR · FINANCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("MTD · USD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Financials")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s4)
        }
        .padding(.horizontal, 20)
        .padding(.top, Space.s4)
    }

    // MARK: - Revenue Waterfall Bridge hero (bespoke)

    private func bridgeHero(_ r: FinancialRollup) -> some View {
        // Plot geometry mirrors the SVG: baseline at local y=178, 80px == the
        // revenue magnitude (full bar). Bars are sized as a fraction of the
        // revenue column so the descending cost floats read as a true bridge.
        let baseH: CGFloat = 80
        let rev = max(r.revenue, 0.0001)
        let oceanFrac = CGFloat(min(max(r.oceanCost / rev, 0), 1))
        let opsFrac   = CGFloat(min(max(r.opsCost / rev, 0), 1))
        let marginFrac = CGFloat(min(max(r.netMargin / rev, 0), 1))

        let revH    = baseH
        let oceanH  = baseH * oceanFrac
        let opsH    = baseH * opsFrac
        let marginH = baseH * marginFrac

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("REVENUE BRIDGE · MTD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("NET MARGIN")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(moneyKPI(r.netMargin)) · \(Int(r.marginPct.rounded()))%")
                        .font(.system(size: 18, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .padding(.bottom, Space.s4)

            // Waterfall plot — 4 columns: Revenue, Ocean, Ops, Margin
            HStack(alignment: .bottom, spacing: 0) {
                waterfallColumn(
                    label: "Revenue", topText: moneyShort(r.revenue),
                    barHeight: revH, maxHeight: baseH,
                    fill: AnyShapeStyle(Brand.info.opacity(0.85)),
                    valueColor: palette.textPrimary, drop: false
                )
                waterfallColumn(
                    label: "Ocean", topText: moneyShort(-r.oceanCost),
                    barHeight: oceanH, maxHeight: baseH,
                    fill: AnyShapeStyle(Brand.danger.opacity(0.85)),
                    valueColor: Brand.danger, drop: true
                )
                waterfallColumn(
                    label: "Ops", topText: moneyShort(-r.opsCost),
                    barHeight: opsH, maxHeight: baseH,
                    fill: AnyShapeStyle(Brand.danger.opacity(0.6)),
                    valueColor: Brand.danger, drop: true
                )
                waterfallColumn(
                    label: "Margin", topText: moneyShort(r.netMargin),
                    barHeight: marginH, maxHeight: baseH,
                    fill: AnyShapeStyle(LinearGradient.diagonal),
                    valueColor: palette.textPrimary, drop: false
                )
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
                    .padding(.bottom, 16)  // sits on baseline, above axis labels
            }
            .padding(.top, Space.s2)
        }
        .padding(Space.s5)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    /// One waterfall column — value chip on top, bar bottom-anchored within a
    /// fixed-height plot lane, axis label beneath. `drop` columns (cost
    /// floats) sit at the top of the plot lane to read as descending steps.
    private func waterfallColumn(
        label: String, topText: String,
        barHeight: CGFloat, maxHeight: CGFloat,
        fill: AnyShapeStyle, valueColor: Color, drop: Bool
    ) -> some View {
        VStack(spacing: 6) {
            Text(topText)
                .font(.system(size: 11, weight: .bold)).monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.6)
            ZStack(alignment: drop ? .top : .bottom) {
                Color.clear.frame(height: maxHeight)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(fill)
                    .frame(height: max(barHeight, 3))
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - KPI strip (4-cell)

    private func kpiStrip(_ r: FinancialRollup) -> some View {
        HStack(spacing: Space.s2) {
            kpiCell(label: "REVENUE", value: moneyKPI(r.revenue),
                    footnote: "MTD", footColor: Brand.success, gradient: false, valueColor: palette.textPrimary)
            kpiCell(label: "COST", value: moneyKPI(r.totalCost),
                    footnote: r.revenue > 0 ? "\(Int((r.totalCost / r.revenue * 100).rounded()))% of rev" : "—",
                    footColor: palette.textSecondary, gradient: false, valueColor: palette.textPrimary)
            kpiCell(label: "MARGIN", value: "\(Int(r.marginPct.rounded()))%",
                    footnote: r.marginPct >= 0 ? "net" : "loss",
                    footColor: r.marginPct >= 0 ? Brand.success : Brand.danger,
                    gradient: true, valueColor: palette.textPrimary)
            kpiCell(label: "AR OPEN", value: moneyKPI(r.arOpen),
                    footnote: "\(r.arInvoices) inv",
                    footColor: palette.textSecondary, gradient: false, valueColor: Brand.warning)
        }
    }

    private func kpiCell(label: String, value: String, footnote: String,
                         footColor: Color, gradient: Bool, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 6)
            Group {
                if gradient {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(value).foregroundStyle(valueColor)
                }
            }
            .font(.system(size: gradient ? 26 : 20, weight: .semibold)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.5)
            Text(footnote)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(footColor)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .padding(.horizontal, 12).padding(.vertical, 12)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - By-lane contribution list

    private func byLaneList(_ r: FinancialRollup) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("BY LANE · CONTRIBUTION")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(r.lanes.count) lane\(r.lanes.count == 1 ? "" : "s")")
                    .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
            }
            if r.lanes.isEmpty {
                EusoEmptyState(systemImage: "chart.bar.doc.horizontal",
                               title: "No contribution data",
                               subtitle: "Settled vessel bookings will roll up by lane here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(r.lanes.enumerated()), id: \.element.id) { idx, lane in
                        laneRow(lane, accent: laneAccent(idx))
                        if idx < r.lanes.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.08))
                                .frame(height: 1)
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.vertical, Space.s2)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    /// Lane accent cycles info → success → hazmat (matches the SVG's three
    /// icon chips: blue Trans-Pacific, green Trans-Atlantic, amber feeder).
    private func laneAccent(_ idx: Int) -> Color {
        switch idx % 3 {
        case 0:  return Brand.info
        case 1:  return Brand.success
        default: return Brand.warning
        }
    }

    private func laneRow(_ lane: LaneContribution, accent: Color) -> some View {
        let mgnColor: Color = lane.marginPct >= 15 ? Brand.success
            : (lane.marginPct >= 10 ? Brand.warning : Brand.warning)
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "shippingbox")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(lane.lane)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(lane.sub)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int(lane.marginPct.rounded()))% MGN")
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(mgnColor)
                Text(moneyKPI(lane.revenue))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, Space.s3)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                exporting = true
            } label: {
                Text("Export statement")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .background(LinearGradient.primary)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)

            Button {
                // PORT-GAP: Settlement CTA → vesselShipments.getVesselSettlement
                // (per-booking payout). No nav router hook exposed to this body;
                // see portGaps.
            } label: {
                Text("Settlement")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
            }
            .background(palette.bgCardSoft)
            .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            .clipShape(Capsule())
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        do {
            let s: VesselFinancialSummary712 = try await EusoTripAPI.shared
                .queryNoInput("vesselShipments.getVesselFinancialSummary")
            self.rollup = FinancialRollup.from(s)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("712 · Vessel Financial Summary · Night") { VesselFinancialSummaryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("712 · Vessel Financial Summary · Light") { VesselFinancialSummaryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
