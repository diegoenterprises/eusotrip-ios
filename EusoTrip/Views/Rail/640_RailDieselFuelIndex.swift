//
//  640_RailDieselFuelIndex.swift
//  EusoTrip — Rail Engineer · Diesel Fuel Index (price-index surface).
//
//  Verbatim port of "640 Rail Diesel Fuel Index.svg" (Dark).
//  CARRIER-SIDE (RAIL_ENGINEER vantage). An INDEX surface that leads with an
//  8-week trend sparkline chart hero (not money rows), then an FSC-peg
//  conversion band and a PADD regional rate table — 640 reads unmistakably
//  as a price index, not a stat-card ledger.
//
//  PURPOSE: give the engineer the live #2 ULSD diesel index, its 8-week
//  trend, the per-mile FSC peg ESang reads, and the regional PADD breakdown —
//  the basis for every fuel surcharge on the lane.
//
//  WIRING (web parity /rail/fuel/index · client/src/pages/rail/DieselIndex.tsx):
//    national index + PADD rows → fuelSurchargeIndex.currentDieselIndex
//        EXISTS · fuelSurchargeIndex.ts:56
//        returns { source, weekOf, nationalAverage, padd1..padd5, note }
//        (the server's source string is surfaced verbatim in the footnote so
//         a mock feed can never masquerade as live EIA data)
//    FSC peg → fscEngine.getSchedules  EXISTS · fscEngine.ts:27
//        returns { schedules: [{ basePrice, cpmRate, method, isActive, … }] }
//        — the peg band binds to the company's active cpm schedule. LIVE OR
//        EM-DASH: an ESANG READS label NEVER sits on a hardcoded number.
//    8-week trend series → fscEngine.getFSCHistory  EXISTS · fscEngine.ts:333
//        requires a scheduleId — now bound via the resolved schedule above;
//        when no schedule/history exists the chart renders its honest empty.
//    Update prices write → fscEngine.updatePaddPrices  EXISTS · fscEngine.ts:172
//        (mutation; writes fscIndex rows + blockchainAuditTrail; broadcasts
//         WS_CHANNELS.PRICING / WS_EVENTS.FSC_UPDATED)
//
//  RBAC railProcedure (RAIL_ENGINEER|CATALYST). transportMode=rail · US
//  (USD · EIA #2 ULSD). NAV: HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//

import SwiftUI

struct RailDieselFuelIndexScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailDieselFuelIndexBody() } nav: {
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

/// `fuelSurchargeIndex.currentDieselIndex` — national EIA #2 ULSD average +
/// the five PADD regional retail figures, in one call. All fields optional so
/// a partial server payload still decodes instead of throwing.
private struct DieselIndex640: Decodable {
    let source: String?
    let weekOf: String?
    let nationalAverage: Double?
    let padd1: Double?
    let padd2: Double?
    let padd3: Double?
    let padd4: Double?
    let padd5: Double?
    let note: String?
}

/// `fscEngine.getFSCHistory` — historical PADD + FSC trend for a schedule.
/// Series points carry the date + the PADD diesel price we plot.
private struct FscHistory640: Decodable {
    struct Point: Decodable, Identifiable {
        let date: String?
        let paddPrice: Double?
        let calculatedFsc: Double?
        var id: String { date ?? UUID().uuidString }
    }
    let scheduleName: String?
    let paddRegion: String?
    let history: [Point]?
}

/// A decimal column that MySQL/drizzle serializes as either a JSON number or
/// a "1.2500"-style string — decode both, silently fail to nil on neither.
private struct FlexDouble640: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
}

/// One fsc_schedules row from `fscEngine.getSchedules` (raw drizzle select).
private struct FscSchedule640: Decodable {
    let id: Int
    let scheduleName: String?
    let method: String?
    let basePrice: FlexDouble640?
    let cpmRate: FlexDouble640?
    let isActive: Int?
}
private struct FscSchedulesPage640: Decodable {
    let schedules: [FscSchedule640]?
}

// MARK: - Body

private struct RailDieselFuelIndexBody: View {
    @Environment(\.palette) private var palette

    @State private var index: DieselIndex640? = nil
    @State private var series: [Double] = []          // 8-week price series (real, may be empty)
    @State private var seriesDates: [String] = []     // matching x-axis labels
    /// The company's active cpm FSC schedule — the LIVE source of the peg
    /// band. nil → every peg figure renders as an em-dash.
    @State private var pegSchedule: FscSchedule640? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isUpdating = false

    // MARK: Derived

    private var heroPriceLabel: String {
        index?.nationalAverage.map { String(format: "$%.2f", $0) } ?? "—"
    }
    /// Live FSC peg ($/mi) from the active cpm schedule — em-dash otherwise.
    private var pegRateLabel: String {
        pegSchedule?.cpmRate?.value.map { String(format: "$%.2f", $0) } ?? "—"
    }
    /// Live peg base diesel price from the schedule — em-dash otherwise.
    private var pegBaseLabel: String {
        pegSchedule?.basePrice?.value.map { String(format: "$%.2f", $0) } ?? "—"
    }
    /// Hi / lo across the live 8-week series when present.
    private var hiLoLabel: String {
        guard let hi = series.max(), let lo = series.min(), !series.isEmpty else { return "" }
        return String(format: "hi $%.2f · lo $%.2f", hi, lo)
    }
    private var startTick: String { seriesDates.first ?? "" }
    private var midTick: String {
        seriesDates.isEmpty ? "" : seriesDates[seriesDates.count / 2]
    }
    private var endTick: String { seriesDates.last ?? "" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard {
                        Text("Loading diesel index…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    heroFigure
                    IridescentHairline()
                    trendCard
                    fscPegBand
                    paddTable
                    footnote
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s2)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Header (eyebrow + caption + breadcrumb)

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("RAIL ENGINEER · FUEL INDEX")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("ULSD · EIA")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 8) {
                Text("Pricing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: - Hero figure + subline

    private var heroFigure: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(heroPriceLabel)
                    .font(.system(size: 32, weight: .bold)).kerning(-0.6)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("/gal")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            // Peg suffix is LIVE (active cpm schedule) or an em-dash — never a
            // hardcoded figure.
            Text("EIA #2 ULSD natl avg · FSC peg \(pegRateLabel)/mi")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Trend sparkline hero card

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("8-WEEK INDEX · #2 ULSD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if !hiLoLabel.isEmpty {
                    Text(hiLoLabel)
                        .font(.system(size: 11, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Brand.success)
                }
            }
            if series.count >= 2 {
                trendChart
                    .frame(height: 78)
                    .padding(.top, 14)
                HStack {
                    Text(startTick)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(midTick)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(endTick)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.top, 6)
            } else {
                // Honest empty: the series is schedule-bound (fscEngine.
                // getFSCHistory via the resolved peg schedule) and no real
                // history rows exist yet — never fabricated chart points.
                trendEmpty
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    /// Real chart geometry: area fill (sparkArea gradient) + brand line +
    /// current marker, plotted from the LIVE 8-week price series.
    private var trendChart: some View {
        GeometryReader { geo in
            let pts = normalized(series)
            let w = geo.size.width
            let h = geo.size.height
            let stepX: CGFloat = pts.count > 1 ? w / CGFloat(pts.count - 1) : w
            let xAt: (Int) -> CGFloat = { i in stepX * CGFloat(i) }
            let yAt: (CGFloat) -> CGFloat = { v in h * (1 - v) }

            ZStack {
                // Baseline + dashed guide (matches SVG hairlines)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: w, y: h))
                }
                .stroke(palette.borderFaint, lineWidth: 1)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.5))
                    p.addLine(to: CGPoint(x: w, y: h * 0.5))
                }
                .stroke(Color.white.opacity(0.04),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

                // Area fill under the line
                Path { p in
                    guard pts.count >= 2 else { return }
                    p.move(to: CGPoint(x: 0, y: yAt(pts[0])))
                    for i in 1..<pts.count { p.addLine(to: CGPoint(x: xAt(i), y: yAt(pts[i]))) }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [Brand.blue.opacity(0.22), Brand.magenta.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom))

                // Trend line
                Path { p in
                    guard pts.count >= 2 else { return }
                    p.move(to: CGPoint(x: 0, y: yAt(pts[0])))
                    for i in 1..<pts.count { p.addLine(to: CGPoint(x: xAt(i), y: yAt(pts[i]))) }
                }
                .stroke(LinearGradient.primary,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                // Current marker (last point)
                if let last = pts.last {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                        .position(x: xAt(pts.count - 1), y: yAt(last))
                }
            }
        }
    }

    private var trendEmpty: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("Trend series pending")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("The 8-week index trend appears once the PADD history feed is live.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s5)
    }

    // MARK: - FSC peg conversion band

    private var fscPegBand: some View {
        // ZERO-FALLBACK: an "ESANG READS" label may never sit on a hardcoded
        // number. The peg binds to the company's active cpm FSC schedule
        // (fscEngine.getSchedules → basePrice + cpmRate) or renders em-dashes.
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FSC PEG · ESANG READS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.85))
                Text(pegSchedule != nil
                     ? "\(pegRateLabel) / mi over \(pegBaseLabel) base diesel"
                     : "— / mi · no active FSC schedule on file")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Text(pegRateLabel)
                .font(.system(size: 26, weight: .bold)).monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - PADD regional rate table

    private var paddTable: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("PADD REGIONS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("$/gal · day delta")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(paddRows.enumerated()), id: \.element.id) { idx, row in
                    paddRow(row)
                    if idx < paddRows.count - 1 {
                        Divider().padding(.leading, 68).overlay(palette.borderFaint)
                    }
                }
            }
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
        }
    }

    private struct PaddRow: Identifiable {
        let id: String
        let title: String
        let detail: String
        let wow: String
        let wowUp: Bool
        let price: Double?
        let carb: Bool   // West-coast CARB diesel reads green (down day)
    }

    /// Rows are driven by the LIVE PADD figures returned by
    /// `currentDieselIndex`. WIRE-GAP: the endpoint returns the weekly spot
    /// price only — no per-region day/WoW deltas exist anywhere on the
    /// server, so no delta chip is rendered (zero-fallback: a fabricated
    /// "+1.3% WoW" is worse than no chip).
    private var paddRows: [PaddRow] {
        let week = index?.weekOf.map { "week of \($0)" } ?? "—"
        return [
            PaddRow(id: "1", title: "PADD 1 · East Coast", detail: week,
                    wow: "", wowUp: false, price: index?.padd1, carb: false),
            PaddRow(id: "3", title: "PADD 3 · Gulf Coast", detail: week,
                    wow: "", wowUp: false, price: index?.padd3, carb: false),
            PaddRow(id: "5", title: "PADD 5 · West Coast", detail: "\(week) · CARB diesel",
                    wow: "", wowUp: false, price: index?.padd5, carb: true),
        ]
    }

    private func paddRow(_ row: PaddRow) -> some View {
        let glyphTint: Color = row.carb ? Brand.success : Brand.hazmat
        let chipColor: Color = row.wowUp ? Brand.warning : Brand.success
        let priceStr: String = row.price.map { String(format: "$%.2f", $0) } ?? "—"
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(glyphTint.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "drop.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(glyphTint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(row.detail)
                    .font(.system(size: 11, design: .monospaced)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                // Delta chip renders ONLY when a real delta exists (WIRE-GAP:
                // none does today — the index returns weekly spot only).
                if !row.wow.isEmpty {
                    Text(row.wow)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(chipColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(chipColor.opacity(0.16)))
                }
                Text(priceStr)
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    // MARK: - Footnote

    private var footnote: some View {
        // The server's own source string is surfaced verbatim — if the feed
        // is a mock, the screen says so instead of dressing it up as EIA.
        Text("source: \(index?.source ?? "—") · day/WoW deltas pending (spot only)")
            .font(.system(size: 10))
            .foregroundStyle(palette.textTertiary)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Update prices",
                      action: { Task { await updatePrices() } },
                      isLoading: isUpdating)
            RailSecondaryActionButton(
                title: "History",
                sheetTitle: "Diesel index history",
                lines: dieselHistoryLines,
                systemImage: "chart.xyaxis.line"
            )
        }
    }

    private var dieselHistoryLines: [String] {
        var lines = [
            "Source \(index?.source ?? "pending")",
            "Week \(index?.weekOf ?? "pending") · national \(heroPriceLabel)",
            "FSC peg \(pegRateLabel)/mi over \(pegBaseLabel) base"
        ]
        if !hiLoLabel.isEmpty { lines.append(hiLoLabel) }
        if !seriesDates.isEmpty {
            lines.append("Series \(startTick) → \(endTick) · \(series.count) live point\(series.count == 1 ? "" : "s")")
        }
        return lines
    }

    // MARK: - Chart helpers

    private func normalized(_ vs: [Double]) -> [CGFloat] {
        guard let lo = vs.min(), let hi = vs.max(), hi > lo else {
            return vs.map { _ in 0.5 }
        }
        return vs.map { CGFloat(($0 - lo) / (hi - lo)) }
    }

    // MARK: - Load / Actions

    private func reload() async {
        loading = true; loadError = nil
        struct EmptyIn: Encodable {}
        do {
            let idx: DieselIndex640 = try await EusoTripAPI.shared.query(
                "fuelSurchargeIndex.currentDieselIndex", input: EmptyIn())
            self.index = idx
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        // FSC peg — bind to the company's active cpm schedule. Best-effort:
        // a failed read leaves the peg band at its honest em-dash state.
        self.pegSchedule = nil
        do {
            let page: FscSchedulesPage640 = try await EusoTripAPI.shared.query(
                "fscEngine.getSchedules", input: EmptyIn())
            let rows = page.schedules ?? []
            self.pegSchedule = rows.first(where: {
                ($0.method ?? "") == "cpm" && ($0.isActive ?? 0) == 1 && $0.cpmRate?.value != nil
            }) ?? rows.first(where: { $0.cpmRate?.value != nil })
        } catch {
            // Honest em-dash peg; the index error (if any) is already surfaced.
        }

        // 8-week trend series — now schedule-bound via the resolved peg
        // schedule. Real history points only; otherwise the chart keeps its
        // honest empty state.
        self.series = []
        self.seriesDates = []
        if let sid = pegSchedule?.id {
            struct HistIn: Encodable { let scheduleId: Int }
            do {
                let hist: FscHistory640 = try await EusoTripAPI.shared.query(
                    "fscEngine.getFSCHistory", input: HistIn(scheduleId: sid))
                let aligned = (hist.history ?? []).suffix(8).compactMap { p -> (Double, String)? in
                    guard let v = p.paddPrice, let d = p.date else { return nil }
                    return (v, String(d.prefix(10)))
                }
                self.series = aligned.map(\.0)
                self.seriesDates = aligned.map(\.1)
            } catch {
                // No history rows yet — honest empty chart.
            }
        }
        loading = false
    }

    private func updatePrices() async {
        isUpdating = true
        struct EmptyIn: Encodable {}
        struct UpdateOut: Decodable { let updatedCount: Int? }
        do {
            // fscEngine.updatePaddPrices — writes fscIndex rows + audit trail,
            // broadcasts WS_EVENTS.FSC_UPDATED.
            let _: UpdateOut = try await EusoTripAPI.shared.mutation(
                "fscEngine.updatePaddPrices", input: EmptyIn())
            await reload()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        isUpdating = false
    }
}

#Preview("640 · Rail Diesel Fuel Index · Night") { RailDieselFuelIndexScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("640 · Rail Diesel Fuel Index · Light") { RailDieselFuelIndexScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
