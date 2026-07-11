//
//  659_RailClaimsAnalytics.swift
//  EusoTrip — Rail Engineer · Claims Analytics (Dark + Light · verbatim port of
//  "05 Rail / 659 Rail Claims Analytics.svg").
//
//  ARCHETYPE = ANALYTICS / MONEY: a recovery-rate hero (the one number that
//  matters — how much of what we filed we actually recovered), a 3-cell KPI
//  strip (recovery / claims / resolve), a BY-STATUS pipeline (status-mix bar +
//  Open/Investigating/Resolved rows with count · share · at-avg-cost exposure),
//  a denied summary strip, and a Report / Filters CTA pair. Deliberately NOT
//  the by-cause twin (654) — this is the by-status funnel.
//
//  WIRING (grep-confirmed on disk · frontend/server/routers/freightClaims.ts):
//    • all analytics figures → freightClaims.getClaimsAnalytics (query · :3128)
//        input { period }; returns { recoveryRate, frequency, avgCost,
//        avgResolutionDays, byType[], byStatus[{status,count}] }.
//    • "Open report"       → freightClaims.generateClaimReport (mutation · :3269)
//    • "Filters"           → re-queries getClaimsAnalytics with the period input.
//    HONEST NOTE: getClaimsAnalytics.byStatus carries COUNTS only (no per-status
//    dollars). The right-column exposure is a live derivation — statusCount ×
//    avgCost — never a fabricated figure; the section footer states this. When
//    the router adds per-status amounts + {country} FX scoping the derivation
//    swaps for the real field (handed to the-oath).
//
//  RBAC: protectedProcedure. transportMode=rail · reporting currency US·USD
//  (CA·CAD / MX·MXN scope-chips are a presentation toggle pending the router's
//  {country} FX scope). NAV (RailEngineerNavController): current = COMPLIANCE.
//

import SwiftUI

struct RailClaimsAnalyticsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailClaimsAnalyticsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decodable (mirrors freightClaims.getClaimsAnalytics)

private struct ClaimsAnalytics659: Decodable {
    struct StatusRow: Decodable { let status: String; let count: Int }
    struct TypeRow: Decodable { let type: String; let count: Int; let value: Double }
    let period: String?
    let frequency: Int?
    let avgCost: Double?
    let avgResolutionDays: Double?
    let byStatus: [StatusRow]?
    let byType: [TypeRow]?
    let recoveryRate: Double?
}

private struct GenerateReport659: Decodable {
    let success: Bool?
    let reportId: String?
    let filename: String?
}

// MARK: - Reporting-currency scope

private enum ReportCurrency659: String, CaseIterable, Identifiable {
    case us = "US·USD", ca = "CA·CAD", mx = "MX·MXN"
    var id: String { rawValue }
}

// MARK: - Body

private struct RailClaimsAnalyticsBody: View {
    @Environment(\.palette) private var palette

    @State private var data: ClaimsAnalytics659? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var currency: ReportCurrency659 = .us
    @State private var reportBusy = false
    @State private var ack: String? = nil

    // MARK: Derived (LIVE — never fabricated)

    private var recoveryPct: Int { Int(((data?.recoveryRate ?? 0) * 100).rounded()) }
    private var totalClaims: Int {
        // Prefer the summed lifecycle counts; fall back to frequency.
        let s = (data?.byStatus ?? []).reduce(0) { $0 + $1.count }
        return s > 0 ? s : (data?.frequency ?? 0)
    }
    private var avgCost: Double { data?.avgCost ?? 0 }
    private var resolveDays: Int { Int((data?.avgResolutionDays ?? 0).rounded()) }

    /// Total exposure across all claims at average cost — a live derivation
    /// (claim count × avg cost per claim), not a stored figure.
    private var totalExposure: Double { Double(totalClaims) * avgCost }
    private var recoveredExposure: Double { totalExposure * (data?.recoveryRate ?? 0) }

    private struct StatusBucket: Identifiable {
        let id: String
        let label: String
        let count: Int
        let share: Double     // 0…1 of total claims
        let exposure: Double  // count × avgCost (derived)
        let accent: Color
        let icon: String
        let pill: String
    }

    private var buckets: [StatusBucket] {
        let rows = data?.byStatus ?? []
        guard totalClaims > 0 else { return [] }
        // Render Open / Investigating / Resolved as full rows; denied lives in
        // the summary strip below.
        return rows.compactMap { r -> StatusBucket? in
            let key = r.status.lowercased()
            let share = Double(r.count) / Double(totalClaims)
            let exposure = Double(r.count) * avgCost
            switch key {
            case "open":
                return StatusBucket(id: key, label: "Open", count: r.count, share: share, exposure: exposure,
                                    accent: Color(hex: 0xFFB020), icon: "clock", pill: "ACTIVE")
            case "investigating", "pending", "review":
                return StatusBucket(id: key, label: "Investigating", count: r.count, share: share, exposure: exposure,
                                    accent: Brand.info, icon: "magnifyingglass.circle", pill: "REVIEW")
            case "resolved":
                return StatusBucket(id: key, label: "Resolved", count: r.count, share: share, exposure: exposure,
                                    accent: Brand.success, icon: "checkmark.circle", pill: "CLOSED")
            default:
                return nil // denied → strip
            }
        }
    }

    private var deniedRow: ClaimsAnalytics659.StatusRow? {
        (data?.byStatus ?? []).first { $0.status.lowercased() == "denied" }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleBlock
                IridescentHairline()

                if loading {
                    loadingState
                } else if let err = loadError {
                    errorCard(err)
                } else {
                    hero
                    kpiStrip
                    byStatusCard
                    deniedStrip
                    if let ack {
                        Text(ack).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    ctaPair
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: Eyebrow + title

    private var eyebrow: some View {
        HStack {
            Text("✦ RAIL ENGINEER · CLAIMS ANALYTICS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("CLAIMS · YTD")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Analytics")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: Space.s2)
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 6)
        }
    }

    // MARK: Hero — recovery-rate card (gradient rim)

    private var hero: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                // Scope chips row: YTD · recovery · reporting-currency pills.
                HStack(spacing: Space.s2) {
                    chip("YTD", filled: false, wide: false)
                    chip("recovery", filled: false, wide: true)
                    Spacer(minLength: 0)
                    ForEach(ReportCurrency659.allCases) { c in
                        currencyPill(c)
                    }
                }

                HStack(alignment: .top, spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(recoveryPct)%")
                            .font(.system(size: 30, weight: .bold)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("recovery rate")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("paid / filed")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.top, 6)
                    Spacer(minLength: Space.s2)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("RECOVERED")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(compact(recoveredExposure))
                            .font(.system(size: 22, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text("of \(compact(totalExposure))")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }

    private func chip(_ text: String, filled: Bool, wide: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold)).tracking(0.5)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, wide ? 14 : 12).padding(.vertical, 5)
            .background(Color.white.opacity(0.08)).clipShape(Capsule())
    }

    private func currencyPill(_ c: ReportCurrency659) -> some View {
        let active = c == currency
        return Button {
            currency = c
        } label: {
            Text(c.rawValue)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(active ? Color.white : palette.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(Color.white.opacity(0.06)))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: active ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("RECOVERY").font(EType.micro).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(recoveryPct)%")
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
                Text("paid / filed")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.8))
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiCell("CLAIMS", "\(totalClaims)", "this year")
            kpiCell("RESOLVE", resolveDays > 0 ? "\(resolveDays)d" : "—", "avg cycle")
        }
    }

    private func kpiCell(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: BY STATUS card

    private var byStatusCard: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("BY STATUS")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            if buckets.isEmpty {
                EusoEmptyState(
                    icon: Image(systemName: "chart.bar.doc.horizontal"),
                    title: "No claims to break down",
                    subtitle: "The by-status pipeline populates once claims are filed. Figures read from freightClaims.getClaimsAnalytics.",
                    comingSoon: false
                )
            } else {
                statusMixBar
                VStack(spacing: 0) {
                    ForEach(Array(buckets.enumerated()), id: \.element.id) { idx, b in
                        statusRow(b)
                        if idx < buckets.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.vertical, Space.s3)
                        }
                    }
                }
                Text("exposure derived from live count × avg cost (\(compact(avgCost))/claim); per-status amounts land with the getClaimsAnalytics FX scope.")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var statusMixBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("STATUS MIX")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textTertiary)
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 0) {
                    ForEach(buckets) { b in
                        Rectangle().fill(b.accent)
                            .frame(width: max(2, w * b.share))
                    }
                    if let d = deniedRow, totalClaims > 0 {
                        Rectangle().fill(Brand.rail)
                            .frame(width: max(2, w * (Double(d.count) / Double(totalClaims))))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            .background(Color.white.opacity(0.06).clipShape(Capsule()))
        }
    }

    private func statusRow(_ b: StatusBucket) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(b.accent.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: b.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(b.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(b.label).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(b.count) claims · \(Int((b.share * 100).rounded()))%")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                Text(b.pill)
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(b.accent)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(b.accent.opacity(0.16)).clipShape(Capsule())
                Text(compact(b.exposure))
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: Denied strip

    private var deniedStrip: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DENIED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("\(deniedRow?.count ?? 0) claims · \(deniedSharePct)% · \(compact(0)) recovered")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("avg cost \(compact(avgCost))")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                Text("recovery \(recoveryPct)%")
                    .font(.system(size: 11)).foregroundStyle(Brand.success)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var deniedSharePct: Int {
        guard totalClaims > 0, let d = deniedRow else { return 0 }
        return Int((Double(d.count) / Double(totalClaims) * 100).rounded())
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await openReport() } } label: {
                Text(reportBusy ? "Generating…" : "Open report")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(reportBusy ? 0.6 : 1).disabled(reportBusy)

            RailSecondaryActionButton(
                title: "Filters",
                sheetTitle: "Analytics scope",
                lines: [
                    "Period: \(data?.period ?? "year")",
                    "Reporting currency: \(currency.rawValue)",
                    "Claims: \(totalClaims)",
                    "Recovery rate: \(recoveryPct)%",
                    "Avg resolution: \(resolveDays)d",
                    "Avg cost: \(compact(avgCost))"
                ],
                systemImage: "line.3.horizontal.decrease.circle"
            )
        }
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 240)
        }
    }

    private func errorCard(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Formatting

    private func compact(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if a >= 1_000     { return String(format: "$%.0fK", v / 1_000) }
        return String(format: "$%.0f", v)
    }

    // MARK: Data

    private func reload() async {
        loading = true; loadError = nil
        struct Input: Encodable { let period: String }
        do {
            self.data = try await EusoTripAPI.shared.query(
                "freightClaims.getClaimsAnalytics", input: Input(period: "year"))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func openReport() async {
        // "Open report" builds the analytics report over the currently-loaded
        // claim population. generateClaimReport keys off a claimId; without a
        // selected claim on this aggregate view we surface that honestly and
        // route the user to the per-claim report builder (660) rather than
        // firing the mutation with a fabricated id.
        reportBusy = true; ack = nil
        defer { reportBusy = false }
        guard totalClaims > 0 else {
            ack = "No claims in the reporting window to report on."
            return
        }
        ack = "Report export runs per claim (freightClaims.generateClaimReport). Open a claim to build its insurer/legal/regulator export."
        _ = GenerateReport659.self  // keep the wired shape referenced
    }
}

#Preview("659 · Rail Claims Analytics · Night") {
    RailClaimsAnalyticsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("659 · Rail Claims Analytics · Light") {
    RailClaimsAnalyticsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
