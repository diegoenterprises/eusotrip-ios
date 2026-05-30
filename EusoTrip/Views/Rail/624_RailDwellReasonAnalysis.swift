//
//  624_RailDwellReasonAnalysis.swift
//  EusoTrip — Rail Engineer · Dwell Reason Analysis (carrier-side root-cause
//  demurrage analytics over a 30-day window).
//
//  Verbatim port of wireframe "624 Rail Dwell Reason Analysis · Dark".
//  Flagship DETAIL grammar (621 Rail Yard Move Queue / 609 Rail Reefer
//  Monitoring / 02 Shipper 205): back chevron + eyebrow + mono caption +
//  title 28/-0.4, gradient-rimmed hero ActiveCard, 3-cell KPI strip
//  (cell-1 eusoDiagonal), itemized ListRow stack, context strip, and an
//  Export report / Charge log CTA pair.
//
//  Wired to railDemurrageAuto.reportByDwellReason (grep-confirmed in-repo:
//  frontend/server/routers/railDemurrageAuto.ts → reportByDwellReason).
//

import SwiftUI

struct RailDwellReasonAnalysisScreen: View {
    let theme: Theme.Palette
    /// 30-day default window — matches the server's `periodDays` default
    /// and the wireframe's "30-DAY" eyebrow. Defaulted so the screen's
    /// only required init param remains `theme`.
    var periodDays: Int = 30

    var body: some View {
        Shell(theme: theme) { RailDwellReasonAnalysisBody(periodDays: periodDays) } nav: {
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

// MARK: - Data shapes (railDemurrageAuto.reportByDwellReason)

/// One reason-code row from `reportByDwellReason`. Server contract:
///   { reason: string, count: number, totalCharges: number, avgHours: number }
private struct DwellReasonRow: Decodable, Identifiable {
    let reason: String
    let count: Int
    let totalCharges: Double
    let avgHours: Double
    var id: String { reason }
}

private struct DwellReasonReport: Decodable {
    let reasons: [DwellReasonRow]
}

// MARK: - Body

private struct RailDwellReasonAnalysisBody: View {
    @Environment(\.palette) private var palette
    let periodDays: Int

    @State private var reasons: [DwellReasonRow] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // Carrier-vantage rail-engineer surface; shipper-of-record Diego Usoro ·
    // Eusorone Technologies. Carrier label per wireframe. The carrier name +
    // exposure-id + sync caption are not returned by reportByDwellReason —
    // see // PORT-GAP markers below; kept as the verbatim wireframe labels.
    private let carrier = "BNSF INTERMODAL"

    // MARK: Derived aggregates (server returns only the per-reason rows)

    private var totalCharges: Double {
        reasons.reduce(into: 0.0) { acc, r in acc += r.totalCharges }
    }
    private var totalEvents: Int {
        reasons.reduce(into: 0) { acc, r in acc += r.count }
    }
    /// Charge-weighted mean "avg over free" across reason codes, rounded to
    /// a whole hour for the hero caption ("31h avg over").
    private var avgHoursOver: Int {
        guard totalEvents > 0 else { return 0 }
        let weighted = reasons.reduce(into: 0.0) { acc, r in acc += r.avgHours * Double(r.count) }
        return Int((weighted / Double(totalEvents)).rounded())
    }
    private var reasonCodeCount: Int { reasons.count }

    /// Reasons ranked by charges descending — the wireframe shows the
    /// itemized stack "BY CHARGES".
    private var rankedReasons: [DwellReasonRow] {
        reasons.sorted { $0.totalCharges > $1.totalCharges }
    }
    /// Top-3 ride the itemized ListRow stack; the remainder roll up into
    /// the "+ <reason> N events · …" footer line (verbatim wireframe).
    private var topReasons: [DwellReasonRow] { Array(rankedReasons.prefix(3)) }
    private var overflowReasons: [DwellReasonRow] {
        rankedReasons.count > 3 ? Array(rankedReasons.dropFirst(3)) : []
    }

    /// Hero progress fill — leading reason's share of total charges
    /// (223/360 ≈ 0.62 in the wireframe).
    private var leadShareFraction: CGFloat {
        guard totalCharges > 0, let lead = rankedReasons.first else { return 0 }
        return CGFloat(min(1.0, lead.totalCharges / totalCharges))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if reasons.isEmpty {
                    EusoEmptyState(systemImage: "chart.bar.doc.horizontal",
                                   title: "No dwell charges",
                                   subtitle: "Demurrage reason codes for this 30-day window will appear here once accruals post.")
                } else {
                    heroCard
                    kpiStrip
                    reasonCodesCard
                    trendStrip
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Header (eyebrow · back chevron · title · carrier caption)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow row — sparkle eyebrow once + right mono window tag.
            HStack {
                Text("✦ RAIL ENGINEER · DWELL ANALYSIS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("\(periodDays)-DAY")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            // Back chevron + title (28/-0.4) + carrier caption on the right.
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 6)
                Text("Dwell reasons")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(carrier)                            // PORT-GAP: carrier name not on reportByDwellReason
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("synced 1h ago")                    // PORT-GAP: sync timestamp not on reportByDwellReason
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.top, Space.s3)
        }
    }

    // MARK: - Hero ActiveCard (gradient-rimmed, root-cause demurrage)

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: Space.s2) {
                    // "root cause" neutral pill
                    Text("root cause")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    // "rising" danger pill
                    Text("rising")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Color(hex: 0xFF6B5E))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.danger.opacity(0.18)))
                    Spacer(minLength: 0)
                    // 30-day delta (PORT-GAP: prior-period comparison not on endpoint)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(periodDays) DAYS")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("+12%")                          // PORT-GAP: trend vs prior 30d not on reportByDwellReason
                            .font(EType.mono(.body)).tracking(0.2)
                            .foregroundStyle(Color(hex: 0xFF6B5E))
                    }
                }
                HStack(alignment: .center, spacing: Space.s4) {
                    Text(currencyShort(totalCharges))
                        .font(.system(size: 30, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("demurrage \(periodDays)d")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("\(totalEvents) events · \(avgHoursOver)h avg over")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                // Progress: leading reason's share of total charges.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: max(0, geo.size.width * leadShareFraction))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - KPI strip (3-cell; cell-1 eusoDiagonal)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            gradientKPICell(label: "EVENTS", value: "\(totalEvents)")
            plainKPICell(label: "AVG",   value: "\(avgHoursOver)h")
            plainKPICell(label: "CODES", value: "\(reasonCodeCount)")
        }
    }

    private func gradientKPICell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(.white.opacity(0.85))
            Text(value)
                .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func plainKPICell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Reason codes card (itemized ListRow stack)

    private var reasonCodesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("REASON CODES · BY CHARGES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(reasonCodeCount) codes")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s3)

            VStack(spacing: 0) {
                ForEach(Array(topReasons.enumerated()), id: \.element.id) { idx, row in
                    reasonRow(row)
                    if idx < topReasons.count - 1 {
                        Divider().background(palette.borderFaint)
                            .padding(.leading, 16 + 40 + 12)
                    }
                }
                if !overflowReasons.isEmpty {
                    Divider().background(palette.borderFaint)
                        .padding(.leading, 16 + 40 + 12)
                    overflowFooter
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func reasonRow(_ row: DwellReasonRow) -> some View {
        let accent = reasonAccent(row.reason)
        let pct = totalCharges > 0 ? Int((row.totalCharges / totalCharges * 100).rounded()) : 0
        return HStack(alignment: .center, spacing: Space.s3) {
            // 40x40 icon chip — warehouse-receipt glyph (rail dwell doc).
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(reasonTitle(row.reason))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(row.count) events · avg \(Int(row.avgHours.rounded()))h over free")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                // Short status pill — share-of-charges percentage.
                Text("\(pct)%")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.22)))
                // Right tabular value — charges.
                Text(currencyShort(row.totalCharges))
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private var overflowFooter: some View {
        // "+ Weather hold 15 events · avg 19h · $1.0k · 4 reason codes total"
        let extraLine: String = overflowReasons
            .map { "\(reasonTitle($0.reason)) \($0.count) events · avg \(Int($0.avgHours.rounded()))h · \(currencyShort($0.totalCharges))" }
            .joined(separator: " · ")
        return HStack {
            Text("+ \(extraLine) · \(reasonCodeCount) reason codes total")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - Trend context strip

    private var trendStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TREND · VS PRIOR \(periodDays) DAYS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(periodDays)-day")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
            }
            // PORT-GAP: prior-period delta + leading-driver narrative not on
            // reportByDwellReason; narrative derived from the ranked rows.
            Text("Total demurrage up 12% · \(leadReasonPhrase) the main driver")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("Eusorone Technologies (DU) · RAIL-260524-9C20A7E15B · \(currencyExact(totalCharges)) exposure")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var leadReasonPhrase: String {
        guard let lead = rankedReasons.first else { return "no single reason" }
        return reasonTitle(lead.reason).lowercased()
    }

    // MARK: - CTA pair (Export report / Charge log)

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Export report", action: {})
                .frame(maxWidth: .infinity)
            Button(action: {}) {
                Text("Charge log")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(hex: 0x232932))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - Loading skeleton

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 200)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Reason label / accent mapping (server reason snake_case)

    private func reasonTitle(_ raw: String) -> String {
        switch raw.lowercased() {
        case "yard_congestion":     return "Yard congestion"
        case "consignee_not_ready": return "Consignee not ready"
        case "no_power":            return "No power / chassis"
        case "weather":             return "Weather hold"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func reasonAccent(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "yard_congestion":     return Color(hex: 0xFF6B5E)  // danger
        case "consignee_not_ready": return Color(hex: 0xF5B544)  // warning
        case "no_power":            return Color(hex: 0x90A4AE)  // rail slate
        case "weather":             return Brand.info
        default:                    return Brand.neutral
        }
    }

    // MARK: - Currency formatting (compact $X.Xk + exact $X,XXX)

    private func currencyShort(_ v: Double) -> String {
        if v >= 1000 {
            let k = v / 1000
            return "$\(String(format: k.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", k))k"
        }
        return "$\(Int(v.rounded()))"
    }

    private func currencyExact(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let s = f.string(from: NSNumber(value: v)) ?? "\(Int(v.rounded()))"
        return "$\(s)"
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct ReportIn: Encodable { let periodDays: Int }
        do {
            let report: DwellReasonReport = try await EusoTripAPI.shared.query(
                "railDemurrageAuto.reportByDwellReason",
                input: ReportIn(periodDays: periodDays))
            // Drop zero-charge rows so the itemized stack only shows live
            // reason codes (the server seeds 4 zero-rows pre-wiring).
            self.reasons = report.reasons.filter { $0.count > 0 || $0.totalCharges > 0 }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("624 · Rail Dwell Reason Analysis · Night") {
    RailDwellReasonAnalysisScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("624 · Rail Dwell Reason Analysis · Light") {
    RailDwellReasonAnalysisScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
