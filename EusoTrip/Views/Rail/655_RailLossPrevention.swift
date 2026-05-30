//
//  655_RailLossPrevention.swift
//  EusoTrip — Rail Engineer · Loss Prevention.
//
//  Verbatim port of "655 Rail Loss Prevention · Dark" (05 Rail).
//  CARRIER-SIDE intermodal-parity gap-fill. Built to the flagship DETAIL
//  grammar (645 Rail Detention Dashboard / 02 Shipper 205): back-chevron +
//  eyebrow + mono caption + title 28/-0.4; gradient-rimmed (cardRim+inset)
//  hero ActiveCard with lead figure + progress; 3-cell KPI strip; itemized
//  ListRow stack (40x40 icon chip + title + mono sub + short status pill +
//  right tabular value); context strip; CTA pair.
//
//  Live tRPC anchors (grep-confirmed, frontend/server/routers/freightClaims.ts):
//    freightClaims.getLossPreventionDashboard  :988  — hero + KPI strip + prevention strip
//    freightClaims.getLossPreventionAnalysis   :1051 — hotspots ListRow stack
//    freightClaims.getClaimsAnalytics          :1160 — (analysis surface · CTA)
//
//  Charts/list plot LIVE data only — empty state when the series is absent,
//  never fabricated.
//

import SwiftUI

struct RailLossPreventionScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailLossPreventionBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror freightClaims.ts response objects)

private struct LossPreventionDashboard: Decodable {
    struct Metrics: Decodable {
        let totalLosses: Int?
        let lossValue: Double?
        let preventedLosses: Int?
        let preventionSavings: Double?
        let lossRatio: Double?
        let trendDirection: String?
    }
    struct Alert: Decodable, Identifiable {
        let id: String
        let severity: String?
        let message: String?
        let lane: String?
        let createdAt: String?
    }
    struct RiskLane: Decodable, Identifiable {
        let lane: String
        let lossCount: Int?
        let totalValue: Double?
        let riskScore: Double?
        var id: String { lane }
    }
    let metrics: Metrics?
    let alerts: [Alert]?
    let topRiskLanes: [RiskLane]?
}

private struct LossPreventionAnalysis: Decodable {
    struct Row: Decodable, Identifiable {
        let group: String
        let claimCount: Int?
        let totalValue: Double?
        let avgValue: Double?
        let trend: String?
        var id: String { group }
    }
    let groupBy: String?
    let period: String?
    let data: [Row]?
    let recommendations: [String]?
}

// MARK: - Body

private struct RailLossPreventionBody: View {
    @Environment(\.palette) private var palette
    @State private var dashboard: LossPreventionDashboard? = nil
    @State private var analysis: LossPreventionAnalysis? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Derived metric strings (LIVE only — empty when the series is absent).
    private var lossValue: Double { dashboard?.metrics?.lossValue ?? 0 }
    private var lossRatioPct: Double { (dashboard?.metrics?.lossRatio ?? 0) * 100 }
    private var hotspotCount: Int { dashboard?.topRiskLanes?.count ?? 0 }
    private var trendDirection: String { dashboard?.metrics?.trendDirection ?? "stable" }

    private func currencyCompact(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if v >= 1_000     { return String(format: "$%.0fK", v / 1_000) }
        return String(format: "$%.0f", v)
    }
    private func currencyFull(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let n = f.string(from: NSNumber(value: v)) ?? "0"
        return "$\(n)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                titleBlock
                IridescentHairline()
                    .padding(.top, Space.s3)

                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.top, Space.s4)
                } else {
                    heroCard
                        .padding(.top, Space.s4)
                    kpiStrip
                        .padding(.top, Space.s3)
                    hotspotsSection
                        .padding(.top, Space.s4)
                    preventionStrip
                        .padding(.top, Space.s4)
                    ctaPair
                        .padding(.top, Space.s5)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow (sparkle once · 12 MO mono)

    private var eyebrow: some View {
        HStack {
            Text("✦ RAIL ENGINEER · LOSS PREVENTION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("12 MO")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title block (back-chevron + title 28/-0.4 · BNSF caption)

    private var titleBlock: some View {
        HStack(alignment: .top) {
            HStack(alignment: .center, spacing: Space.s2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Loss prevention")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("BNSF")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("12-month window")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.top, Space.s4)
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 72)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
        .padding(.top, Space.s4)
    }

    // MARK: - Hero (gradient-rimmed ActiveCard · lead figure + progress)

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 0) {
                // Chip row: window + delta trend.
                HStack(spacing: Space.s2) {
                    Text("12 mo")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color.white.opacity(0.08)).clipShape(Capsule())
                    Text(trendChipLabel)
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Brand.success)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Brand.success.opacity(0.22)).clipShape(Capsule())
                    Spacer()
                }

                // Lead figure + caption block + right RATIO column.
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currencyFull(lossValue))
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                        Text("claims paid · 12 mo")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(String(format: "loss ratio %.1f%% · %@", lossRatioPct, trendCaption))
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("RATIO")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(String(format: "%.1f%%", lossRatioPct))
                            .font(EType.mono(.body)).tracking(0.2)
                            .foregroundStyle(Brand.success)
                    }
                }
                .padding(.top, Space.s4)

                // Progress hairline — loss ratio as a fraction of a 10% ceiling
                // (LIVE: zero-width when the ratio is 0).
                GeometryReader { geo in
                    let frac = min(max(lossRatioPct / 10.0, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: geo.size.width * frac)
                    }
                }
                .frame(height: 6)
                .padding(.top, Space.s4)
            }
        }
    }

    private var trendChipLabel: String {
        switch trendDirection.lowercased() {
        case "improving": return "improving"
        case "worsening": return "worsening"
        default:          return "stable"
        }
    }
    private var trendCaption: String {
        switch trendDirection.lowercased() {
        case "improving": return "trending down"
        case "worsening": return "trending up"
        default:          return "stable"
        }
    }

    // MARK: - KPI strip (3-cell · cell-1 eusoDiagonal)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // Cell 1 — PAID, gradient fill (eusoDiagonal).
            VStack(alignment: .leading, spacing: 6) {
                Text("PAID")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text(currencyCompact(lossValue))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white).monospacedDigit()
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            MetricTile(label: "LOSS RATIO",
                       value: String(format: "%.1f%%", lossRatioPct),
                       accent: Brand.success)
            MetricTile(label: "HOTSPOTS",
                       value: "\(hotspotCount)",
                       accent: hotspotCount > 0 ? Brand.warning : nil)
        }
    }

    // MARK: - Hotspots (itemized ListRow stack · LIVE analysis.data)

    private var hotspotsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("HOTSPOTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getLossPreventionAnalysis:1051")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            let rows = analysis?.data ?? []
            if rows.isEmpty {
                EusoEmptyState(systemImage: "exclamationmark.triangle",
                               title: "No hotspots",
                               subtitle: "Loss-prevention hotspots will appear here once the analysis is computed.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        hotspotRow(row)
                        if idx < rows.count - 1 {
                            Divider().overlay(palette.borderFaint)
                        }
                    }
                    HStack {
                        Text("+ root-cause tagging · corrective actions open per hotspot")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func hotspotRow(_ row: LossPreventionAnalysis.Row) -> some View {
        let kind = hotspotKind(row.trend)
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(kind.color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: kind.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(kind.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.group)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(hotspotSubtitle(row))
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(kind.label)
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(kind.color)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(kind.color.opacity(0.18)).clipShape(Capsule())
                Text(currencyFull(row.totalValue ?? 0))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(kind.valueIsNeutral ? palette.textPrimary : kind.color)
                    .monospacedDigit()
            }
        }
        .padding(Space.s4)
    }

    private func hotspotSubtitle(_ row: LossPreventionAnalysis.Row) -> String {
        let n = row.claimCount ?? 0
        if let t = row.trend, !t.isEmpty, ["improving", "stable", "worsening"].contains(t.lowercased()) {
            return n == 1 ? "1 claim · \(t.lowercased())" : "\(n) claims · \(t.lowercased())"
        }
        return n == 1 ? "1 claim" : "\(n) claims"
    }

    private struct HotspotKind {
        let label: String
        let icon: String
        let color: Color
        let valueIsNeutral: Bool
    }
    private func hotspotKind(_ trend: String?) -> HotspotKind {
        switch (trend ?? "").lowercased() {
        case "worsening", "rising", "hotspot":
            return HotspotKind(label: "HOTSPOT", icon: "exclamationmark.triangle.fill", color: Brand.danger, valueIsNeutral: false)
        case "watch", "elevated":
            return HotspotKind(label: "WATCH", icon: "thermometer.medium", color: Brand.warning, valueIsNeutral: false)
        case "improving", "stable":
            return HotspotKind(label: "STABLE", icon: "shippingbox", color: Brand.info, valueIsNeutral: true)
        default:
            return HotspotKind(label: "WATCH", icon: "exclamationmark.triangle.fill", color: Brand.warning, valueIsNeutral: false)
        }
    }

    // MARK: - Prevention strip (context · getLossPreventionDashboard)

    private var preventionStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text("PREVENTION · getLossPreventionDashboard")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("12 mo")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("root-cause tagging · corrective actions tracked to close")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("Carrier BNSF Intermodal · Eusorone Technologies (DU) · LP program v2")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "View actions", action: {})
                .frame(maxWidth: .infinity)
            Button(action: {}) {
                Text("Analysis")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgSecondary)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct AnalysisIn: Encodable { let groupBy: String; let period: String }
        do {
            async let dash: LossPreventionDashboard =
                EusoTripAPI.shared.queryNoInput("freightClaims.getLossPreventionDashboard")
            async let anl: LossPreventionAnalysis =
                EusoTripAPI.shared.query("freightClaims.getLossPreventionAnalysis",
                                         input: AnalysisIn(groupBy: "lane", period: "year"))
            let (d, a) = try await (dash, anl)
            self.dashboard = d
            self.analysis = a
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("655 · Rail Loss Prevention · Night") { RailLossPreventionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("655 · Rail Loss Prevention · Light") { RailLossPreventionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
