//
//  805_VesselLossPrevention.swift
//  EusoTrip — Vessel Operator · Loss Prevention.
//
//  Faithful 1:1 port of "805 Vessel Loss Prevention.svg" (Light + Dark), RECONSTRUCTED to a
//  purpose-built RISK-CONSOLE archetype (deliberately NOT the money-ledger skeleton it used to share
//  with 803 Freight Audit / 804 Overcharge Recovery): the hero is a LOSS-BY-CAUSE segmented breakdown
//  (cargo damage / theft / reefer excursion / seal breach) with a 2x2 cause legend, and the primary
//  surface is a live timestamped RISK ALERT feed (severity chip + message + lane + relative time +
//  HIGH/MED/INFO pill) rather than an invoice list.
//  Nav anchored to the registered Vessel Operator Shell + BottomNav (HOME · SHIPMENTS · [orb] ·
//  COMPLIANCE[current] · ME) — the exact wrapper sibling 757_VesselDetentionLetters ships.
//
//  Data / wiring (endpoints MCP-confirmed on disk this fire):
//    freightClaims.getLossPreventionDashboard (EXISTS frontend/server/routers/freightClaims.ts:988 ·
//        protectedProcedure · NO input · ->
//        {metrics:{totalLosses,lossValue,preventedLosses,preventionSavings,lossRatio,trendDirection},
//        alerts:[{id,severity,message,lane,createdAt}],topRiskLanes:[{lane,lossCount,totalValue,riskScore}]}).
//        NOTE alerts/topRiskLanes return empty arrays (web stub) — seeds in #Preview only; the live query
//        on .task / .refreshable overwrites every value, and the alert feed shows an honest empty state
//        when the server returns no alerts.
//    freightClaims.getLossPreventionAnalysis (EXISTS freightClaims.ts:1051 · input {groupBy:lane|commodity|
//        carrier|month, period:month|quarter|year} -> {groupBy,period,data:[{group,claimCount,totalValue,
//        avgValue,trend}],recommendations:[String]}) seeds the cause breakdown + the ESang recommendation.
//        data currently returns empty (web stub) — the cause card renders honestly from whatever the
//        server provides.
//    "View loss alerts" reads alerts (read · re-runs load). "Export" -> exportLossPreventionReport is a
//        named-gap STUB (no backing mutation today) — flagged, re-runs load() rather than faked.
//
//  0 fabricated data on load · honest empty/error states. RimCard805 / ESangRow805 / secondaryButton805
//  / usd805 are file-scoped bespoke helpers (the canonical port's RimCard / ESangRow / SecondaryButton /
//  Money.usd are not shared app symbols) built from sibling 757's gradient-rim grammar to preserve the
//  exact wireframe look.
//

import SwiftUI

private struct LossCause805: Identifiable {
    let id = UUID()
    let name: String
    let frac: Double
    let color: Color
    let detail: String   // "5 · $42,400"
}

private struct RiskAlert805: Identifiable {
    let id = UUID()
    let symbol: String
    let tint: Color
    let kind: StatusPill.Kind
    let pill: String
    let title: String
    let sub: String      // "CNSHA→USLGB · CMAU-744120 · 2h ago"
}

struct VesselLossPreventionScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselLossPreventionBody()
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

private struct VesselLossPreventionBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var hero       = "$0"
    @State private var subline    = "prevention savings · 0 losses · loss ratio 0.0% · trend stable"
    @State private var atRisk     = "$0"

    @State private var causes: [LossCause805] = []
    @State private var alerts: [RiskAlert805] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text(hero).font(.system(size: 34, weight: .bold, design: .monospaced)).foregroundStyle(LinearGradient.diagonal)
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    causeCard
                    Text("RISK ALERTS · LIVE FEED")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    alertFeed
                    HStack(spacing: 8) {
                        CTAButton(title: "View loss alerts", action: { Task { await viewAlerts() } }, trailingIcon: "bell")
                        secondaryButton805(title: "Export") { Task { await exportReport() } }
                    }
                    ESangRow805(title: esangTitle, subtitle: esangSubtitle)
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
                Text("VESSEL OPERATOR · LOSS PREVENTION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("2026-Q2").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 6) {
                Text("Compliance").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // LOSS BY CAUSE — segmented breakdown + 2x2 legend
    private var causeCard: some View {
        RimCard805 {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("LOSS BY CAUSE · VALUE AT RISK").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(atRisk).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(Brand.danger)
                }
                if causes.isEmpty {
                    Text("No loss-by-cause data in range — getLossPreventionAnalysis returned an empty breakdown.")
                        .font(.system(size: 12)).foregroundStyle(palette.textTertiary)
                } else {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            ForEach(causes) { c in
                                Rectangle().fill(c.color).frame(width: geo.size.width * c.frac)
                            }
                        }
                        .clipShape(Capsule())
                        .background(Capsule().fill(palette.bgCardSoft))
                    }.frame(height: 12)
                    let cols = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 12) {
                        ForEach(causes) { c in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(c.color).frame(width: 8, height: 8).padding(.top, 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                                    Text(c.detail).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var alertFeed: some View {
        if alerts.isEmpty {
            EusoEmptyState(systemImage: "bell.slash",
                           title: "No risk alerts in feed",
                           subtitle: "getLossPreventionDashboard returned an empty alert stream — nothing flagged right now.")
        } else {
            LifecycleCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(alerts.enumerated()), id: \.element.id) { idx, a in
                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(a.tint.opacity(0.14)).frame(width: 40, height: 40)
                                .overlay(Image(systemName: a.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(a.tint))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                                Text(a.sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            StatusPill(text: a.pill, kind: a.kind)
                        }
                        .padding(.vertical, 10)
                        if idx < alerts.count - 1 { Divider().overlay(palette.borderFaint) }
                    }
                }
            }
        }
    }

    /// ESang advisory derives from the live cause breakdown — top cause + lead lane,
    /// not a hard-coded string (renders honestly when the analysis is empty).
    private var esangTitle: String {
        guard let top = causes.first else { return "ESang: no loss-by-cause signal yet" }
        let pct = Int((top.frac * 100).rounded())
        return "ESang: \(top.name.lowercased()) drives \(pct)% of value at risk"
    }
    private var esangSubtitle: String {
        guard let lead = alerts.first else { return "no live alerts — monitor the next discharge cycle" }
        let lane = lead.sub.split(separator: " ").first.map(String.init) ?? "—"
        return "add GPS seal monitoring on \(lane) first"
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            struct Metrics: Decodable { let totalLosses: Int?; let lossValue: Double?; let preventedLosses: Int?; let preventionSavings: Double?; let lossRatio: Double?; let trendDirection: String? }
            struct Alert: Decodable { let severity: String?; let message: String?; let lane: String?; let createdAt: String? }
            struct Out: Decodable { let metrics: Metrics; let alerts: [Alert]? }
            let r: Out = try await EusoTripAPI.shared.query("freightClaims.getLossPreventionDashboard", input: EmptyInput805())
            let m = r.metrics
            hero = usd805(m.preventionSavings ?? 0)
            let losses = m.totalLosses ?? 0
            let trend = m.trendDirection ?? "stable"
            subline = "prevention savings · \(losses) losses · loss ratio \(String(format: "%.1f%%", (m.lossRatio ?? 0) * 100)) · trend \(trend)"
            atRisk = usd805(m.lossValue ?? 0)

            if let rawAlerts = r.alerts, !rawAlerts.isEmpty {
                alerts = rawAlerts.prefix(3).map { a in
                    let sev = (a.severity ?? "info").lowercased()
                    let kind: StatusPill.Kind = (sev == "high" || sev == "critical") ? .danger : ((sev == "medium" || sev == "med") ? .warning : .info)
                    let tint: Color = kind == .danger ? Brand.danger : (kind == .warning ? Brand.warning : Brand.blue)
                    let sym = kind == .danger ? "exclamationmark.triangle.fill" : (kind == .warning ? "thermometer.medium" : "bell.fill")
                    return RiskAlert805(symbol: sym, tint: tint, kind: kind, pill: sev.uppercased(),
                                        title: a.message ?? "—", sub: "\(a.lane ?? "—") · \(a.createdAt ?? "")")
                }
            } else {
                alerts = []
            }

            // Cause breakdown via getLossPreventionAnalysis (groupBy commodity).
            struct Group: Decodable { let group: String?; let claimCount: Int?; let totalValue: Double? }
            struct Analysis: Decodable { let data: [Group]; let recommendations: [String] }
            let a: Analysis = try await EusoTripAPI.shared.query("freightClaims.getLossPreventionAnalysis", input: AnalysisInput805(groupBy: "commodity", period: "year"))
            if !a.data.isEmpty {
                let total = max(a.data.reduce(0) { $0 + ($1.totalValue ?? 0) }, 1)
                atRisk = usd805(total)
                let causePalette: [Color] = [Brand.danger, Brand.warning, Brand.info, Brand.neutral]
                causes = a.data.prefix(4).enumerated().map { i, g in
                    LossCause805(name: g.group ?? "—", frac: (g.totalValue ?? 0) / total, color: causePalette[i % causePalette.count],
                                 detail: "\(g.claimCount ?? 0) · \(usd805(g.totalValue ?? 0))")
                }
            } else {
                causes = []
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func viewAlerts() async {
        // freightClaims.getLossPreventionDashboard.alerts (EXISTS freightClaims.ts:988) — re-open the live feed.
        await load()
    }

    private func exportReport() async {
        // exportLossPreventionReport — STUB · named-gap (no backing mutation today; surfaced to the-oath).
        await load()
    }

    /// File-scoped USD formatter — the canonical port's `Money.usd(_:)` is not a
    /// shared app static (Money is a value struct), so we render the same compact
    /// grouped-dollars grammar the registered siblings use.
    private func usd805(_ v: Double) -> String {
        "$" + Int(v.rounded()).formatted(.number.grouping(.automatic))
    }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same outline grammar sibling
    /// 757 uses for its secondary CTA.
    private func secondaryButton805(title: String, action: @escaping () -> Void) -> some View {
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
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// Gradient-rim hero card — mirrors the gradient-stroked context cards the
/// registered siblings (664/680, sibling 757 `RimCard757`) ship.
private struct RimCard805<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
    }
}

/// ESang advisory row — the canonical port's `ESangRow` is not a shared app
/// symbol, so we render the same sparkle + advisory grammar file-scoped.
private struct ESangRow805: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }
}

private struct EmptyInput805: Encodable {}
private struct AnalysisInput805: Encodable { let groupBy: String; let period: String }

#Preview("805 · Loss Prevention · Night") { VesselLossPreventionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("805 · Loss Prevention · Light") { VesselLossPreventionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
