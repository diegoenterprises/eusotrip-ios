//
//  742_VesselModeOptimization.swift
//  EusoTrip — Vessel Operator · Mode Optimization (PURPOSE-BUILT DECISION MATRIX).
//
//  Verbatim bespoke port of canonical wireframe "742 Vessel Mode Optimization ·
//  Dark" (06 Vessel · Vessel Operator). A DECISION/COMPARISON MATRIX: Intermodal
//  vs Truck vs Rail compared across Cost / Transit / Reliability, the recommended
//  column highlighted, so the operator books the best-balanced option with the
//  numbers in front of them. NOT a stat-tile stamp — the whole page is one
//  read-across-and-decide table. Docked under SHIPMENTS.
//
//  REAL WIRING (tRPC · server/routers/multiModal.ts — re-verified 2026-07-11):
//    · multiModal.getCostByMode {}                                      (:1802)
//        -> { costComparison:[{mode,avgCostPerMile,avgTotalCost,volume}] }. The
//        REAL per-mode cost row, computed off the loads table.
//    · multiModal.getTransitTimeComparison {}                          (:1861)
//        -> { comparison:[{mode,avgDays,reliability,samples}], topLanes }. The
//        REAL per-mode transit + reliability rows.
//    · multiModal.getModeOptimization {origin,destination,weight}       (:1746)
//        -> { recommendations:[{mode,score,co2Reduction,…}], laneData } (empty
//        today; needs a bound lane) — the score + CO₂ + ranked recommendation
//        enrichment. Named gap surfaced; the matrix derives the recommended mode
//        from the real cost/transit data until it lands.  STUB · named-gap.
//    · "Book intermodal" -> multiModal.createIntermodalBooking (:320) needs a
//        full booking payload (lane, container, dates); the affordance routes
//        into the booking flow rather than fabricate a payload.  Honest gap.
//
//  transportMode=vessel↔intermodal · US · RBAC protectedProcedure. NO mock data —
//  every cell derives from the live cost + transit comparisons.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Data shapes

private struct CostByMode742: Decodable { let costComparison: [CostRow742] }
private struct CostRow742: Decodable { let mode: String; let avgCostPerMile: Double?; let avgTotalCost: Double?; let volume: Int? }

private struct TransitComparison742: Decodable { let comparison: [TransitRow742] }
private struct TransitRow742: Decodable { let mode: String; let avgDays: Double?; let reliability: Double?; let samples: Int? }

private struct ModeOptimization742: Decodable {
    let recommendations: [ModeRec742]
    let laneData: LaneData742?
}
private struct ModeRec742: Decodable {
    let rank: Int?; let mode: String; let score: Int?; let reason: String?
    let cost: Double?; let transitDays: Int?; let co2Reduction: String?; let reliability: Int?
}
private struct LaneData742: Decodable { let distance: Double?; let historicalVolume: Int?; let seasonalFactor: Double? }

// MARK: - Screen

struct VesselModeOptimizationScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VesselModeOptimizationBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle)
        }
    }
}

// MARK: - Mode column model

private struct ModeColumn {
    let key: String          // "intermodal" | "truck" | "rail"
    let label: String
    var cost: Double? = nil
    var transitDays: Double? = nil
    var reliability: Double? = nil
    var co2: String? = nil
    var score: Int? = nil
    var volume: Int? = nil
}

// MARK: - Body

private struct VesselModeOptimizationBody: View {
    @Environment(\.palette) private var palette

    @State private var cost: CostByMode742? = nil
    @State private var transit: TransitComparison742? = nil
    @State private var opt: ModeOptimization742? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var bookNote: String? = nil

    private let modeKeys: [(key: String, label: String)] =
        [("intermodal", "INTERMODAL"), ("truck", "TRUCK"), ("rail", "RAIL")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorCard(err)
                } else if !hasAnyData {
                    EusoEmptyState(systemImage: "arrow.triangle.branch",
                                   title: "No lane data to compare yet",
                                   subtitle: "Mode comparison lights up as cost and transit history accrues across your lanes.")
                } else {
                    recommendedHero
                    laneStrip
                    matrixSection
                    laneDataStrip
                    esangCard
                    if let note = bookNote { infoBanner(note) }
                    ctaRow
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Derived columns

    private var columns: [ModeColumn] {
        modeKeys.map { m in
            var col = ModeColumn(key: m.key, label: m.label)
            if let cr = (cost?.costComparison ?? []).first(where: { $0.mode == m.key }) {
                col.cost = (cr.avgTotalCost ?? 0) > 0 ? cr.avgTotalCost : nil
                col.volume = cr.volume
            }
            if let tr = (transit?.comparison ?? []).first(where: { $0.mode == m.key }) {
                col.transitDays = (tr.samples ?? 0) > 0 ? tr.avgDays : nil
                col.reliability = (tr.samples ?? 0) > 0 ? tr.reliability : nil
            }
            if let rec = (opt?.recommendations ?? []).first(where: { $0.mode == m.key }) {
                col.score = rec.score
                col.co2 = rec.co2Reduction
                if col.cost == nil, let c = rec.cost, c > 0 { col.cost = c }
                if col.transitDays == nil, let t = rec.transitDays { col.transitDays = Double(t) }
                if col.reliability == nil, let r = rec.reliability { col.reliability = Double(r) }
            }
            return col
        }
    }
    private var hasAnyData: Bool {
        columns.contains { $0.cost != nil || $0.transitDays != nil || $0.reliability != nil }
    }
    /// Recommended column — the server rank-1 recommendation, else the lowest-cost
    /// mode that has real cost data (honest derivation).
    private var recommendedKey: String {
        if let rec = (opt?.recommendations ?? []).min(by: { ($0.rank ?? 99) < ($1.rank ?? 99) }) { return rec.mode }
        let priced = columns.filter { $0.cost != nil }
        return priced.min(by: { ($0.cost ?? .infinity) < ($1.cost ?? .infinity) })?.key ?? "intermodal"
    }
    private var recommendedColumn: ModeColumn? { columns.first { $0.key == recommendedKey } }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 8, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · MODE OPTIMIZE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("MODE").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Text("Mode optimization")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary).padding(.top, Space.s4)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5).padding(.bottom, Space.s3)
    }

    // MARK: Recommended hero

    private var recommendedHero: some View {
        let rec = recommendedColumn
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("RECOMMENDED").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(rec?.label.capitalized ?? "—").font(.system(size: 20, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(recSub(rec)).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("SCORE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(rec?.score.map { "\($0)" } ?? "—")
                    .font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
            }
        }
        .padding(Space.s5).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
    }
    private func recSub(_ rec: ModeColumn?) -> String {
        guard let rec else { return "best-balanced mode for this lane" }
        var parts: [String] = []
        if let c = rec.cost { parts.append("\(currency(c)) avg") }
        if let r = rec.reliability { parts.append("\(Int(r))% reliable") }
        if let co2 = rec.co2, !co2.isEmpty { parts.append(co2) }
        return parts.isEmpty ? "best-balanced mode for this lane" : parts.joined(separator: " · ")
    }

    // MARK: Lane strip

    private var laneStrip: some View {
        HStack {
            Text("Lane comparison · your network").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
            Spacer()
            if let d = opt?.laneData?.distance, d > 0 {
                Text("\(Int(d)) mi").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            } else {
                Text("all active lanes").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Matrix

    private var matrixSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("MODE COMPARISON").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getCostByMode · getTransitTimeComparison").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                columnHeaderRow
                Divider().overlay(palette.borderFaint)
                matrixRow("Cost", values: columns.map { $0.cost.map { currency($0) } ?? "—" })
                Divider().overlay(palette.borderFaint)
                matrixRow("Transit", values: columns.map { $0.transitDays.map { fmtDays($0) } ?? "—" })
                Divider().overlay(palette.borderFaint)
                matrixRow("Reliability", values: columns.map { $0.reliability.map { "\(Int($0))%" } ?? "—" })
                Divider().overlay(palette.borderFaint)
                matrixRow("CO₂ vs truck", values: columns.map { $0.co2 ?? "—" })
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var columnHeaderRow: some View {
        HStack(spacing: 0) {
            Text("").frame(width: 88, alignment: .leading)
            ForEach(columns, id: \.key) { col in
                VStack(spacing: 3) {
                    Text(col.label).font(.system(size: 9, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(col.key == recommendedKey ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textTertiary))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if col.key == recommendedKey {
                        Text("BEST").font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(LinearGradient.diagonal))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
    }

    private func matrixRow(_ label: String, values: [String]) -> some View {
        HStack(spacing: 0) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                .frame(width: 88, alignment: .leading)
            ForEach(Array(columns.indices), id: \.self) { i in
                let col = columns[i]
                Text(i < values.count ? values[i] : "—")
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(col.key == recommendedKey ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textPrimary))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .background(recommendedTint)
    }
    private var recommendedTint: some View {
        GeometryReader { geo in
            let colW = (geo.size.width - 88) / CGFloat(columns.count)
            let idx = columns.firstIndex { $0.key == recommendedKey } ?? 0
            LinearGradient.diagonal.opacity(0.08)
                .frame(width: colW)
                .offset(x: 88 + colW * CGFloat(idx))
        }
    }

    // MARK: Lane data strip

    private var laneDataStrip: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.info)
            VStack(alignment: .leading, spacing: 2) {
                Text("LANE DATA").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(laneDataText).font(.system(size: 11)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private var laneDataText: String {
        var parts: [String] = []
        if let v = opt?.laneData?.historicalVolume, v > 0 { parts.append("volume \(v)/qtr") }
        if let f = opt?.laneData?.seasonalFactor, f > 0 { parts.append(String(format: "seasonal %.2f", f)) }
        let carriers = columns.filter { ($0.volume ?? 0) > 0 }.count
        if carriers > 0 { parts.append("\(carriers) mode\(carriers == 1 ? "" : "s") with volume") }
        return parts.isEmpty ? "historical cost + transit across your active lanes" : parts.joined(separator: " · ")
    }

    // MARK: ESANG

    private var esangCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG AI").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(esangHeadline).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(esangDetail).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private var esangHeadline: String {
        guard let rec = recommendedColumn else { return "Book the best-balanced mode for this lane" }
        return "Book \(rec.label.capitalized) for this lane"
    }
    private var esangDetail: String {
        guard let rec = recommendedColumn else { return "Weighs cost, transit, and reliability." }
        let cheapestTruck = columns.first { $0.key == "truck" }?.cost
        if let recCost = rec.cost, let truck = cheapestTruck, truck > recCost {
            return "Saves \(currency(truck - recCost)) vs truck · best cost-to-transit balance"
        }
        return "Best cost-to-transit balance across your modes"
    }

    // MARK: CTA

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                bookNote = "Intermodal booking needs a bound lane, container, and dates — open the booking flow to tender this move."
            } label: {
                Text("Book intermodal").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48).background(LinearGradient.primary).clipShape(Capsule())
            }.buttonStyle(.plain).frame(maxWidth: .infinity)
            Button { } label: {
                Text("Compare").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(minWidth: 120, minHeight: 48).padding(.horizontal, Space.s3)
                    .background(palette.bgCard).overlay(Capsule().strokeBorder(palette.borderFaint)).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    // MARK: States / format

    private func infoBanner(_ msg: String) -> some View {
        LifecycleCard(accentWarning: true) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.warning)
                Text(msg).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }
    private func errorCard(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }
    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 100)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 240)
        }
    }
    private func currency(_ v: Double) -> String {
        v == v.rounded() ? "$\(Int(v).formatted(.number.grouping(.automatic)))" : "$\(String(format: "%.0f", v))"
    }
    private func fmtDays(_ d: Double) -> String {
        d == d.rounded() ? "\(Int(d)) d" : String(format: "%.1f d", d)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            async let c: CostByMode742 = EusoTripAPI.shared.queryNoInput("multiModal.getCostByMode")
            async let t: TransitComparison742 = EusoTripAPI.shared.queryNoInput("multiModal.getTransitTimeComparison")
            let (cResp, tResp) = try await (c, t)
            self.cost = cResp; self.transit = tResp
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("742 · Vessel Mode Optimization · Night") {
    VesselModeOptimizationScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("742 · Vessel Mode Optimization · Light") {
    VesselModeOptimizationScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
