//
//  772_VesselDemurrageAnalytics.swift
//  EusoTrip — Vessel Operator · Demurrage & Detention Analytics.
//
//  Faithful 1:1 port of "772 Vessel Demurrage Analytics.svg" (Light + Dark),
//  RECONSTRUCTED to a purpose-built TREND-ANALYTICS archetype (kills the stamped
//  hero+3KPI+chip-list monotony). Composition mirrors the SVG: detail header; a
//  summary band (total + avoidable); a real 6-month COLUMN chart (each month split into
//  baseline vs avoidable, computed from the decoded charges) — NOT a watch-list; a
//  BY-CHARGE-TYPE horizontal breakdown; ESang advisory; Open dispute queue / Export CTA.
//
//  Window Dec–May · VES-260524-5A37CC · Vessel Operator Lena Bjornstad (LB) ·
//  Aurora Ocean Division; shipper-of-record Diego Usoro · Eusorone Technologies (DU).
//  Nav: Compliance tab current (D&D analytics is a compliance-domain surface) —
//  same Shell + BottomNav wrapper the registered vessel siblings 664/680/757 ship.
//
//  Data / wiring (endpoint confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    vesselShipments.getVesselFinancialSummary
//      (EXISTS frontend/server/routers/vesselShipments.ts:1775 · vesselProcedure · no input ·
//       returns {settlements:[], demurrage:[]}; demurrage rows come straight off the
//       vessel_demurrage table — db.ts:2549 — {chargeType ENUM(demurrage|detention|per_diem),
//       chargeableDays INT, ratePerDay DECIMAL(8,2), totalCharge DECIMAL(10,2), status
//       ENUM(accruing|invoiced|paid|disputed|waived), startDate TIMESTAMP}. DECIMAL columns
//       serialize as JSON strings, so ratePerDay/totalCharge decode as String?.)
//    Monthly + by-charge-type aggregation is computed CLIENT-SIDE from the decoded rows
//    (no fabricated arrays). When the table is empty the bespoke empty state renders honestly.
//
//    "Open dispute queue" opens a live queue from the decoded rows; per-row Dispute calls
//    vesselShipments.disputeVesselDemurrage. Export calls vesselShipments.exportVesselDemurrageAnalytics.
//
//  CRITICAL PITFALLS fixed vs the canonical Code/ port:
//    (1) CTAButton — canonical used a trailing-closure `CTAButton(title:){}`; here `action:`
//        is the NAMED 2nd parameter.  (2) OrbESang → OrbeSang (the real in-module symbol; the
//        canonical had a casing typo).  (3) EmptyQuery → file-private EmptyInput772 (no module
//        EmptyInput).  (4) every file-scoped helper type suffixed 772 to avoid private-type
//        collisions.  (5) all referenced design-system symbols confirmed in-module; the
//        outline secondary button uses RoundedRectangle(Radius.md) per the app-wide button std.
//

import SwiftUI

struct VesselDemurrageAnalyticsScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselDemurrageAnalyticsBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror getVesselFinancialSummary.demurrage[] / vessel_demurrage table)

private struct FinancialSummary772: Decodable { let demurrage: [DemurrageRow772] }
private struct DemurrageRow772: Decodable {
    let id: Int?
    let shipmentId: Int?
    let chargeType: String?
    let chargeableDays: Int?
    let ratePerDay: String?
    let totalCharge: String?
    let status: String?
    let startDate: String?
    var amount: Double { Double(totalCharge ?? "0") ?? 0 }
    /// Avoidable = disputable/waivable charges (detention, disputed/waived/pending status).
    var isAvoidable: Bool {
        (chargeType ?? "").lowercased().contains("detention") ||
        ["disputed", "waived", "pending"].contains((status ?? "").lowercased())
    }
}
private struct MonthBucket772: Identifiable { let id = UUID(); let label: String; let baseline: Double; let avoidable: Double; var total: Double { baseline + avoidable } }
private struct CauseBucket772: Identifiable { let id = UUID(); let label: String; let usd: Double; let color: Color }
private struct EmptyInput772: Encodable {}
private struct ExportInput772: Encodable { let format: String }
private struct ExportOut772: Decodable { let format: String?; let rowCount: Int?; let data: String?; let exportedAt: String? }
private struct DisputeInput772: Encodable { let shipmentId: Int; let demurrageId: Int?; let reason: String }
private struct ActionOut772: Decodable { let success: Bool?; let disputed: Int? }

// MARK: - Body

private struct VesselDemurrageAnalyticsBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [DemurrageRow772] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil
    @State private var showDisputeQueue = false
    @State private var disputeInFlight: Int? = nil

    private var months: [MonthBucket772] { Self.bucketByMonth(rows) }
    private var causes: [CauseBucket772] { Self.bucketByCause(rows) }
    private var total: Double { rows.reduce(0) { $0 + $1.amount } }
    private var avoidable: Double { rows.filter { $0.isAvoidable }.reduce(0) { $0 + $1.amount } }
    private var contestableRows: [DemurrageRow772] {
        rows.filter { ["accruing", "invoiced"].contains(($0.status ?? "").lowercased()) && $0.shipmentId != nil }
    }

    // Honest derived labels (2026-06-09 · C1 cluster fix) — every identity/tariff
    // string below computes from the decoded rows; em-dash when absent. No hardcoded
    // "$150/day · 4 free days", no invented VES- ref, no fabricated Dec–May window.
    private var windowLabel: String {
        guard let first = months.first?.label, let last = months.last?.label else { return "—" }
        return first == last ? first.uppercased() : "\(first.uppercased()) – \(last.uppercased())"
    }
    private var avgRateLabel: String {
        let ratesByDay = rows.compactMap { Double($0.ratePerDay ?? "") }.filter { $0 > 0 }
        guard !ratesByDay.isEmpty else { return "" }
        let avg = ratesByDay.reduce(0, +) / Double(ratesByDay.count)
        return String(format: "avg $%.0f/day · ", avg)
    }
    private var disputedCount: Int { rows.filter { ($0.status ?? "").lowercased() == "disputed" }.count }
    private var waivedCount: Int { rows.filter { ($0.status ?? "").lowercased() == "waived" }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    ActiveCard { Text("Aggregating charges…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    ActiveCard { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if rows.isEmpty {
                    EusoEmptyState(systemImage: "chart.bar.xaxis",
                                   title: "No demurrage to analyze",
                                   subtitle: "No demurrage charges came back for this range. Nothing has accrued, so there is no trend to chart and nothing to dispute.")
                } else {
                    actionBanners
                    summaryBand
                    trendCard
                    causeCard
                    esang
                    HStack(spacing: 8) {
                        CTAButton(title: "Open dispute queue", action: { Task { await openDisputeQueue() } }, trailingIcon: "tray.full")
                        secondaryButton(title: "Export") { Task { await exportSummary() } }
                            .frame(width: 120)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showDisputeQueue) { disputeQueueSheet }
    }

    @ViewBuilder private var actionBanners: some View {
        if let actionMessage {
            ActiveCard {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.success)
                    Text(actionMessage).font(EType.caption).foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
        if let actionError {
            ActiveCard {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
                    Text(actionError).font(EType.caption).foregroundStyle(Brand.danger)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var disputeQueueSheet: some View {
        NavigationStack {
            List {
                if contestableRows.isEmpty {
                    Text("No accruing or invoiced demurrage charges are contestable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(contestableRows.indices, id: \.self) { idx in
                        let row = contestableRows[idx]
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text((row.chargeType ?? "Demurrage").capitalized).font(.headline)
                                Text("Shipment \(row.shipmentId.map(String.init) ?? "—") · \(row.status ?? "—") · \(row.chargeableDays ?? 0)d").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(money(row.amount)).font(.subheadline.weight(.bold)).monospacedDigit()
                            Button(disputeInFlight == row.id ? "Filing…" : "Dispute") {
                                Task { await dispute(row) }
                            }
                            .disabled(disputeInFlight != nil)
                        }
                    }
                }
            }
            .navigationTitle("Dispute Queue")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showDisputeQueue = false } } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · DEMURRAGE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(windowLabel).font(.system(size: 9, weight: .heavy)).tracking(1.0).monospaced().foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("D&D Analytics").font(.system(size: 28, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(rows.count) charge\(rows.count == 1 ? "" : "s")").font(.system(size: 11)).monospaced().foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var summaryBand: some View {
        ActiveCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(money(total)).font(.system(size: 30, weight: .heavy)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text("demurrage & detention · \(months.count) month\(months.count == 1 ? "" : "s") · \(totalDays) days").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Text("\(avgRateLabel)across \(rows.count) charge\(rows.count == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("AVOIDABLE").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text(money(avoidable)).font(.system(size: 20, weight: .bold)).monospacedDigit().foregroundStyle(Brand.warning)
                    Text("\(total > 0 ? Int((avoidable / total * 100).rounded()) : 0)% recoverable").font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("6-MONTH TREND · baseline vs avoidable").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    legend(Color(hex: 0xB0BAC6), "baseline"); legend(Brand.warning, "avoidable"); Spacer()
                }
                ColumnChart772(months: months, baselineColor: Color(hex: 0xB0BAC6), avoidColor: Brand.warning,
                            grid: palette.textPrimary.opacity(0.06), axisInk: palette.textTertiary, highlightLast: true)
                    .frame(height: 150)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private var causeCard: some View {
        let maxV = max(1, causes.map { $0.usd }.max() ?? 1)
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("BY CHARGE TYPE · financial summary").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 14) {
                ForEach(causes) { c in
                    VStack(spacing: 6) {
                        HStack {
                            Circle().fill(c.color).frame(width: 8, height: 8)
                            Text(c.label).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(money(c.usd)).font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.textPrimary.opacity(0.06)).frame(height: 6)
                                Capsule().fill(c.color).frame(width: CGFloat(c.usd / maxV) * geo.size.width, height: 6)
                            }
                        }.frame(height: 6)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private var esang: some View {
        HStack(spacing: 12) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(money(avoidable)) of D&D is disputable").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                // Derived from the decoded rows only — no fabricated port/tactic advice.
                Text("\(disputedCount) disputed · \(waivedCount) waived in this window").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private var totalDays: Int { rows.reduce(0) { $0 + ($1.chargeableDays ?? 0) } }

    // MARK: - Aggregation (client-side over the real rows)

    private static func monthKey(_ iso: String?) -> (order: Int, label: String)? {
        guard let s = iso, let d = ISO8601DateFormatter().date(from: s) ?? ISO8601DateFormatter().date(from: (s) + "T00:00:00Z") else { return nil }
        let comp = Calendar.current.dateComponents([.year, .month], from: d)
        let f = DateFormatter(); f.dateFormat = "MMM"
        return ((comp.year ?? 0) * 12 + (comp.month ?? 0), f.string(from: d))
    }
    private static func bucketByMonth(_ rows: [DemurrageRow772]) -> [MonthBucket772] {
        var map: [Int: (label: String, base: Double, avoid: Double)] = [:]
        for r in rows {
            guard let k = monthKey(r.startDate) else { continue }
            var e = map[k.order] ?? (k.label, 0, 0)
            if r.isAvoidable { e.avoid += r.amount } else { e.base += r.amount }
            e.label = k.label; map[k.order] = e
        }
        let ordered = map.keys.sorted().suffix(6)
        return ordered.map { MonthBucket772(label: map[$0]!.label, baseline: map[$0]!.base, avoidable: map[$0]!.avoid) }
    }
    private static func bucketByCause(_ rows: [DemurrageRow772]) -> [CauseBucket772] {
        let chartPalette: [Color] = [Brand.danger, Brand.warning, Brand.info, Color(hex: 0x607D8B)]
        var map: [String: Double] = [:]
        for r in rows { let key = (r.chargeType ?? "other").capitalized; map[key, default: 0] += r.amount }
        let sorted = map.sorted { $0.value > $1.value }.prefix(4)
        return sorted.enumerated().map { CauseBucket772(label: $0.element.key, usd: $0.element.value, color: chartPalette[$0.offset % chartPalette.count]) }
    }

    private func money(_ v: Double) -> String {
        if v >= 1000 { return "$" + String(format: "%.1fK", v / 1000) }
        return "$" + String(format: "%.0f", v)
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10); Text(t).font(.system(size: 9)).foregroundStyle(palette.textSecondary) }
    }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same gradient-outline grammar the
    /// registered siblings (680/757) use, on RoundedRectangle(Radius.md) per the
    /// app-wide button standard (no capsules).
    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let fs: FinancialSummary772 = try await EusoTripAPI.shared.query("vesselShipments.getVesselFinancialSummary", input: EmptyInput772())
            self.rows = fs.demurrage
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func openDisputeQueue() async {
        actionMessage = nil; actionError = nil
        guard !contestableRows.isEmpty else {
            actionError = "No accruing or invoiced demurrage charges are contestable."
            return
        }
        showDisputeQueue = true
    }

    private func dispute(_ row: DemurrageRow772) async {
        guard let shipmentId = row.shipmentId else {
            actionError = "This charge has no shipment id to dispute."
            return
        }
        actionMessage = nil; actionError = nil; disputeInFlight = row.id
        defer { disputeInFlight = nil }
        do {
            let out: ActionOut772 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.disputeVesselDemurrage",
                input: DisputeInput772(shipmentId: shipmentId,
                                       demurrageId: row.id,
                                       reason: "Disputed from vessel demurrage analytics.")
            )
            actionMessage = "Filed \(out.disputed ?? 1) demurrage dispute\(out.disputed == 1 ? "" : "s")."
            showDisputeQueue = false
            await load()
        } catch {
            actionError = error.eusoUserCopy
        }
    }

    private func exportSummary() async {
        actionMessage = nil; actionError = nil
        do {
            let out: ExportOut772 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.exportVesselDemurrageAnalytics",
                input: ExportInput772(format: "csv")
            )
            actionMessage = "Export ready · \(out.rowCount ?? 0) rows · \(out.exportedAt.map(shortDateTime) ?? "recorded")"
        } catch {
            actionError = error.eusoUserCopy
        }
    }

    private func shortDateTime(_ iso: String) -> String {
        guard iso.count >= 16 else { return iso }
        return String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}

// MARK: - Stacked column chart (baseline + avoidable; computed from buckets)

private struct ColumnChart772: View {
    let months: [MonthBucket772]
    let baselineColor: Color; let avoidColor: Color
    let grid: Color; let axisInk: Color
    let highlightLast: Bool
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let plotLeft: CGFloat = 30, plotBottom = h - 16, plotTop: CGFloat = 6
            let maxV = max(1, months.map { $0.total }.max() ?? 1)
            let n = max(1, months.count)
            let slot = (w - plotLeft) / CGFloat(n)
            let barW = min(30, slot * 0.6)
            let y: (Double) -> CGFloat = { v in plotBottom - CGFloat(v / maxV) * (plotBottom - plotTop) }
            ZStack(alignment: .topLeading) {
                // gridlines at 50% / 100%
                ForEach([0.5, 1.0], id: \.self) { f in
                    let gy = y(maxV * f)
                    Path { p in p.move(to: CGPoint(x: plotLeft, y: gy)); p.addLine(to: CGPoint(x: w, y: gy)) }.stroke(grid, lineWidth: 1)
                    Text("$\(Int((maxV * f) / 1000))K").font(.system(size: 8)).foregroundStyle(axisInk).position(x: 14, y: gy)
                }
                Path { p in p.move(to: CGPoint(x: plotLeft, y: plotBottom)); p.addLine(to: CGPoint(x: w, y: plotBottom)) }.stroke(axisInk.opacity(0.5), lineWidth: 1)
                ForEach(Array(months.enumerated()), id: \.element.id) { idx, m in
                    let cx = plotLeft + slot * CGFloat(idx) + slot / 2
                    let isLast = highlightLast && idx == months.count - 1
                    // baseline
                    RoundedRectangle(cornerRadius: 3).fill(isLast ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(baselineColor))
                        .frame(width: barW, height: max(0, plotBottom - y(m.baseline)))
                        .position(x: cx, y: (plotBottom + y(m.baseline)) / 2)
                    // avoidable (stacked on top)
                    RoundedRectangle(cornerRadius: 3).fill(avoidColor)
                        .frame(width: barW, height: max(0, y(m.baseline) - y(m.total)))
                        .position(x: cx, y: (y(m.baseline) + y(m.total)) / 2)
                    Text(m.label).font(.system(size: 9, weight: isLast ? .bold : .regular))
                        .foregroundStyle(axisInk)
                        .position(x: cx, y: plotBottom + 9)
                }
            }
        }
    }
}

#Preview("772 · Vessel Demurrage Analytics · Night") { VesselDemurrageAnalyticsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("772 · Vessel Demurrage Analytics · Light") { VesselDemurrageAnalyticsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
