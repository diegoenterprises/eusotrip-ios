//
//  219_ShipperFreightClaims.swift
//  EusoTrip - Shipper freight-claim register, filing, evidence, and disputes.
//

import SwiftUI

// MARK: - Status filter

private enum ClaimStatusFilter: String, CaseIterable, Identifiable {
    case all
    case open
    case pending
    case resolved
    case denied

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:      return "All"
        case .open:     return "Open"
        case .pending:  return "Pending"
        case .resolved: return "Resolved"
        case .denied:   return "Denied"
        }
    }

    var icon: String {
        switch self {
        case .all:      return "square.grid.2x2"
        case .open:     return "exclamationmark.circle.fill"
        case .pending:  return "hourglass"
        case .resolved: return "checkmark.seal.fill"
        case .denied:   return "xmark.seal.fill"
        }
    }

    var serverStatus: String? {
        switch self {
        case .all:      return nil
        case .open:     return "investigating"
        case .pending:  return "pending_evidence"
        case .resolved: return "settled"
        case .denied:   return "denied"
        }
    }
}

// MARK: - Store (preserved)

@MainActor
final class ShipperFreightClaimsStore: ObservableObject {
    enum LoadState {
        case loading
        case error(String)
        case loaded(
            dashboard: ShipperFreightClaimsAPI.Dashboard,
            claims: [ShipperFreightClaimsAPI.ClaimRow]
        )
    }

    @Published private(set) var state: LoadState = .loading
    @Published fileprivate var filter: ClaimStatusFilter = .all {
        didSet {
            if oldValue != filter { Task { await refresh() } }
        }
    }
    @Published var searchTerm: String = ""

    /// Weather-peril classification per claim id. A failed read remains a
    /// failed read; the UI never infers weather from the claim type.
    @Published fileprivate var perils: [String: ClaimPerilClassification] = [:]
    @Published fileprivate var perilReadFailures: Set<String> = []

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    /// Classify one claim's weather peril and cache only server-grounded results.
    func classifyPeril(_ claim: ShipperFreightClaimsAPI.ClaimRow) async {
        if perils[claim.id] != nil || perilReadFailures.contains(claim.id) { return }
        struct In: Encodable { let claimId: String }
        do {
            let c: ClaimPerilClassification = try await api.query(
                "freightClaims.classifyClaimPeril", input: In(claimId: claim.id))
            perils[claim.id] = c
        } catch {
            perilReadFailures.insert(claim.id)
        }
    }

    func refresh() async {
        if case .loaded = state {} else { state = .loading }
        do {
            async let d = api.shipperFreightClaims.getClaimsDashboard()
            async let l = api.shipperFreightClaims.getClaims(
                status: filter.serverStatus,
                search: searchTerm.isEmpty ? nil : searchTerm,
                limit: 50
            )
            let (dashboard, listResponse) = try await (d, l)
            state = .loaded(dashboard: dashboard, claims: listResponse.claims)
        } catch {
            state = .error("Couldn't reach freight claims service.")
        }
    }
}

// MARK: - Severity / status helpers

private struct SeverityStyle {
    let label: String
    let color: Color
}

private func severityStyle(_ raw: String?) -> SeverityStyle {
    switch (raw ?? "").lowercased() {
    case "critical":  return SeverityStyle(label: "Critical", color: Brand.danger)
    case "major":     return SeverityStyle(label: "Major",    color: Brand.warning)
    case "moderate":  return SeverityStyle(label: "Moderate", color: Brand.info)
    case "minor":     return SeverityStyle(label: "Minor",    color: Brand.success)
    default:           return SeverityStyle(label: (raw ?? "-").capitalized, color: Brand.info)
    }
}

private func statusColor(_ raw: String?, palette: Theme.Palette) -> Color {
    switch (raw ?? "").lowercased() {
    case "filed", "under_review", "investigating", "pending_evidence": return Brand.warning
    case "approved", "partial_approval", "counter_offer":                return Brand.info
    case "settled", "paid", "closed":                                   return Brand.success
    case "denied":                                                         return Brand.danger
    default:                           return palette.textSecondary
    }
}

private func typeIcon(_ raw: String?) -> String {
    switch (raw ?? "").lowercased() {
    case "damage":         return "hammer.fill"
    case "loss":           return "questionmark.diamond.fill"
    case "shortage":       return "minus.diamond.fill"
    case "delay":          return "clock.badge.exclamationmark.fill"
    case "contamination":  return "drop.triangle.fill"
    case "theft":          return "lock.shield.fill"
    default:                return "shippingbox.and.arrow.backward.fill"
    }
}

private func prettifyType(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "Unknown" }
    return raw.replacingOccurrences(of: "_", with: " ").capitalized
}

// MARK: - Weather-peril classification (freightClaims.classifyClaimPeril)
//
// `freightClaims.classifyClaimPeril({claimId})` → a weather-peril
// classification record + (when the enterprise key is present) the cited
// weather snapshot the claim should reference. Enterprise-gated today: the
// classifier still flags whether a claim's TYPE/cause is weather-shaped (a
// free, deterministic read), but the cited `snapshot`/`peril` envelope comes
// back `available:false` — so we badge the claim as weather-peril from the
// type/peril fields and render the ENTERPRISE state for the cited report.
// EVERY field is optional so the gated shape decodes without throwing. We
// NEVER fabricate a peril verdict or a snapshot.
struct ClaimPerilClassification: Decodable, Hashable {
    struct Verdict: Decodable, Hashable {
        let classification: String
        let matchedTerms: [String]
        let isWeatherPeril: Bool
    }

    let claimId: String
    let available: Bool
    let weatherPeril: Verdict

    var shouldBadge: Bool {
        available && weatherPeril.isWeatherPeril
    }

    var perilLabel: String {
        weatherPeril.classification == "weather_peril" ? "Weather peril" : "Weather review"
    }
}

// MARK: - Screen root

struct ShipperFreightClaims: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    // Sheet→push (NAV remediation 2026-05-30): the claim detail pushes
    // in-stack via the surface detail layer + BespokeBackBar.
    @Environment(\.shipperPushDetail) private var pushDetail
    @StateObject private var store = ShipperFreightClaimsStore()
    @State private var selected: ShipperFreightClaimsAPI.ClaimRow?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)

                content
                    .padding(.top, Space.s4)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .eusoRefreshable { await store.refresh() }
        // RealtimeService → freight claims refresh when carrier-side
        // claim status changes (filed, investigation, settled).
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await store.refresh() }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18),
            value: store.filter
        )
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            EusoTripEyebrow(verbatim: "SHIPPER · FREIGHT CLAIMS")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel(counterAccessibility)
        }
        .padding(.horizontal, Space.s5)
    }

    private var counterEyebrow: String {
        if case .loaded(let d, _) = store.state {
            let open = openClaimsMetric(d)
            let resolved = resolvedClaimsMetric(d)
            return "\(open.value) OPEN · \(resolved.value) RESOLVED"
        }
        return "—"
    }

    private var counterAccessibility: String {
        if case .loaded(let d, _) = store.state {
            let open = openClaimsMetric(d)
            let resolved = resolvedClaimsMetric(d)
            return "\(open.accessibilityLabel) \(resolved.accessibilityLabel)"
        }
        return "Loading freight claims"
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Freight claims")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Damage · shortage · loss · delay · contamination · overcharge")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 84)
                }
            }
            .padding(.horizontal, Space.s5)
        case .error(let msg):
            errorBanner(msg)
                .padding(.horizontal, Space.s5)
        case .loaded(let dashboard, let claims):
            VStack(alignment: .leading, spacing: 0) {
                kpiStrip(d: dashboard)
                    .padding(.horizontal, Space.s5)

                sectionLabel("OPEN CLAIMS")
                    .padding(.top, Space.s4)

                let openMetric = openClaimsMetric(dashboard)
                let resolvedMetric = resolvedClaimsMetric(dashboard)
                if openMetric.valueState == .measured && dashboard.open == 0 {
                    emptyHeroCard(metric: openMetric)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)
                } else if openMetric.displaysMeasurement && dashboard.open > 0 {
                    activeClaimsBlock(dashboard: dashboard, claims: claims)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)
                } else {
                    openClaimsTruthCard(openMetric)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)
                }

                fileClaimCTA
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)

                let history = resolvedHistory(from: claims, dashboard: dashboard)
                if !history.isEmpty {
                    sectionLabel("CLAIM HISTORY · \(resolvedMetric.value) RESOLVED")
                        .accessibilityLabel(resolvedMetric.accessibilityLabel)
                        .padding(.top, Space.s5)
                    historyCard(rows: history, metric: resolvedMetric)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s5)
    }

    // MARK: KPI strip (3 tiles · OPEN / RESOLVED YTD / RECOVERED)

    @ViewBuilder
    private func kpiStrip(d: ShipperFreightClaimsAPI.Dashboard?) -> some View {
        let open = d.map { openClaimsMetric($0) }
            ?? unavailableMetric(label: "Open claims", kind: .open)
        let resolved = d.map { resolvedClaimsMetric($0) }
            ?? unavailableMetric(label: "Resolved claims", kind: .resolved)
        let average = FreightClaimsMetricPresenter.averageResolution(
            label: "Average resolution time",
            dashboard: d
        )
        let claimValue = FreightClaimsMetricPresenter.money(
            label: "Total claim value",
            dashboard: d,
            truth: d?.metricStates?.totalValue
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                kpiTile(
                    label: "OPEN",
                    metric: open,
                    sub: open.stateLabel,
                    valueStyle: .primary,
                    valueSize: 28,
                    subColor: shipperMetricStateColor(open)
                )
                kpiTile(
                    label: "RESOLVED",
                    metric: resolved,
                sub: "\(resolved.stateLabel)\n" + "Avg \(average.value) · \(average.stateLabel)",
                    valueStyle: .primary,
                    valueSize: 28,
                    subColor: shipperMetricStateColor(average),
                    accessibility: "\(resolved.accessibilityLabel) \(average.accessibilityLabel)"
                )
                kpiTile(
                    label: "CLAIM VALUE",
                    metric: claimValue,
                    sub: claimValue.stateLabel,
                    valueStyle: .gradient,
                    valueSize: 22,
                    subColor: shipperMetricStateColor(claimValue)
                )
            }
            if let d {
                dashboardProofRow(d)
            }
        }
    }

    @ViewBuilder
    private func kpiTile(
        label: String,
        metric: FreightClaimsMetricPresentation,
        sub: String,
        valueStyle: KpiValueStyle,
        valueSize: CGFloat,
        subColor: Color,
        accessibility: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 14)
                .padding(.leading, 14)
            valueText(metric.value, size: valueSize, style: valueStyle)
                .padding(.top, 12)
                .padding(.leading, 14)
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(subColor)
                .padding(.top, 6)
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .padding(.bottom, 14)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 118, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility ?? metric.accessibilityLabel)
    }

    @ViewBuilder
    private func valueText(_ value: String, size: CGFloat, style: KpiValueStyle) -> some View {
        switch style {
        case .gradient:
            Text(value)
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundStyle(LinearGradient.diagonal)
        case .primary:
            Text(value)
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
        case .success:
            Text(value)
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundStyle(Brand.success)
        case .danger:
            Text(value)
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundStyle(Brand.danger)
        }
    }

    private func openClaimsMetric(
        _ dashboard: ShipperFreightClaimsAPI.Dashboard
    ) -> FreightClaimsMetricPresentation {
        FreightClaimsMetricPresenter.count(
            label: "Open claims",
            value: dashboard.open,
            truth: dashboard.metricStates?.open,
            kind: .open,
            dashboardProvenance: dashboard.provenance
        )
    }

    private func resolvedClaimsMetric(
        _ dashboard: ShipperFreightClaimsAPI.Dashboard
    ) -> FreightClaimsMetricPresentation {
        FreightClaimsMetricPresenter.count(
            label: "Resolved claims",
            value: dashboard.resolved,
            truth: dashboard.metricStates?.resolved,
            kind: .resolved,
            dashboardProvenance: dashboard.provenance
        )
    }

    private func unavailableMetric(
        label: String,
        kind: FreightClaimsMetricKind
    ) -> FreightClaimsMetricPresentation {
        FreightClaimsMetricPresenter.count(
            label: label,
            value: nil,
            truth: nil,
            kind: kind,
            dashboardProvenance: nil
        )
    }

    private func dashboardProofRow(_ dashboard: ShipperFreightClaimsAPI.Dashboard) -> some View {
        let proof = FreightClaimsMetricPresenter.dashboardProof(dashboard.provenance)
        return HStack(spacing: Space.s2) {
            Image(systemName: dashboard.provenance == nil ? "questionmark.circle" : "checkmark.shield")
                .accessibilityHidden(true)
            Text(proof)
                .lineLimit(2)
        }
        .font(EType.micro)
        .foregroundStyle(palette.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dashboard provenance. \(proof).")
    }

    private func shipperMetricStateColor(_ metric: FreightClaimsMetricPresentation) -> Color {
        switch metric.valueState {
        case .measured:
            return metric.stateLabel == "Measured zero" ? Brand.success : palette.textSecondary
        case .measuredByDimension:
            return Brand.info
        case .partial:
            return Brand.warning
        case .noObservations, .notModeled, .none:
            return palette.textTertiary
        }
    }

    // MARK: Empty / unavailable truth states

    private func emptyHeroCard(metric: FreightClaimsMetricPresentation) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.bgCard)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)

            VStack(spacing: 12) {
                CheckCircleGlyph()
                    .frame(width: 48, height: 48)
                VStack(spacing: 4) {
                    Text("No open freight claims")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Measured zero in the authorized claims ledger.")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                    Text(metric.proofText)
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(20)
        }
        .frame(minHeight: 140)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No open freight claims. \(metric.accessibilityLabel)")
    }

    private func openClaimsTruthCard(_ metric: FreightClaimsMetricPresentation) -> some View {
        let copy = openClaimsTruthCopy(metric.valueState)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: copy.icon)
                    .foregroundStyle(shipperMetricStateColor(metric))
                Text(copy.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text(copy.detail)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(metric.proofText)
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(copy.title). \(copy.detail) \(metric.accessibilityLabel)")
    }

    private func openClaimsTruthCopy(
        _ state: FreightClaimsAPI.MetricValueState?
    ) -> (icon: String, title: String, detail: String) {
        switch state {
        case .noObservations:
            return (
                "tray",
                "No claim observations",
                "No freight claims were observed for this authorized company view."
            )
        case .partial:
            return (
                "circle.lefthalf.filled",
                "Open-claim count is partial",
                "The current count covers only part of the available claim record."
            )
        case .measuredByDimension:
            return (
                "square.grid.2x2",
                "Open claims measured by dimension",
                "The count is complete within its recorded dimensions, not as one undifferentiated total."
            )
        case .notModeled:
            return (
                "questionmark.circle",
                "Open claims not modeled",
                "This view does not currently calculate an open-claim count."
            )
        case .measured, .none:
            return (
                "exclamationmark.circle",
                "Open-claim truth unavailable",
                "The current response does not establish a measured open-claim total."
            )
        }
    }

    // MARK: Active claims block (when open > 0 — supplemental EXTRA-OK)

    @ViewBuilder
    private func activeClaimsBlock(dashboard d: ShipperFreightClaimsAPI.Dashboard,
                                   claims: [ShipperFreightClaimsAPI.ClaimRow]) -> some View {
        VStack(spacing: Space.s3) {
            agingCard(
                d.aging,
                metric: FreightClaimsMetricPresenter.count(
                    label: "Open claim aging",
                    value: d.aging.under30 + d.aging.days30to60 + d.aging.days60to90 + d.aging.over90,
                    truth: d.metricStates?.aging,
                    kind: .aging,
                    dashboardProvenance: d.provenance
                )
            )
            searchBar
            filterChipRow
            if claims.isEmpty {
                Text("No claims match this filter.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s4)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(claims.filter { !Self.resolvedStatuses.contains(($0.status ?? "").lowercased()) }) { row in
                        claimRow(row)
                    }
                }
            }
        }
    }

    // MARK: File a claim CTA

    private var fileClaimCTA: some View {
        Button(action: tapFileClaim) {
            HStack(spacing: 8) {
                ZStack {
                    Rectangle()
                        .fill(.white)
                        .frame(width: 14, height: 2.2)
                        .cornerRadius(1.1)
                    Rectangle()
                        .fill(.white)
                        .frame(width: 2.2, height: 14)
                        .cornerRadius(1.1)
                }
                .frame(width: 14, height: 14)
                Text("File a claim")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(LinearGradient.primary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("File a claim")
        .accessibilityHint("Opens the new-claim wizard")
    }

    // MARK: History card (resolved rows + see-all gradient mid-link)

    private func resolvedHistory(
        from claims: [ShipperFreightClaimsAPI.ClaimRow],
        dashboard: ShipperFreightClaimsAPI.Dashboard
    ) -> [ShipperFreightClaimsAPI.ClaimRow] {
        // Prefer resolved claims from the active list; fall back to
        // dashboard.recentClaims filtered to resolved.
        let inList = claims.filter { Self.resolvedStatuses.contains(($0.status ?? "").lowercased()) }
        if !inList.isEmpty { return Array(inList.prefix(3)) }
        return Array(dashboard.recentClaims.filter {
            Self.resolvedStatuses.contains(($0.status ?? "").lowercased())
        }.prefix(3))
    }

    private func historyCard(
        rows: [ShipperFreightClaimsAPI.ClaimRow],
        metric: FreightClaimsMetricPresentation
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { idx in
                historyRowView(rows[idx])
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                if idx < rows.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }
            Rectangle()
                .fill(palette.borderFaint)
                .frame(height: 1)
                .padding(.horizontal, 20)
            Button(action: tapSeeFullHistory) {
                Text("See full history → \(metric.value) resolved")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See full history. \(metric.accessibilityLabel)")
        }
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Open a claim's detail. Sheet→push: renders `ClaimDetailSheet`
    /// in-stack with a BespokeBackBar via the surface detail layer.
    /// `selected` is retained for any in-place readers; the push is the
    /// active presentation path.
    private func openClaim(_ row: ShipperFreightClaimsAPI.ClaimRow) {
        selected = row
        if let pushDetail {
            pushDetail("Freight Claim") {
                AnyView(
                    ClaimDetailSheet(claim: row)
                        .environment(\.palette, palette)
                )
            }
        }
    }

    @ViewBuilder
    private func historyRowView(_ row: ShipperFreightClaimsAPI.ClaimRow) -> some View {
        Button(action: { openClaim(row) }) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient.successTint)
                        .frame(width: 40, height: 40)
                    CheckPolyline()
                        .stroke(Brand.success,
                                style: StrokeStyle(lineWidth: 2.2,
                                                   lineCap: .round,
                                                   lineJoin: .round))
                        .frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(historyTitle(row))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(historyKicker(row))
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(historyTiming(row))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ClaimRowStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(historyTitle(row)). \(historyKicker(row)). \(historyTiming(row)).")
    }

    private func historyTitle(_ row: ShipperFreightClaimsAPI.ClaimRow) -> String {
        let kind = prettifyType(row.type)
        let amount = formatMoney(row.amount, currency: row.currency)
        return amount == "—" ? "\(kind) · settled" : "\(kind) · settled \(amount)"
    }

    private func historyKicker(_ row: ShipperFreightClaimsAPI.ClaimRow) -> String {
        var parts: [String] = []
        if let load = row.loadNumber, !load.isEmpty, load != "-" {
            parts.append(load)
        }
        if let description = row.description, !description.isEmpty {
            parts.append(description)
        }
        return parts.isEmpty ? row.claimNumber : parts.joined(separator: " · ")
    }

    private func historyTiming(_ row: ShipperFreightClaimsAPI.ClaimRow) -> String {
        if !row.filedDate.isEmpty {
            return "Filed \(row.filedDate) · resolved"
        }
        return "Resolved"
    }

    // MARK: Aging breakdown card (preserved)

    private func agingCard(
        _ aging: ShipperFreightClaimsAPI.AgingBuckets,
        metric: FreightClaimsMetricPresentation
    ) -> some View {
        let total = aging.under30 + aging.days30to60 + aging.days60to90 + aging.over90
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text("OPEN-CLAIM AGING")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(metric.value) open")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            if !metric.displaysMeasurement {
                Text(metric.stateLabel)
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.vertical, Space.s2)
            } else {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        agingSegment(width: width(for: aging.under30,    total: total, in: geo), color: Brand.success)
                        agingSegment(width: width(for: aging.days30to60, total: total, in: geo), color: Brand.info)
                        agingSegment(width: width(for: aging.days60to90, total: total, in: geo), color: Brand.warning)
                        agingSegment(width: width(for: aging.over90,     total: total, in: geo), color: Brand.danger)
                    }
                }
                .frame(height: 6)
                HStack(spacing: Space.s3) {
                    agingLegend(label: "<30d",    value: aging.under30,    color: Brand.success)
                    agingLegend(label: "30-60",   value: aging.days30to60, color: Brand.info)
                    agingLegend(label: "60-90",   value: aging.days60to90, color: Brand.warning)
                    agingLegend(label: ">90d",    value: aging.over90,     color: Brand.danger)
                }
            }
            Text("\(metric.stateLabel) · \(metric.proofText)")
                .font(EType.micro)
                .foregroundStyle(shipperMetricStateColor(metric))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            metric.displaysMeasurement
                ? "\(metric.accessibilityLabel) Under 30 days, \(aging.under30). 30 to 60 days, \(aging.days30to60). 60 to 90 days, \(aging.days60to90). Over 90 days, \(aging.over90)."
                : metric.accessibilityLabel
        )
    }

    private func width(for value: Int, total: Int, in geo: GeometryProxy) -> CGFloat {
        guard total > 0 else { return 0 }
        return geo.size.width * CGFloat(value) / CGFloat(total)
    }

    @ViewBuilder
    private func agingSegment(width: CGFloat, color: Color) -> some View {
        if width > 0 {
            Capsule().fill(color).frame(width: width, height: 6)
        }
    }

    private func agingLegend(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(value)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Search + filter (preserved)

    private var searchBar: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            TextField("Search claims by description", text: $store.searchTerm)
                .textFieldStyle(.plain)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await store.refresh() } }
            if !store.searchTerm.isEmpty {
                Button {
                    store.searchTerm = ""
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 10)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ClaimStatusFilter.allCases) { f in
                    filterChip(f)
                }
            }
        }
    }

    private func filterChip(_ f: ClaimStatusFilter) -> some View {
        let active = (store.filter == f)
        return Button {
            store.filter = f
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        } label: {
            HStack(spacing: 4) {
                Image(systemName: f.icon)
                    .font(.system(size: 10, weight: .heavy))
                Text(f.label)
                    .font(.system(size: 11, weight: .heavy))
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
            .background(
                Capsule().fill(active
                               ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                               : AnyShapeStyle(palette.bgCard))
            )
            .overlay(
                Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Active claim row (preserved)

    private func claimRow(_ row: ShipperFreightClaimsAPI.ClaimRow) -> some View {
        let sev = severityStyle(row.severity)
        let stColor = statusColor(row.status, palette: palette)
        return Button {
            openClaim(row)
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient.diagonal.opacity(0.15))
                    Image(systemName: typeIcon(row.type))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.claimNumber)
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textPrimary)
                        statusPill(label: row.status, color: stColor)
                        Spacer(minLength: 0)
                    }
                    Text(row.description?.isEmpty == false ? row.description! : "Description unavailable")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(prettifyType(row.type).uppercased())
                            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                        Text("·")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                        Text(sev.label.uppercased())
                            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(sev.color)
                        weatherPerilBadge(row)
                        Spacer(minLength: 4)
                        if !row.filedDate.isEmpty {
                            Text(row.filedDate)
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                if let value = row.amount,
                   let currency = row.currency {
                    Text(formatMoney(value, currency: currency))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(ClaimRowStyle())
        // Classify when the row renders. Failed reads remain unbadged.
        .task(id: row.id) { await store.classifyPeril(row) }
    }

    /// Bespoke weather-peril badge — a WeatherIcons alert glyph + the peril
    /// label, shown only when the classifier (or the deterministic type
    /// heuristic) flags the claim as weather-caused. ZERO SF Symbols.
    @ViewBuilder
    private func weatherPerilBadge(_ row: ShipperFreightClaimsAPI.ClaimRow) -> some View {
        if let cls = store.perils[row.id], cls.shouldBadge {
            HStack(spacing: 3) {
                WeatherIcons.utility(.alert, size: 9, tint: Brand.info)
                Text(cls.perilLabel.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.info)
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Brand.info.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Brand.info.opacity(0.35), lineWidth: 0.75))
            .accessibilityLabel("Weather peril claim. \(cls.perilLabel).")
        }
    }

    private func statusPill(label: String?, color: Color) -> some View {
        Text(prettifyType(label).uppercased())
            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.75))
    }

    // MARK: Notification posts (§20.4)

    private func tapFileClaim() {
        // Founder doctrine 2026-05-07: route to in-app composer
        // (386 FreightClaimComposer) instead of mailto:claims.
        // The composer handles photo uploads, load lookup, damage
        // description, and POSTs to freightClaims.create.
        NotificationCenter.default.post(
            name: .eusoShipperClaimFile,
            object: nil,
            userInfo: [
                "source": "219_ShipperFreightClaims",
                "shipperCompanyId": 1
            ]
        )
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap,
            object: nil,
            userInfo: ["screenId": "386"]
        )
    }

    private func tapSeeFullHistory() {
        // Real action: jump to 201 ShipperLoads with "claim" as the
        // search query so the row list narrows to load rows with
        // exception status. Replaces openURL stub.
        NotificationCenter.default.post(
            name: .eusoShipperClaimHistory,
            object: nil,
            userInfo: [
                "source": "219_ShipperFreightClaims",
                "shipperCompanyId": 1
            ]
        )
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "201", "query": "exception"]
        )
    }

    // MARK: Error banner

    private func errorBanner(_ msg: String) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Claims service offline")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private static let resolvedStatuses: Set<String> = ["settled", "paid", "closed"]

    private func formatMoney(
        _ value: Double?,
        currency: FreightClaimsAPI.CurrencyCode?
    ) -> String {
        guard let value, let currency else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value))
            ?? "\(currency.rawValue) \(value.formatted(.number.precision(.fractionLength(0))))"
    }
}

// MARK: - Press feedback

private struct ClaimRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - KPI value style

private enum KpiValueStyle { case gradient, primary, success, danger }

// MARK: - File-scoped paint extensions (§19.2)

private extension LinearGradient {
    static let successTint = LinearGradient(
        colors: [Brand.success.opacity(0.10), Brand.success.opacity(0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Glyph shapes (§19.2 file-scoped)

private struct CheckCircleGlyph: View {
    var body: some View {
        ZStack {
            Circle().fill(Brand.success.opacity(0.10))
            CheckPolyline()
                .stroke(Brand.success,
                        style: StrokeStyle(lineWidth: 2.4,
                                           lineCap: .round,
                                           lineJoin: .round))
                .padding(8)
        }
    }
}

private struct CheckPolyline: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let pStart  = CGPoint(x: rect.minX + rect.width * 0.25,
                              y: rect.minY + rect.height * 0.50)
        let pMiddle = CGPoint(x: rect.minX + rect.width * 0.45,
                              y: rect.minY + rect.height * 0.70)
        let pEnd    = CGPoint(x: rect.minX + rect.width * 0.75,
                              y: rect.minY + rect.height * 0.30)
        p.move(to: pStart)
        p.addLine(to: pMiddle)
        p.addLine(to: pEnd)
        return p
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// "File a claim" gradient pill tap.
    static let eusoShipperClaimFile    = Notification.Name("eusoShipperClaimFile")
    /// History row tap (currently routes through the existing `selected` sheet).
    static let eusoShipperClaimRow     = Notification.Name("eusoShipperClaimRow")
    /// "See full history" gradient mid-link tap.
    static let eusoShipperClaimHistory = Notification.Name("eusoShipperClaimHistory")
}

// MARK: - Detail sheet (preserved)

private struct ClaimDetailSheet: View {
    let claim: ShipperFreightClaimsAPI.ClaimRow
    @Environment(\.palette) private var palette
    @State private var presentingEvidence: Bool = false
    @State private var presentingDispute: Bool = false
    @State private var actionToast: String? = nil
    // Weather-peril classification + the cited weather.historical evidence the
    // claim references. Enterprise-gated → available:false → ENTERPRISE state.
    @State private var peril: ClaimPerilClassification? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                heroCard
                metaCard
                if let l = claim.loadNumber, !l.isEmpty, l != "-" {
                    associationCard(loadNumber: l)
                }
                if claim.description?.isEmpty == false {
                    descriptionCard
                }
                weatherEvidenceCard
                actionsCard
                Color.clear.frame(height: 48)
            }
            .padding(Space.s4)
        }
        .task(id: claim.id) { await classifyPeril() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage.ignoresSafeArea())
        .sheet(isPresented: $presentingEvidence) {
            AddEvidenceSheet(claim: claim) { msg in
                actionToast = msg
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $presentingDispute) {
            OpenDisputeSheet(claim: claim) { msg in
                actionToast = msg
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .bottom) {
            if let msg = actionToast {
                Text(msg)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        do {
                            try await Task.sleep(nanoseconds: 1_800_000_000)
                        } catch {
                            return
                        }
                        actionToast = nil
                    }
            }
        }
        .animation(.easeOut(duration: 0.18), value: actionToast)
    }

    private var heroCard: some View {
        let sev = severityStyle(claim.severity)
        let stColor = statusColor(claim.status, palette: palette)
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("CLAIM")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if let amount = claim.amount,
                   let currency = claim.currency {
                    Text(formatMoney(amount, currency: currency))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                }
            }
            Text(claim.claimNumber)
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
            HStack(spacing: 6) {
                pill(label: prettifyType(claim.type).uppercased(), color: Brand.info)
                pill(label: prettifyType(claim.status).uppercased(), color: stColor)
                pill(label: sev.label.uppercased(), color: sev.color)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var metaCard: some View {
        sectionCard(title: "FILED") {
            VStack(spacing: 6) {
                kvRow("Filed",   value: claim.filedDate.isEmpty ? "-" : claim.filedDate)
                kvRow("Carrier", value: (claim.carrier?.isEmpty == false && claim.carrier != "-")
                      ? claim.carrier!
                      : "-")
                kvRow("Shipper", value: (claim.shipper?.isEmpty == false && claim.shipper != "-")
                      ? claim.shipper!
                      : "-")
            }
        }
    }

    private func associationCard(loadNumber: String) -> some View {
        sectionCard(title: "ASSOCIATED LOAD") {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(loadNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
        }
    }

    private var descriptionCard: some View {
        sectionCard(title: "DESCRIPTION") {
            Text(claim.description ?? "Description unavailable")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Weather-peril classification

    @ViewBuilder
    private var weatherEvidenceCard: some View {
        if let peril, peril.shouldBadge {
            sectionCard(title: "WEATHER PERIL · CLASSIFICATION") {
                HStack(spacing: 8) {
                    WeatherIcons.utility(.alert, size: 12, tint: Brand.info)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(peril.perilLabel)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text(peril.weatherPeril.matchedTerms.isEmpty
                             ? "Classified from the stored claim narrative."
                             : "Matched narrative terms: \(peril.weatherPeril.matchedTerms.joined(separator: ", ")).")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func classifyPeril() async {
        if peril != nil { return }
        struct In: Encodable { let claimId: String }
        do {
            peril = try await EusoTripAPI.shared.query(
                "freightClaims.classifyClaimPeril", input: In(claimId: claim.id))
        } catch {
            peril = nil
        }
    }

    private var actionsCard: some View {
        sectionCard(title: "ACTIONS") {
            VStack(spacing: 6) {
                actionRow(
                    icon: "doc.badge.arrow.up",
                    title: "Add evidence",
                    subtitle: "Photos, BOL, POD, repair invoices."
                ) { presentingEvidence = true }

                actionRow(
                    icon: "person.2.wave.2.fill",
                    title: "Open dispute",
                    subtitle: "Escalate to mediator if the carrier denies the claim."
                ) { presentingDispute = true }
            }
        }
    }

    private func actionRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(LinearGradient.diagonal.opacity(0.15))
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(EType.micro).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .buttonStyle(ClaimRowStyle())
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            content()
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func kvRow(_ key: String, value: String) -> some View {
        HStack {
            Text(key)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
        }
    }

    private func pill(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.75))
    }

    private func formatMoney(
        _ value: Double?,
        currency: FreightClaimsAPI.CurrencyCode?
    ) -> String {
        guard let value, let currency else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value))
            ?? "\(currency.rawValue) \(value.formatted(.number.precision(.fractionLength(0))))"
    }
}

// MARK: - Previews

#Preview("219 · Freight Claims · Dark") {
    ShipperFreightClaims()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("219 · Freight Claims · Light") {
    ShipperFreightClaims()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}

// MARK: - AddEvidenceSheet
//
// Inline composer that posts to `freightClaims.addClaimEvidence`. Replaces
// the prior `MeAction.fire("claims.add-evidence")` stub. Server returns an
// uploadUrl iOS can later POST the binary blob to — for now we ship the
// metadata record (type + name + optional description + URL) which is the
// authoritative claim-trail entry.
private struct AddEvidenceSheet: View {
    let claim: ShipperFreightClaimsAPI.ClaimRow
    let onResult: (String) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var evidenceType: String = "photo"
    @State private var evidenceName: String = ""
    @State private var evidenceDescription: String = ""
    @State private var evidenceURL: String = ""
    @State private var submitting: Bool = false
    @State private var errorMsg: String? = nil
    @State private var requestKey = UUID()

    private let evidenceTypes: [(String, String)] = [
        ("photo", "Photo"),
        ("bol", TransportLexicon.generic(key: "billOfLading")),
        ("delivery_receipt", TransportLexicon.generic(key: "proofOfDelivery")),
        ("inspection_report", "Inspection report"),
        ("temperature_log", "Temperature log"),
        ("video", "Video"),
        ("witness_statement", "Witness statement"),
        ("police_report", "Police report"),
        ("weight_ticket", "Weight ticket"),
        ("other", "Other")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    section("EVIDENCE") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TYPE")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                                .foregroundStyle(palette.textTertiary)
                            Picker("Type", selection: $evidenceType) {
                                ForEach(evidenceTypes, id: \.0) { e in
                                    Text(e.1).tag(e.0)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        labeledField("Name (e.g. damage_photo_left.jpg)", text: $evidenceName)
                        labeledField("Description (optional)", text: $evidenceDescription)
                        labeledField("Hosted URL (optional, https://…)", text: $evidenceURL, keyboard: .URL)
                    }
                    if let err = errorMsg {
                        Text(err)
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(Brand.danger)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Brand.danger.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    submit
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("Add evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CLAIM \(claim.claimNumber)")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text("Add evidence to the claim file")
                .font(EType.body.weight(.bold))
                .foregroundStyle(palette.textPrimary)
            Text("Evidence is saved to the claim file. Paste a hosted link or open the upload sheet when available.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private func section<Inner: View>(_ title: String, @ViewBuilder content: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func labeledField(_ label: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
    }

    private var canSubmit: Bool {
        !evidenceName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var submit: some View {
        Button {
            doSubmit()
        } label: {
            HStack {
                if submitting { ProgressView().tint(.white) }
                else { Image(systemName: "paperclip") }
                Text(submitting ? "Saving…" : "Add evidence")
                    .font(EType.body.weight(.heavy))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(canSubmit && !submitting
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(Brand.neutral))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || submitting)
    }

    private func doSubmit() {
        submitting = true
        errorMsg = nil
        let trimmedDesc = evidenceDescription.trimmingCharacters(in: .whitespaces)
        let trimmedURL = evidenceURL.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                let name = evidenceName.trimmingCharacters(in: .whitespacesAndNewlines)
                let record = try await EusoTripAPI.shared.shipperFreightClaims.addClaimEvidence(
                    claimId: claim.id,
                    type: evidenceType,
                    name: name,
                    description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                    url: trimmedURL.isEmpty ? nil : trimmedURL,
                    requestKey: requestKey
                )
                guard record.claimId == claim.id,
                      record.type == evidenceType,
                      record.name == name else {
                    throw ClaimEvidenceConfirmationError.acknowledgementMismatch
                }
                if let mode = claim.transportMode, record.transportMode != mode {
                    throw ClaimEvidenceConfirmationError.transactionMismatch
                }
                if let reference = claim.referenceNumber,
                   !reference.isEmpty,
                   record.referenceNumber != reference {
                    throw ClaimEvidenceConfirmationError.transactionMismatch
                }
                guard let detail = try await EusoTripAPI.shared.shipperFreightClaims.getClaimById(id: claim.id),
                      detail.claimId == claim.id,
                      detail.evidence.contains(where: { $0.id == record.id }) else {
                    throw ClaimEvidenceConfirmationError.readbackMismatch
                }
                await MainActor.run {
                    submitting = false
                    onResult("Evidence confirmed on claim \(claim.claimNumber)")
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    submitting = false
                    errorMsg = "Couldn't add evidence: \(error.localizedDescription)"
                }
            }
        }
    }
}

private enum ClaimEvidenceConfirmationError: LocalizedError {
    case acknowledgementMismatch
    case transactionMismatch
    case readbackMismatch

    var errorDescription: String? {
        switch self {
        case .acknowledgementMismatch:
            return "The evidence acknowledgement did not match the submitted evidence."
        case .transactionMismatch:
            return "The evidence acknowledgement referenced a different freight transaction."
        case .readbackMismatch:
            return "The evidence was acknowledged but could not be confirmed on the claim record. Retry with the same request."
        }
    }
}

// MARK: - OpenDisputeSheet
//
// Inline composer that posts to `freightClaims.fileDispute`. Replaces the
// prior `MeAction.fire("claims.open-dispute")` stub. The dispute surface is
// distinct from the claim itself — disputes are mediator-routed; claims are
// damage / loss / shortage / delay records.
private struct OpenDisputeSheet: View {
    let claim: ShipperFreightClaimsAPI.ClaimRow
    let onResult: (String) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var disputeType: String = "rate"
    @State private var invoiceNumber: String = ""
    @State private var amountText: String = ""
    @State private var currencyText: String = ""
    @State private var description: String = ""
    @State private var submitting: Bool = false
    @State private var errorMsg: String? = nil

    private let disputeTypes: [(String, String)] = [
        ("rate", "Rate"),
        ("accessorial", "Accessorial"),
        ("detention", "Detention"),
        ("lumper", "Lumper"),
        ("fuel_surcharge", "Fuel surcharge"),
        ("duplicate_billing", "Duplicate billing"),
        ("service_failure", "Service failure"),
        ("contract_violation", "Contract violation")
    ]

    private var amount: Double? {
        Double(amountText.trimmingCharacters(in: .whitespaces))
    }

    private var currency: FreightClaimsAPI.CurrencyCode? {
        FreightClaimsAPI.CurrencyCode(rawValue: currencyText)
    }

    private var canSubmit: Bool {
        guard let amount, currency != nil else { return false }
        return !invoiceNumber.trimmingCharacters(in: .whitespaces).isEmpty &&
        amount > 0 &&
        description.trimmingCharacters(in: .whitespaces).count >= 10
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    section("DISPUTE") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TYPE")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                                .foregroundStyle(palette.textTertiary)
                            Picker("Type", selection: $disputeType) {
                                ForEach(disputeTypes, id: \.0) { d in
                                    Text(d.1).tag(d.0)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        labeledField("Invoice number", text: $invoiceNumber)
                        labeledField("Amount in the invoice currency", text: $amountText, keyboard: .decimalPad)
                        labeledField("Three-letter ISO currency", text: $currencyText)
                    }
                    section("DESCRIPTION") {
                        Text("MIN 10 CHARS")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                            .foregroundStyle(palette.textTertiary)
                        TextEditor(text: $description)
                            .frame(minHeight: 110)
                            .padding(8)
                            .background(palette.bgCardSoft)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    }
                    if let err = errorMsg {
                        Text(err)
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(Brand.danger)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Brand.danger.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    submit
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("Open dispute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CLAIM \(claim.claimNumber)")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text("File a formal dispute")
                .font(EType.body.weight(.bold))
                .foregroundStyle(palette.textPrimary)
            Text("Disputes route to a mediator and open a DSP-prefixed file you can track from the Disputes board.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private func section<Inner: View>(_ title: String, @ViewBuilder content: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func labeledField(_ label: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
    }

    private var submit: some View {
        Button {
            doSubmit()
        } label: {
            HStack {
                if submitting { ProgressView().tint(.white) }
                else { Image(systemName: "person.2.wave.2.fill") }
                Text(submitting ? "Filing…" : "File dispute")
                    .font(EType.body.weight(.heavy))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(canSubmit && !submitting
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(Brand.neutral))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || submitting)
    }

    private func doSubmit() {
        guard let amt = amount, amt > 0, let currency else { return }
        submitting = true
        errorMsg = nil
        Task {
            struct ReadbackInput: Encodable {
                let status: String?
                let type: String?
                let limit: Int
                let offset: Int
            }
            struct Readback: Decodable {
                struct Row: Decodable {
                    struct States: Decodable {
                        let amount: FreightClaimsAPI.MetricTruth
                    }
                    let id: String
                    let disputeNumber: String
                    let status: String
                    let amount: Double?
                    let currency: FreightClaimsAPI.CurrencyCode?
                    let invoiceNumber: String
                    let metricStates: States
                }
                let disputes: [Row]
            }
            do {
                let resp = try await EusoTripAPI.shared.shipperFreightClaims.fileDispute(
                    type: disputeType,
                    invoiceNumber: invoiceNumber.trimmingCharacters(in: .whitespaces),
                    amount: amt,
                    currency: currency,
                    description: description.trimmingCharacters(in: .whitespaces),
                    loadId: nil,
                    carrierId: nil
                )
                guard !resp.id.isEmpty,
                      !resp.disputeNumber.isEmpty,
                      resp.status.lowercased() == "filed",
                      abs(resp.amount - amt) < 0.005,
                      resp.currency == currency else {
                    throw FormalDisputeConfirmationError.invalidAcknowledgement
                }
                let readback: Readback = try await EusoTripAPI.shared.query(
                    "freightClaims.getDisputeResolution",
                    input: ReadbackInput(status: "filed", type: nil, limit: 50, offset: 0)
                )
                let invoice = invoiceNumber.trimmingCharacters(in: .whitespaces)
                guard readback.disputes.contains(where: {
                    $0.id == resp.id
                        && $0.disputeNumber == resp.disputeNumber
                        && $0.status.lowercased() == "filed"
                        && $0.invoiceNumber == invoice
                        && $0.currency == currency
                        && $0.metricStates.amount.valueState == .measured
                        && $0.metricStates.amount.accessState == .granted
                        && $0.metricStates.amount.trackingState == .tracked
                        && $0.metricStates.amount.provenance.source == "disputes.amountInDispute+baseCurrency"
                        && $0.amount.map { abs($0 - amt) < 0.005 } == true
                }) else {
                    throw FormalDisputeConfirmationError.readbackMismatch
                }
                await MainActor.run {
                    submitting = false
                    onResult("Dispute \(resp.disputeNumber) confirmed")
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    submitting = false
                    errorMsg = "Couldn't file dispute: \(error.localizedDescription)"
                }
            }
        }
    }
}

private enum FormalDisputeConfirmationError: LocalizedError {
    case invalidAcknowledgement
    case readbackMismatch

    var errorDescription: String? {
        switch self {
        case .invalidAcknowledgement:
            return "The dispute acknowledgement was incomplete."
        case .readbackMismatch:
            return "The dispute was acknowledged but could not be confirmed in the live dispute register."
        }
    }
}
