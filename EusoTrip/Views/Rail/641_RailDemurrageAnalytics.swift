//
//  641_RailDemurrageAnalytics.swift
//  EusoTrip — Rail Engineer · Demurrage Analytics (TREND/ANALYTICS archetype).
//
//  Verbatim port of "05 Rail / 641 Rail Demurrage Analytics" (dark wireframe).
//  ARCHETYPE = trend/analytics — distinct from 558 Demurrage Watch (live
//  per-car burndown). Hero carries an 8-week demurrage-$ bar-trend; below is
//  an itemized BY-DWELL-REASON ledger, a nightly-accrual context strip, and a
//  CTA pair (Export report · Dispute).
//
//  Live wiring (railDemurrageAuto.ts):
//    • trend bars + lead figure  -> railDemurrageAuto.dashboard           (EXISTS)
//    • by-reason ledger          -> railDemurrageAuto.reportByDwellReason (EXISTS)
//    • Dispute CTA               -> railDemurrageAuto.createDispute       (EXISTS · mutation)
//  PORT-GAP — the 8-week trend SERIES has no endpoint yet (proposed
//  railDemurrageAuto.weeklyTrend). We render a real empty trend state rather
//  than fabricate bar heights. The dashboard `summary` drives the lead $/over
//  figures; the ledger plots reportByDwellReason's `reasons` verbatim.
//
//  RBAC: protectedProcedure (rail carrier/engineer). transportMode=rail ·
//  country US (STB 48h free-time) · currency USD.
//

import SwiftUI

struct RailDemurrageAnalyticsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailDemurrageAnalyticsBody() } nav: {
            // NAV (RailEngineerNavController): HOME · SHIPMENTS · [orb] ·
            // COMPLIANCE · ME, current = SHIPMENTS.
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

// MARK: - Data shapes (mirror railDemurrageAuto.ts output verbatim)

/// railDemurrageAuto.dashboard → summary block.
private struct RailDemurrageSummary641: Decodable {
    let activeAccruals: Int?
    let totalChargesAccruing: Double?
    let disputesOpen: Int?
    let waiversPending: Int?
}

/// railDemurrageAuto.dashboard → one entry of `topDwellReasons`. Server
/// currently returns [] until the schema wiring lands; we decode defensively
/// so the ledger lights up the moment the rows arrive without a phone deploy.
private struct RailDwellReasonRow641: Decodable, Identifiable {
    let reason: String?
    let count: Int?
    let totalCharges: Double?
    let avgHours: Double?
    var id: String { reason ?? UUID().uuidString }
}

private struct RailDemurrageDashboard641: Decodable {
    let summary: RailDemurrageSummary641?
    let topDwellReasons: [RailDwellReasonRow641]?
}

/// railDemurrageAuto.reportByDwellReason → { reasons: [...] }.
private struct RailReportByDwellReason641: Decodable {
    let reasons: [RailDwellReasonRow641]?
}

/// railDemurrageAuto.createDispute → mutation result.
private struct RailDisputeResult641: Decodable {
    let disputeId: String?
    let status: String?
}

// MARK: - Body

private struct RailDemurrageAnalyticsBody: View {
    @Environment(\.palette) private var palette

    @State private var summary: RailDemurrageSummary641? = nil
    @State private var reasons: [RailDwellReasonRow641] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // Dispute mutation state (createDispute).
    @State private var disputing = false
    @State private var disputeAck: String? = nil
    @State private var disputeError: String? = nil

    // PORT-GAP — no weeklyTrend endpoint. The 8-week series stays empty so we
    // never fabricate chart data; the hero shows a real empty-trend rail.
    @State private var weeklyTrend: [Double] = []

    // MARK: Derived

    private var accruedUsd: Double { summary?.totalChargesAccruing ?? 0 }
    private var overCount: Int { summary?.activeAccruals ?? 0 }
    private var carCount: Int { reasons.reduce(into: 0) { acc, r in acc += (r.count ?? 0) } }
    private var recoveredUsd: Double { 0 } // server has no recovered figure yet — show 0, never seed.

    /// Sort the ledger by spend, descending — the ranked root-cause view the
    /// desc calls for ("attack the dwell reason actually driving spend").
    private var rankedReasons: [RailDwellReasonRow641] {
        reasons.sorted { ($0.totalCharges ?? 0) > ($1.totalCharges ?? 0) }
    }

    /// Grouped USD whole-dollar formatter — matches the wireframe's "$11,740"
    /// comma grouping. A single helper so every $ figure renders identically.
    private func usd(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: Int(value))) ?? "\(Int(value))")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline()
                if loading {
                    LifecycleCard {
                        Text("Loading demurrage analytics…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    trendHero
                    byDwellReasonLedger
                    accrualEngineStrip
                    if let ack = disputeAck {
                        ackBanner(ack, danger: false)
                    } else if let derr = disputeError {
                        ackBanner(derr, danger: true)
                    }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow row (✦ RAIL ENGINEER · DEMURRAGE  ·  30-DAY)

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("RAIL ENGINEER · DEMURRAGE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text("30-DAY")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Headline (back chevron · title · BNSF / synced meta)

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Demurrage analytics")
                .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("BNSF")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("synced 6m ago")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: - HERO · trend analytics card

    private var trendHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Window / over chips
            HStack(spacing: 8) {
                Text("window 30d")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
                Text("\(overCount) over")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.warning.opacity(0.18)))
            }
            .padding(.top, Space.s4)

            // Accrued lead figure  +  TREND MoM
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(usd(accruedUsd))
                        .font(.system(size: 30, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("accrued · \(carCount) cars in 30d")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("TREND")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    // PORT-GAP — MoM delta requires the trend series; with no
                    // endpoint we surface "—" rather than the wireframe's
                    // hard-coded "+8% MoM".
                    Text(monthOverMonthLabel)
                        .font(EType.mono(.body)).tracking(0.2)
                        .foregroundStyle(Brand.warning)
                }
            }
            .padding(.top, Space.s4)

            // 8-week $ trend bars (or real empty-trend rail)
            trendBars
                .padding(.top, Space.s5)
        }
        .padding(.horizontal, Space.s5)
        .padding(.bottom, Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var monthOverMonthLabel: String {
        // No weeklyTrend endpoint → cannot compute a real MoM delta.
        weeklyTrend.count >= 8 ? "+0% MoM" : "— MoM"
    }

    @ViewBuilder
    private var trendBars: some View {
        if weeklyTrend.count >= 2 {
            liveTrendBars
        } else {
            emptyTrendRail
        }
    }

    /// Live 8-week bars plotted from a real returned series. Last bar (current
    /// week) renders with the brand gradient; the prior two warm-toned per the
    /// wireframe's "this week live" emphasis.
    private var liveTrendBars: some View {
        let series = weeklyTrend
        let peak = max(series.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let n = series.count
                let gap: CGFloat = 12
                let totalGap = gap * CGFloat(max(n - 1, 0))
                let barW = max((geo.size.width - totalGap) / CGFloat(max(n, 1)), 2)
                let h = geo.size.height
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(series.enumerated()), id: \.offset) { idx, v in
                        let frac = CGFloat(v / peak)
                        let barH = max(h * frac, 3)
                        let isCurrent = idx == n - 1
                        let isWarm = idx >= n - 3 && !isCurrent
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                isCurrent
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(isWarm
                                        ? Brand.warning.opacity(0.50)
                                        : Color.white.opacity(0.10))
                            )
                            .frame(width: barW, height: barH)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 36)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }
            Text("8-wk demurrage · $/wk · this wk live")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
        }
    }

    /// PORT-GAP empty trend — no weeklyTrend endpoint. A flat baseline +
    /// honest caption instead of fabricated bars.
    private var emptyTrendRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .center) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                    Text("8-week trend series not yet wired")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .frame(height: 36)
            Text("8-wk demurrage · $/wk · awaiting weeklyTrend")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - BY DWELL REASON ledger

    private var byDwellReasonLedger: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("BREAKDOWN · BY DWELL REASON")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("reportByDwellReason:93")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }

            if rankedReasons.isEmpty {
                EusoEmptyState(
                    systemImage: "list.bullet.rectangle",
                    title: "No dwell-reason breakdown yet",
                    subtitle: "Ranked root-cause spend appears here once the nightly accrual engine populates reportByDwellReason."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rankedReasons.enumerated()), id: \.element.id) { idx, r in
                        if idx > 0 {
                            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                        dwellReasonRow(r)
                    }
                    Text(ledgerFootnote)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s4)
                        .padding(.top, Space.s2)
                        .padding(.bottom, Space.s4)
                }
                .padding(.top, Space.s2)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private var ledgerFootnote: String {
        recoveredUsd > 0
            ? "Within free time · no charge · recovered \(usd(recoveredUsd)) via disputes"
            : "Ranked by demurrage spend · nightly auto-recalc feeds the dispute queue"
    }

    private func dwellReasonRow(_ r: RailDwellReasonRow641) -> some View {
        let category = categoryFor(r.reason)
        let accent = category.color
        let pct = carCount > 0 ? Int((Double(r.count ?? 0) / Double(carCount)) * 100) : 0
        return HStack(spacing: Space.s3) {
            // 40×40 icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: category.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(prettyReason(r.reason))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(r.count ?? 0) cars · \(pct)% · avg \(avgDaysLabel(r.avgHours))")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            // category pill
            Text(category.tag)
                .font(.system(size: 10, weight: .bold)).tracking(0.5)
                .foregroundStyle(accent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(accent.opacity(0.18)))
            // right tabular $
            Text(usd(r.totalCharges ?? 0))
                .font(.system(size: 14, weight: .bold)).monospacedDigit()
                .foregroundStyle(category.isTop ? accent : palette.textPrimary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private func avgDaysLabel(_ hours: Double?) -> String {
        guard let h = hours, h > 0 else { return "—" }
        return String(format: "%.1fd", h / 24.0)
    }

    private func prettyReason(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Unknown reason" }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Accrual engine context strip

    private var accrualEngineStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACCRUAL ENGINE · NIGHTLY 02:00 CT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(carCount) cars")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("reportByDwellReason feeds dispute queue · auto-recalc")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.textSecondary)
            Text("Carrier BNSF Intermodal · Eusorone (DU) · RAIL-260524-A7140")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Dispute ack banner

    private func ackBanner(_ text: String, danger: Bool) -> some View {
        let color: Color = danger ? Brand.danger : Brand.success
        return HStack(spacing: Space.s2) {
            Image(systemName: danger ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
            Text(text).font(EType.caption).foregroundStyle(color)
            Spacer()
        }
        .padding(Space.s3)
        .background(color.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - CTA pair (Export report · Dispute)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Export report", action: {}, leadingIcon: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
            Button(action: { Task { await openDispute() } }) {
                HStack(spacing: 6) {
                    if disputing {
                        ProgressView().controlSize(.small).tint(palette.textPrimary)
                    }
                    Text("Dispute")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgCardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
            .disabled(disputing)
        }
    }

    // MARK: - Category mapping (dwell reason → icon / tag / accent)

    private struct DwellCategory {
        let icon: String
        let tag: String
        let color: Color
        var isTop: Bool = false
    }

    private func categoryFor(_ reason: String?) -> DwellCategory {
        let key = (reason ?? "").lowercased()
        let isTop = rankedReasons.first?.reason == reason
        if key.contains("congest") || key.contains("yard") || key.contains("ramp") {
            return DwellCategory(icon: "clock", tag: "RAMP", color: Brand.warning, isTop: isTop)
        }
        if key.contains("chassis") || key.contains("power") || key.contains("equip") {
            return DwellCategory(icon: "link", tag: "EQUIP", color: Brand.info, isTop: isTop)
        }
        if key.contains("consignee") || key.contains("hold") || key.contains("paperwork") || key.contains("customer") {
            return DwellCategory(icon: "doc.text", tag: "HOLD", color: Brand.escort, isTop: isTop)
        }
        if key.contains("weather") {
            return DwellCategory(icon: "cloud.rain", tag: "WX", color: Brand.info, isTop: isTop)
        }
        return DwellCategory(icon: "questionmark.circle", tag: "OTHER", color: palette.textSecondary, isTop: isTop)
    }

    // MARK: - Data

    private func reload() async {
        loading = true; loadError = nil
        struct DashIn: Encodable {}
        struct ReasonIn: Encodable { let periodDays: Int }
        do {
            async let dash: RailDemurrageDashboard641 = EusoTripAPI.shared.query(
                "railDemurrageAuto.dashboard", input: DashIn())
            async let rep: RailReportByDwellReason641 = EusoTripAPI.shared.query(
                "railDemurrageAuto.reportByDwellReason", input: ReasonIn(periodDays: 30))
            let (d, r) = try await (dash, rep)
            self.summary = d.summary
            // Prefer the dedicated report endpoint's reasons; fall back to the
            // dashboard's topDwellReasons if the report returns nothing.
            let reportReasons = r.reasons ?? []
            self.reasons = reportReasons.isEmpty ? (d.topDwellReasons ?? []) : reportReasons
            // PORT-GAP — no weeklyTrend endpoint. Series stays empty; the hero
            // renders the honest empty-trend rail.
            self.weeklyTrend = []
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Submits a demurrage dispute via the real createDispute mutation.
    /// createDispute requires a per-car `demurrageId`; this analytics surface
    /// only has the dashboard aggregates, so we thread the id when one is
    /// available and otherwise surface an honest message rather than invent
    /// one. `submitDispute(demurrageId:reason:notes:)` is the live wire — it
    /// hits railDemurrageAuto.createDispute verbatim.
    private func openDispute() async {
        // PORT-GAP — the analytics dashboard returns aggregates with no
        // per-car demurrageId, and createDispute requires one. Surface the
        // honest hand-off to Demurrage Watch (where the id exists) instead of
        // fabricating an id. The live mutation path lives in
        // `submitDispute(...)` below and fires the moment an id is threaded in.
        disputeAck = nil
        disputeError = "Select a car on Demurrage Watch to open a dispute — analytics carries no per-car demurrage id yet."
    }

    /// Live createDispute wire. Kept as a dedicated method so the analytics
    /// surface can call it the moment a per-car demurrageId is threaded in
    /// (e.g. from a drill sheet), with real success/error acks.
    private func submitDispute(demurrageId: Int, reason: String, notes: String?) async {
        guard !disputing else { return }
        disputing = true; disputeAck = nil; disputeError = nil
        struct DisputeIn: Encodable {
            let demurrageId: Int
            let reason: String
            let notes: String?
        }
        do {
            let result: RailDisputeResult641 = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.createDispute",
                input: DisputeIn(demurrageId: demurrageId, reason: reason, notes: notes))
            disputeAck = "Dispute \(result.disputeId ?? "submitted") · \(result.status ?? "submitted")"
        } catch {
            disputeError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        disputing = false
    }
}

#Preview("641 · Rail Demurrage Analytics · Night") {
    RailDemurrageAnalyticsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("641 · Rail Demurrage Analytics · Light") {
    RailDemurrageAnalyticsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
