//
//  099_MeFreightClaims.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · Freight Claims)
//
//  Screen 099 · Me · Freight Claims — file and track cargo
//  damage / loss / shortage / delay / contamination claims from
//  the cab. Dashboard hero shows open / pending / resolved counts
//  plus total value in dispute. Aging strip surfaces claims
//  stuck in the pipeline >30 / 60 / 90 days so drivers can push
//  for resolution. Recent claims list with status chips.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Dashboard + claims + file all hit real `freightClaims.*`
//      procs — MCP-verified at
//      `frontend/server/routers/freightClaims.ts`.
//    • File mutation maps the driver's claim type to the
//      canonical `incidents.type` enum server-side — we pass the
//      driver-facing vocabulary (damage, loss, shortage, delay,
//      contamination) and the server auto-routes to the safety
//      workflow (property_damage, hazmat_spill, near_miss).
//    • No fabricated aging buckets. Counters reflect the
//      server's live view of the company's claims table.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero + submit CTA.
//         Brand.warning on aging >60d, Brand.magenta on >90d.
//    §4   Tokenized Space/Radius/EType throughout.
//

import SwiftUI

enum FreightClaimsMetricKind: Equatable {
    case open
    case pending
    case resolved
    case denied
    case totalValue
    case averageResolution
    case aging

    var sourceLabel: String {
        switch self {
        case .open, .pending, .resolved, .denied, .aging:
            return "Claims ledger"
        case .totalValue:
            return "Filed claim values"
        case .averageResolution:
            return "Claim timing history"
        }
    }
}

struct FreightClaimsMetricPresentation {
    let value: String
    let stateLabel: String
    let proofText: String
    let accessibilityLabel: String
    let valueState: FreightClaimsAPI.MetricValueState?
    let displaysMeasurement: Bool
}

enum FreightClaimsMetricPresenter {
    static func count(
        label: String,
        value: Int?,
        truth: FreightClaimsAPI.MetricTruth?,
        kind: FreightClaimsMetricKind,
        dashboardProvenance: FreightClaimsAPI.DashboardProvenance?
    ) -> FreightClaimsMetricPresentation {
        let displaysMeasurement = truth.map(measurementCanDisplay) ?? false
        let visibleValue = displaysMeasurement ? value.map(String.init) ?? "—" : "—"
        let measuredZero = displaysMeasurement && value == 0
        let stateLabel = stateLabel(
            truth: truth,
            measuredZero: measuredZero,
            dimensionCount: nil,
            unvaluedCount: nil,
            kind: kind
        )
        let proof = proofText(kind: kind, truth: truth, dashboardProvenance: dashboardProvenance)
        let accessibleValue = visibleValue == "—" ? "value unavailable" : visibleValue
        return FreightClaimsMetricPresentation(
            value: visibleValue,
            stateLabel: stateLabel,
            proofText: proof,
            accessibilityLabel: "\(label), \(accessibleValue). \(stateLabel). \(proof).",
            valueState: truth?.valueState,
            displaysMeasurement: displaysMeasurement && value != nil
        )
    }

    static func money(
        label: String,
        dashboard: FreightClaimsAPI.Dashboard?,
        truth: FreightClaimsAPI.MetricTruth?
    ) -> FreightClaimsMetricPresentation {
        let displaysMeasurement = truth.map(measurementCanDisplay) ?? false
        let dimensionCount = dashboard?.totalsByCurrency.count
        let unvaluedCount = dashboard?.unvaluedClaimCount
        let visibleValue: String
        let accessibleValue: String

        if displaysMeasurement, let dashboard {
            if let dimensionCount, dimensionCount > 1 {
                visibleValue = "\(dimensionCount) currencies"
                accessibleValue = dashboard.totalsByCurrency
                    .map { "\($0.currency.rawValue) \(plainNumber($0.amount))" }
                    .joined(separator: ", ")
            } else if let amount = dashboard.totalValue,
                      let currency = dashboard.totalValueCurrency {
                visibleValue = formatMoney(amount, currency: currency)
                accessibleValue = "\(currency.rawValue) \(plainNumber(amount))"
            } else if let total = dashboard.totalsByCurrency.first {
                visibleValue = formatMoney(total.amount, currency: total.currency)
                accessibleValue = "\(total.currency.rawValue) \(plainNumber(total.amount))"
            } else {
                visibleValue = "—"
                accessibleValue = "value unavailable"
            }
        } else {
            visibleValue = "—"
            accessibleValue = "value unavailable"
        }

        let stateLabel = stateLabel(
            truth: truth,
            measuredZero: dashboard?.totalValue == 0 && displaysMeasurement,
            dimensionCount: dimensionCount,
            unvaluedCount: unvaluedCount,
            kind: .totalValue
        )
        let proof = proofText(
            kind: .totalValue,
            truth: truth,
            dashboardProvenance: dashboard?.provenance
        )
        return FreightClaimsMetricPresentation(
            value: visibleValue,
            stateLabel: stateLabel,
            proofText: proof,
            accessibilityLabel: "\(label), \(accessibleValue). \(stateLabel). \(proof).",
            valueState: truth?.valueState,
            displaysMeasurement: displaysMeasurement && visibleValue != "—"
        )
    }

    static func averageResolution(
        label: String,
        dashboard: FreightClaimsAPI.Dashboard?
    ) -> FreightClaimsMetricPresentation {
        let truth = dashboard?.metricStates?.avgResolutionDays
        let displaysMeasurement = truth.map(measurementCanDisplay) ?? false
        let visibleValue: String
        let accessibleValue: String
        if displaysMeasurement, let average = dashboard?.avgResolutionDays {
            visibleValue = "\(Int(average.rounded()))d"
            accessibleValue = "\(average.formatted(.number.precision(.fractionLength(1)))) days"
        } else {
            visibleValue = "—"
            accessibleValue = "value unavailable"
        }
        let stateLabel = stateLabel(
            truth: truth,
            measuredZero: dashboard?.avgResolutionDays == 0 && displaysMeasurement,
            dimensionCount: nil,
            unvaluedCount: nil,
            kind: .averageResolution
        )
        let proof = proofText(
            kind: .averageResolution,
            truth: truth,
            dashboardProvenance: dashboard?.provenance
        )
        return FreightClaimsMetricPresentation(
            value: visibleValue,
            stateLabel: stateLabel,
            proofText: proof,
            accessibilityLabel: "\(label), \(accessibleValue). \(stateLabel). \(proof).",
            valueState: truth?.valueState,
            displaysMeasurement: displaysMeasurement && dashboard?.avgResolutionDays != nil
        )
    }

    static func dashboardProof(_ provenance: FreightClaimsAPI.DashboardProvenance?) -> String {
        guard let provenance else { return "Dashboard provenance unavailable" }
        return "Claims ledger · \(scopeLabel(provenance.scope)) · \(observationLabel(provenance.observedAt)) · \(calculationLabel(provenance.computedAt))"
    }

    private static func measurementCanDisplay(_ truth: FreightClaimsAPI.MetricTruth) -> Bool {
        guard truth.accessState == .granted else { return false }
        guard truth.trackingState == .tracked else { return false }
        switch truth.valueState {
        case .measured, .measuredByDimension, .partial:
            return true
        case .noObservations, .notModeled:
            return false
        }
    }

    private static func stateLabel(
        truth: FreightClaimsAPI.MetricTruth?,
        measuredZero: Bool,
        dimensionCount: Int?,
        unvaluedCount: Int?,
        kind: FreightClaimsMetricKind
    ) -> String {
        guard let truth else { return "Truth unavailable" }
        guard truth.accessState == .granted else {
            return truth.accessState == .restricted ? "Restricted" : "Access unknown"
        }
        guard truth.trackingState == .tracked else { return "Not tracked" }
        switch truth.valueState {
        case .measured:
            return measuredZero ? "Measured zero" : "Measured"
        case .measuredByDimension:
            return kind == .totalValue ? "Measured by currency" : "Measured by dimension"
        case .partial:
            var parts = ["Partial"]
            if kind == .totalValue, let dimensionCount, dimensionCount > 1 {
                parts.append("\(dimensionCount) currencies")
            }
            if let unvaluedCount, unvaluedCount > 0 {
                parts.append("\(unvaluedCount) unvalued")
            }
            return parts.joined(separator: " · ")
        case .noObservations:
            return "No observations"
        case .notModeled:
            return "Not modeled"
        }
    }

    private static func proofText(
        kind: FreightClaimsMetricKind,
        truth: FreightClaimsAPI.MetricTruth?,
        dashboardProvenance: FreightClaimsAPI.DashboardProvenance?
    ) -> String {
        guard let truth else { return "Provenance unavailable" }
        if truth.accessState != .granted {
            let access = truth.accessState == .restricted ? "Metric access restricted" : "Metric access unknown"
            return "\(access) · \(calculationLabel(truth.provenance.computedAt))"
        }
        if truth.valueState == .notModeled || truth.trackingState == .notTracked {
            return "No measurement source · \(calculationLabel(truth.provenance.computedAt))"
        }
        if truth.valueState == .noObservations {
            return "\(kind.sourceLabel) · No source observation · \(calculationLabel(truth.provenance.computedAt))"
        }
        return "\(kind.sourceLabel) · \(scopeLabel(dashboardProvenance?.scope)) · \(observationLabel(truth.provenance.observedAt)) · \(calculationLabel(truth.provenance.computedAt))"
    }

    private static func scopeLabel(_ scope: String?) -> String {
        switch scope {
        case "platform": return "Platform records"
        case "transaction_party_company": return "Company transactions"
        default: return "Authorized records"
        }
    }

    private static func observationLabel(_ iso: String?) -> String {
        guard let iso, let date = parseISO8601(iso) else { return "observation time unavailable" }
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 { return "updated just now" }
        if elapsed < 3_600 { return "updated \(Int(elapsed / 60))m ago" }
        if elapsed < 86_400 { return "updated \(Int(elapsed / 3_600))h ago" }
        if elapsed < 604_800 { return "updated \(Int(elapsed / 86_400))d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "updated \(formatter.string(from: date))"
    }

    private static func calculationLabel(_ iso: String?) -> String {
        guard let iso, let date = parseISO8601(iso) else { return "calculation time unavailable" }
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 { return "calculated just now" }
        if elapsed < 3_600 { return "calculated \(Int(elapsed / 60))m ago" }
        if elapsed < 86_400 { return "calculated \(Int(elapsed / 3_600))h ago" }
        return "calculated \(Int(elapsed / 86_400))d ago"
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func formatMoney(
        _ value: Double,
        currency: FreightClaimsAPI.CurrencyCode
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value))
            ?? "\(currency.rawValue) \(plainNumber(value))"
    }

    private static func plainNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

// MARK: - Screen root

struct MeFreightClaims: View {
    @Environment(\.palette) var palette
    @StateObject private var store = FreightClaimsStore()

    @State private var showingFile = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                counterStrip
                agingSection
                fileCTA
                claimsSection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .eusoRefreshable { await store.refresh() }
        .sheet(isPresented: $showingFile) {
            FileClaimSheet(store: store)
                .eusoSheetX()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Freight Claims")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Cargo damage · loss · shortage · delay · contamination")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                Text("Truck / trailer mechanical + accident → Zeun")
                    .font(EType.micro)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary.opacity(0.8))
            }
            Spacer()
            OrbeSang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Counter strip

    private var counterStrip: some View {
        let d = store.dashboard
        let open = FreightClaimsMetricPresenter.count(
            label: "Open claims",
            value: d?.open,
            truth: d?.metricStates?.open,
            kind: .open,
            dashboardProvenance: d?.provenance
        )
        let pending = FreightClaimsMetricPresenter.count(
            label: "Pending claims",
            value: d?.pending,
            truth: d?.metricStates?.pending,
            kind: .pending,
            dashboardProvenance: d?.provenance
        )
        let resolved = FreightClaimsMetricPresenter.count(
            label: "Resolved claims",
            value: d?.resolved,
            truth: d?.metricStates?.resolved,
            kind: .resolved,
            dashboardProvenance: d?.provenance
        )
        let denied = FreightClaimsMetricPresenter.count(
            label: "Denied claims",
            value: d?.denied,
            truth: d?.metricStates?.denied,
            kind: .denied,
            dashboardProvenance: d?.provenance
        )
        let claimValue = FreightClaimsMetricPresenter.money(
            label: "Total claim value",
            dashboard: d,
            truth: d?.metricStates?.totalValue
        )
        let average = FreightClaimsMetricPresenter.averageResolution(
            label: "Average resolution time",
            dashboard: d
        )
        return VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                countTile(label: "OPEN", metric: open, gradient: true)
                countTile(label: "PENDING", metric: pending, gradient: false)
                countTile(label: "RESOLVED", metric: resolved, gradient: false)
                countTile(label: "DENIED", metric: denied, gradient: false)
            }
            HStack(spacing: Space.s2) {
                moneyTile(label: "TOTAL VALUE", metric: claimValue)
                metaTile(label: "AVG RESOLUTION", metric: average)
            }
            if let d {
                dashboardProofRow(d)
            }
        }
    }

    private func countTile(
        label: String,
        metric: FreightClaimsMetricPresentation,
        gradient: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(metric.value)
                .font(EType.bodyStrong)
                .foregroundStyle(gradient
                                 ? AnyShapeStyle(LinearGradient.diagonal)
                                 : AnyShapeStyle(palette.textPrimary))
                .monospacedDigit()
            Text(metric.stateLabel)
                .font(EType.micro)
                .foregroundStyle(metricStateColor(metric))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 88, alignment: .topLeading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.accessibilityLabel)
    }

    private func moneyTile(
        label: String,
        metric: FreightClaimsMetricPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(metric.value)
                .font(EType.numeric)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(metric.stateLabel)
                .font(EType.micro)
                .foregroundStyle(metricStateColor(metric))
                .lineLimit(2)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 88, alignment: .topLeading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.accessibilityLabel)
    }

    private func metaTile(
        label: String,
        metric: FreightClaimsMetricPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(metric.value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Text(metric.stateLabel)
                .font(EType.micro)
                .foregroundStyle(metricStateColor(metric))
                .lineLimit(2)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 88, alignment: .topLeading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.accessibilityLabel)
    }

    private func dashboardProofRow(_ dashboard: FreightClaimsAPI.Dashboard) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: dashboard.provenance == nil ? "questionmark.circle" : "checkmark.shield")
                .accessibilityHidden(true)
            Text(FreightClaimsMetricPresenter.dashboardProof(dashboard.provenance))
                .lineLimit(2)
        }
        .font(EType.micro)
        .foregroundStyle(palette.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Dashboard provenance. \(FreightClaimsMetricPresenter.dashboardProof(dashboard.provenance))."
        )
    }

    private func metricStateColor(_ metric: FreightClaimsMetricPresentation) -> Color {
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

    // MARK: Aging

    @ViewBuilder
    private var agingSection: some View {
        if let dashboard = store.dashboard {
            let aging = dashboard.aging
            let total = aging.under30 + aging.days30to60 + aging.days60to90 + aging.over90
            let metric = FreightClaimsMetricPresenter.count(
                label: "Open claim aging",
                value: total,
                truth: dashboard.metricStates?.aging,
                kind: .aging,
                dashboardProvenance: dashboard.provenance
            )
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("AGING")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                if metric.displaysMeasurement {
                    HStack(spacing: Space.s2) {
                        agingTile(label: "<30D",    count: aging.under30,    tint: palette.textSecondary)
                        agingTile(label: "30-60D",  count: aging.days30to60, tint: palette.textPrimary)
                        agingTile(label: "60-90D",  count: aging.days60to90, tint: Brand.warning)
                        agingTile(label: ">90D",    count: aging.over90,     tint: Brand.magenta)
                    }
                }
                Text("\(metric.stateLabel) · \(metric.proofText)")
                    .font(EType.micro)
                    .foregroundStyle(metricStateColor(metric))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                metric.displaysMeasurement
                    ? "\(metric.accessibilityLabel) Under 30 days, \(aging.under30). 30 to 60 days, \(aging.days30to60). 60 to 90 days, \(aging.days60to90). Over 90 days, \(aging.over90)."
                    : metric.accessibilityLabel
            )
        }
    }

    private func agingTile(label: String, count: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(palette.textTertiary)
            Text("\(count)")
                .font(EType.bodyStrong)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 0.5)
                )
        )
    }

    // MARK: File CTA

    private var fileCTA: some View {
        Button {
            showingFile = true
        } label: {
            HStack {
                Image(systemName: "plus.rectangle.on.rectangle")
                Text("File a claim")
                Spacer()
                Image(systemName: "arrow.right")
            }
            .font(EType.bodyStrong)
            .foregroundStyle(.white)
            .padding(Space.s3)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient.diagonal)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Claims

    private var claimsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("RECENT CLAIMS")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            if store.claims.isEmpty, let error = store.lastError, !store.isLoading {
                EusoEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "Claims unavailable",
                    subtitle: error.eusoUserCopy
                )
            } else if store.claims.isEmpty && !store.isLoading {
                EusoEmptyState(
                    systemImage: "shippingbox",
                    title: "No claims filed",
                    subtitle: "If something gets damaged, short or contaminated on your next load, file it here so safety + billing can pull POD photos + start recovery."
                )
            } else {
                ForEach(store.claims, id: \.stableId) { c in
                    claimRow(c)
                }
            }
        }
    }

    private func claimRow(_ c: FreightClaimsAPI.Claim) -> some View {
        let statusLower = (c.status ?? "").lowercased()
        return HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: claimTypeIcon(c.type))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.5))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(c.type.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
                     ?? "Claim type unavailable")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                if let desc = c.description, !desc.isEmpty {
                    Text(desc)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                if let ts = c.createdAt {
                    Text(relativeTime(ts))
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
            statusChip(statusLower)
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    private func claimTypeIcon(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "property_damage":      return "shippingbox.and.arrow.backward"
        case "hazmat_spill":         return "exclamationmark.triangle"
        case "near_miss":            return "clock.badge.exclamationmark"
        default:                     return "doc.text"
        }
    }

    @ViewBuilder
    private func statusChip(_ status: String) -> some View {
        let (label, tint, filled): (String, Color, Bool) = {
            switch status {
            case "resolved", "approved", "paid":
                return (status.uppercased(), .green, true)
            case "denied", "disputed":
                return (status.uppercased(), Brand.magenta, false)
            case "investigating", "open":
                return (status.uppercased(), Brand.warning, false)
            default:
                return (status.isEmpty ? "STATUS UNKNOWN" : status.uppercased(), palette.textTertiary, false)
            }
        }()
        Text(label)
            .font(EType.micro)
            .tracking(1.2)
            .foregroundStyle(filled ? .white : tint)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .background(
                Group {
                    if filled {
                        Capsule().fill(LinearGradient.diagonal)
                    } else {
                        Capsule().stroke(tint, lineWidth: 1)
                    }
                }
            )
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Space.s1) {
            Text("Notice and filing deadlines vary by contract, mode, and jurisdiction. Preserve the cargo condition and file promptly.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Text("Accident? Breakdown? Mechanical? That flow lives in Zeun. DVIR, roadside, provider dispatch all route through there.")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.s2)
    }

    // MARK: Helpers

    private func relativeTime(_ iso: String) -> String {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = full.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "" }
        let s = -date.timeIntervalSinceNow
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86400 { return "\(Int(s / 3600))h ago" }
        return "\(Int(s / 86400))d ago"
    }
}

// MARK: - File sheet

private struct FileClaimSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: FreightClaimsStore

    @State private var loadId: String = ""
    @State private var type: FreightClaimsAPI.ClaimType = .damage
    @State private var amount: String = ""
    @State private var currencyCode: String = ""
    @State private var commodity: String = ""
    @State private var expectedQuantity: String = ""
    @State private var receivedQuantity: String = ""
    @State private var quantityUnit: String = ""
    @State private var description: String = ""
    @State private var damageExtent: String = ""
    @State private var submitError: String?
    @State private var requestKey = UUID()

    private let truckClaimTypes: [FreightClaimsAPI.ClaimType] = [
        .damage, .loss, .shortage, .delay, .contamination, .overcharge
    ]

    private var parsedAmount: Double? {
        guard let value = Double(amount.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite, value > 0 else { return nil }
        return value
    }

    private var parsedCurrency: FreightClaimsAPI.CurrencyCode? {
        FreightClaimsAPI.CurrencyCode(rawValue: currencyCode)
    }

    private var isCurrencyValid: Bool {
        currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedCurrency != nil
    }

    private var parsedExpectedQuantity: Double? { parsedQuantity(expectedQuantity, allowsZero: false) }
    private var parsedReceivedQuantity: Double? { parsedQuantity(receivedQuantity, allowsZero: true) }
    private var isQuantityValid: Bool {
        guard type == .shortage else { return true }
        guard let expected = parsedExpectedQuantity, let received = parsedReceivedQuantity else { return false }
        return received < expected
            && !quantityUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && quantityUnit.trimmingCharacters(in: .whitespacesAndNewlines).count <= 32
    }

    private var canSubmit: Bool {
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return !loadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && desc.count >= 10
            && parsedAmount != nil
            && isCurrencyValid
            && isQuantityValid
            && !store.isFiling
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Load") {
                    TextField("Load ID or number", text: $loadId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Claim type") {
                    Picker("Type", selection: $type) {
                        ForEach(truckClaimTypes) { t in
                            Label(t.label, systemImage: t.icon).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Amount") {
                    TextField("Claim amount", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("Currency code (optional)", text: $currencyCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityHint("Enter a three-letter currency code only when it is known")
                    if !isCurrencyValid {
                        Text("Use a three-letter currency code, or leave it blank to use the load's recorded currency.")
                            .font(EType.caption)
                            .foregroundStyle(Brand.warning)
                    }
                }
                Section("Commodity (optional)") {
                    TextField("e.g. 24 pallets pharma cold chain", text: $commodity)
                }
                if type == .shortage {
                    Section("Quantity evidence") {
                        TextField("Expected quantity", text: $expectedQuantity)
                            .keyboardType(.decimalPad)
                        TextField("Received quantity", text: $receivedQuantity)
                            .keyboardType(.decimalPad)
                        TextField("Unit, e.g. lb, kg, gal, bbl, MT", text: $quantityUnit)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !isQuantityValid {
                            Text("A shortage requires a positive expected quantity, a lower non-negative received quantity, and its unit.")
                                .font(EType.caption)
                                .foregroundStyle(Brand.warning)
                        }
                    }
                }
                Section("Description (≥10 chars)") {
                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                }
                Section("Damage extent (optional)") {
                    TextField("e.g. 4 pallets wet, 12 cases crushed", text: $damageExtent)
                }
                if let err = submitError {
                    Section {
                        Text(err)
                            .foregroundStyle(Brand.warning)
                            .font(EType.caption)
                    }
                }
            }
            .navigationTitle("File freight claim")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if store.isFiling {
                            ProgressView()
                        } else {
                            Text("File").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private func submit() async {
        submitError = nil
        guard let amount = parsedAmount else {
            submitError = "Enter a positive claim amount."
            return
        }
        do {
            _ = try await store.fileClaim(
                FreightClaimsAPI.FileClaimRequest(
                    reference: .truck(loadId.trimmingCharacters(in: .whitespacesAndNewlines)),
                    type: type,
                    amount: amount,
                    currency: parsedCurrency,
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    commodity: optionalText(commodity),
                    weight: nil,
                    weightUnit: nil,
                    expectedQuantity: type == .shortage ? parsedExpectedQuantity : nil,
                    receivedQuantity: type == .shortage ? parsedReceivedQuantity : nil,
                    quantityUnit: type == .shortage ? optionalText(quantityUnit) : nil,
                    damageExtent: optionalText(damageExtent),
                    discoveredAt: nil,
                    evidenceIds: nil,
                    requestKey: requestKey
                )
            )
            dismiss()
        } catch {
            submitError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't file claim, try again in a moment."
        }
    }

    private func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parsedQuantity(_ value: String, allowsZero: Bool) -> Double? {
        guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              number.isFinite,
              allowsZero ? number >= 0 : number > 0 else { return nil }
        return number
    }
}

// MARK: - Screen wrapper

struct MeFreightClaimsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeFreightClaims()
        } nav: {
            BottomNav(
                leading: driverNavLeading_099(),
                trailing: driverNavTrailing_099(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_099() -> [NavSlot] {
    RoleNav.driverLeading(current: .none)
}
private func driverNavTrailing_099() -> [NavSlot] {
    RoleNav.driverTrailing(current: .me)
}

// MARK: - Previews

#Preview("099 · Freight Claims · Night") {
    MeFreightClaimsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("099 · Freight Claims · Afternoon") {
    MeFreightClaimsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
