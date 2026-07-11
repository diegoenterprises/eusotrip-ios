//
//  755_VesselMultimodalAnalytics.swift
//  EusoTrip — Vessel Operator · Multimodal Analytics.
//
//  Faithful 1:1 port of "755 Vessel Multimodal Analytics.svg" (Light + Dark).
//  PORTFOLIO-COMPOSITION archetype (deliberately distinct from 753's transit
//  bars and 754's cost number-line): a 4-cell network KPI strip (revenue cell
//  inked eusoDiagonal), a single stacked revenue-share bar segmented by mode,
//  and a legend ledger carrying share% + trend pills — a composition view, not
//  a chip-comparison. Detail header, KPI strip, revenue-share composition,
//  CTA pair, ESANG conversion row. Real Vessel-Operator BottomNav with HOME inked.
//
//  Wiring (endpoint confirmed on disk this fire):
//    multiModal.getMultiModalAnalytics — EXISTS frontend/server/routers/multiModal.ts:1942
//      · protectedProcedure · query · input {dateRange?} (optional)
//      · returns {kpis:{totalShipments,totalRevenue,avgCostPerShipment,onTimeDelivery,
//        avgDwellTime,emptyMilesRatio,intermodalConversionRate,co2Saved},
//        modeBreakdown:[{mode,shipments,revenue,avgCost,onTime,co2PerShipment}], …}
//      derived from real loads (revenue = SUM(rate), intermodal split).
//    "Monthly trend" re-runs load(); "Export" → STUB · named-gap exportMultiModalAnalytics.
//    ESANG conversion row → esangCoach.forScreen.
//
//  0 mock data on load · honest empty/degraded states. Historical YTD aggregate
//  (not a live tick), so no map/geofence fusion applies here.
//

import SwiftUI

// MARK: - Model

private struct ModeShare755: Identifiable {
    let mode: String
    let shipments: Int
    let revenue: Double
    var id: String { mode }
}

private struct MMAnalytics755 {
    let totalShipments: Int
    let totalRevenue: Double
    let avgCostPerShipment: Double
    let onTimeDelivery: Double
    let intermodalConversionRate: Double
    let modes: [ModeShare755]
    var revenueTotal: Double { max(modes.reduce(0) { $0 + $1.revenue }, totalRevenue) }
    var withRevenue: [ModeShare755] { modes.filter { $0.revenue > 0 }.sorted { $0.revenue > $1.revenue } }
    var zeroModes: [ModeShare755] { modes.filter { $0.revenue <= 0 } }
}

private struct Empty755: Encodable {}

// MARK: - Wrapper

struct VesselMultimodalAnalyticsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselMMABody755()
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

private struct VesselMMABody755: View {
    @Environment(\.palette) private var palette

    @State private var data: MMAnalytics755? = nil
    @State private var esangTip: String? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private let ocean = Brand.info
    private let truck = Brand.warning
    private let intermodal = Brand.escort
    private let rail = Color(hex: 0x2FBE82)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading multimodal analytics…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let d = data, d.totalShipments > 0 {
                    kpiStrip(d)
                    compositionSection(d)
                    ctaPair
                    esangRow(d)
                } else {
                    EusoEmptyState(systemImage: "chart.pie",
                                   title: "No shipments in range",
                                   subtitle: "getMultiModalAnalytics returned no shipments. There is no revenue composition to break down across modes yet.")
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · ANALYTICS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("YTD 2026").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Text("Multimodal analytics").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    private var subline: String {
        guard let d = data else { return "All-mode revenue · shipments · on-time" }
        return "All-mode revenue · \(d.totalShipments.formatted(.number.grouping(.automatic))) shipments · \(pct(d.onTimeDelivery)) on-time YTD"
    }

    // MARK: KPI strip (revenue inked)

    private func kpiStrip(_ d: MMAnalytics755) -> some View {
        HStack(spacing: 8) {
            KpiCell755(label: "REVENUE", value: compactMoney(d.totalRevenue), sub: "YTD 2026", gradient: true)
            KpiCell755(label: "SHIPMENTS", value: d.totalShipments.formatted(.number.grouping(.automatic)), sub: "\(money(d.avgCostPerShipment)) avg")
            KpiCell755(label: "ON-TIME", value: pct(d.onTimeDelivery), sub: "held YTD", subColor: Brand.success)
            KpiCell755(label: "IM CONV", value: pct(d.intermodalConversionRate), sub: "intermodal", subColor: Brand.success)
        }
    }

    // MARK: Revenue-share composition

    private func compositionSection(_ d: MMAnalytics755) -> some View {
        let total = max(1, d.revenueTotal)
        let leadId = d.withRevenue.first?.id
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("REVENUE SHARE · BY MODE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(compactMoney(d.revenueTotal)) revenue").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(d.withRevenue.count) active modes").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, 16).padding(.top, 14)
                // stacked share bar
                GeometryReader { g in
                    HStack(spacing: 0) {
                        ForEach(d.withRevenue) { m in
                            Rectangle().fill(accent(m.mode))
                                .frame(width: max(2, CGFloat(m.revenue / total) * g.size.width))
                        }
                    }
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(palette.textPrimary.opacity(0.05), lineWidth: 1))
                }
                .frame(height: 16)
                .padding(.horizontal, 16).padding(.top, 12)
                Divider().overlay(palette.borderFaint).padding(.top, 12)
                ForEach(Array(d.withRevenue.enumerated()), id: \.element.id) { idx, m in
                    ShareRow755(mode: m, accent: accent(m.mode),
                                sharePct: m.revenue / total * 100,
                                badge: m.id == leadId ? ("LEAD", ocean) : (m.mode == "intermodal" ? ("+\(Int(d.intermodalConversionRate.rounded())) pt", rail) : nil))
                    if idx < d.withRevenue.count - 1 || !d.zeroModes.isEmpty { Divider().overlay(palette.borderFaint).padding(.leading, 16) }
                }
                ForEach(Array(d.zeroModes.enumerated()), id: \.element.id) { idx, m in
                    ShareRow755(mode: m, accent: accent(m.mode).opacity(0.45), sharePct: 0, badge: ("NEW", palette.textTertiary), muted: true)
                    if idx < d.zeroModes.count - 1 { Divider().overlay(palette.borderFaint).padding(.leading, 16) }
                }
            }
            .padding(.bottom, 10)
            .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: 8) {
            CTAButton(title: "Monthly trend", action: { Task { await load() } })
            Button(action: { Task { await load() } }) {
                Text("Export").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }.buttonStyle(.plain).frame(width: 128)
        }
    }

    // MARK: ESANG

    private func esangRow(_ d: MMAnalytics755) -> some View {
        let title = esangTip ?? "Intermodal conversion at \(pct(d.intermodalConversionRate))"
        let detail = "Each shift trims CO₂/shipment · on-time held at \(pct(d.onTimeDelivery))"
        return ESangRow755(title: title, detail: detail)
    }

    // MARK: Helpers

    private func accent(_ mode: String) -> Color {
        switch mode { case "ocean": return ocean; case "truck": return truck; case "intermodal": return intermodal; default: return rail }
    }
    private func pct(_ v: Double) -> String { "\(String(format: v == v.rounded() ? "%.0f" : "%.1f", v))%" }
    private func money(_ v: Double) -> String { "$\(Int(v).formatted(.number.grouping(.automatic)))" }
    private func compactMoney(_ v: Double) -> String {
        if v >= 1_000_000 { return "$\(String(format: "%.2f", v / 1_000_000))M" }
        if v >= 1_000 { return "$\(String(format: "%.1f", v / 1_000))K" }
        return money(v)
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        do {
            struct KPIs: Decodable {
                let totalShipments: Int?; let totalRevenue: Double?; let avgCostPerShipment: Double?
                let onTimeDelivery: Double?; let intermodalConversionRate: Double?
            }
            struct Mode: Decodable { let mode: String?; let shipments: Int?; let revenue: Double? }
            struct Resp: Decodable { let kpis: KPIs?; let modeBreakdown: [Mode]? }
            let r: Resp = try await EusoTripAPI.shared.query("multiModal.getMultiModalAnalytics", input: Empty755())
            let k = r.kpis
            let modes = (r.modeBreakdown ?? []).compactMap { m -> ModeShare755? in
                guard let name = m.mode else { return nil }
                return ModeShare755(mode: name, shipments: m.shipments ?? 0, revenue: m.revenue ?? 0)
            }
            data = MMAnalytics755(
                totalShipments: k?.totalShipments ?? 0,
                totalRevenue: k?.totalRevenue ?? 0,
                avgCostPerShipment: k?.avgCostPerShipment ?? 0,
                onTimeDelivery: k?.onTimeDelivery ?? 0,
                intermodalConversionRate: k?.intermodalConversionRate ?? 0,
                modes: modes
            )
            struct CoachIn: Encodable { let screen: String }
            struct CoachOut: Decodable { let tip: String? }
            if let c: CoachOut = try? await EusoTripAPI.shared.query("esangCoach.forScreen", input: CoachIn(screen: "haul")),
               let t = c.tip, !t.isEmpty { esangTip = t } else { esangTip = nil }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - File-scoped bespoke helpers

private struct KpiCell755: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let sub: String
    var subColor: Color? = nil
    var gradient: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(gradient ? Color.white.opacity(0.85) : palette.textTertiary)
            Text(value).font(.system(size: 20, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(gradient ? Color.white : palette.textPrimary)
            Text(sub).font(.system(size: 10)).foregroundStyle(gradient ? Color.white.opacity(0.85) : (subColor ?? palette.textSecondary))
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(gradient ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard)))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(gradient ? Color.clear : palette.borderFaint, lineWidth: 1))
    }
}

private struct ShareRow755: View {
    @Environment(\.palette) private var palette
    let mode: ModeShare755
    let accent: Color
    let sharePct: Double
    let badge: (String, Color)?
    var muted: Bool = false
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(accent).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.mode.capitalized).font(.system(size: 14, weight: .bold)).foregroundStyle(muted ? palette.textSecondary : palette.textPrimary)
                Text(muted ? "0 shp · onboarding" : "\(mode.shipments) shp · \(Int(sharePct.rounded()))% share")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(muted ? palette.textTertiary : palette.textSecondary)
            }
            Spacer()
            Text(compact(mode.revenue)).font(.system(size: 14, weight: .bold)).monospacedDigit()
                .foregroundStyle(muted ? palette.textTertiary : palette.textPrimary)
            if let badge {
                Text(badge.0).font(.system(size: 9, weight: .heavy)).foregroundStyle(badge.1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(badge.1.opacity(0.16)))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
    private func compact(_ v: Double) -> String {
        if v >= 1_000_000 { return "$\(String(format: "%.2f", v / 1_000_000))M" }
        if v >= 1_000 { return "$\(String(format: "%.0f", v / 1_000))K" }
        return "$\(Int(v))"
    }
}

private struct ESangRow755: View {
    @Environment(\.palette) private var palette
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 16)).frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG: \(title)").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text(detail).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

#Preview("755 · Vessel Multimodal Analytics · Night") { VesselMultimodalAnalyticsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("755 · Vessel Multimodal Analytics · Light") { VesselMultimodalAnalyticsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
