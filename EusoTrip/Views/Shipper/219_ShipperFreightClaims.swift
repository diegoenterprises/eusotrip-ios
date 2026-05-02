//
//  219_ShipperFreightClaims.swift
//  EusoTrip 2027 UI — Shipper · Freight Claims (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/219_ShipperFreightClaims.swift. Persona: Diego
//  Usoro / Eusorone Technologies (companyId 1) per §11. Resolved
//  history rows reference the §11.2 MATRIX-50 audit trail — claim
//  records join historical `loads` rows on the LD- hex tail (e.g.
//  LD-260224, LD-260118, LD-251114). When the active set is on the
//  MATRIX-50-2026-04-26 batch (UN1203 gasoline / NH₃ MC-306 /
//  reefer berries) the hero counter reads "0 OPEN · {N} PAID YTD"
//  in textTertiary because clean-record is the canonical Diego
//  posture. The primary surface is the clean-record claims summary
//  (3-tile KPI strip · empty-state success hero · File-a-claim CTA
//  · resolved history rows with success-tinted check glyphs). When
//  open claims exist, the empty hero swaps for the AGING breakdown
//  + filter row + claim list (real backend wiring preserved).
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · FREIGHT CLAIMS / "{N} OPEN · {M} PAID YTD"
//    2. Title block      Freight claims / "Damage · short · loss · contamination · temp excursion"
//    3. IridescentHairline
//    4. KPI strip        OPEN (success-sub when 0) · RESOLVED YTD (avg cycle) · RECOVERED (gradient $)
//    5. OPEN CLAIMS section eyebrow
//        - empty path:  empty-state success hero (CheckCircleGlyph + clean-record copy)
//        - active path: AGING breakdown card + search · filter chips · claim list
//    6. File a claim     gradient pill CTA (always present)
//    7. CLAIM HISTORY · {N} RESOLVED — 3 resolved rows with success-tinted
//                        check glyphs + "See full history" gradient mid-link
//
//  Real wiring preserved: `freightClaims.getClaimsDashboard` +
//  `freightClaims.getClaims(...)` via `ShipperFreightClaimsStore`.
//  Detail sheet (preserved) opens on row tap with hero / meta /
//  association / description / actions cards.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2124 — `freightClaims.fileClaim` not yet on iOS API
//                surface. File-a-claim CTA posts notification only;
//                wizard intake (type · severity · description ·
//                evidence · valuation) lands when backend ships.
//    EUSO-2125 — `dashboard.totalValue` is the lifetime aggregate.
//                Wireframe RECOVERED tile sub-line wants per-year
//                breakdown ("2024 + 2025 + 2026"); paint single
//                lifetime sub-line until per-year split ships.
//
//  Doctrine refs: §2 ME-tab nav (handled by ContentView); §3
//  numbers-first copy ("0 OPEN · 1 PAID YTD"); §4.3 single
//  iridescent hairline; §11 Diego canon; §15.2 gradient mid-link
//  recipe; §17.2 success-tinted check-circle glyph; §19.2 file-
//  scoped paint extensions; §20.4 no dead buttons; §22.2 counter
//  color (textTertiary informational).
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
        case .pending:  return "reported"
        case .resolved: return "resolved"
        case .denied:   return "denied"
        }
    }
}

// MARK: - Store (preserved)

@MainActor
final class ShipperFreightClaimsStore: ObservableObject {
    enum LoadState {
        case loading
        case empty
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

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
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
            if dashboard.recentClaims.isEmpty && listResponse.claims.isEmpty
                && dashboard.open == 0 && dashboard.pending == 0
                && dashboard.resolved == 0 {
                state = .empty
            } else {
                state = .loaded(dashboard: dashboard, claims: listResponse.claims)
            }
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
    default:           return SeverityStyle(label: (raw ?? "—").capitalized, color: Brand.info)
    }
}

private func statusColor(_ raw: String, palette: Theme.Palette) -> Color {
    switch raw.lowercased() {
    case "investigating", "open":     return Brand.warning
    case "reported", "pending":       return Brand.info
    case "resolved":                  return Brand.success
    case "denied", "rejected":        return Brand.danger
    case "paid":                      return Brand.success
    default:                           return palette.textSecondary
    }
}

private func typeIcon(_ raw: String) -> String {
    switch raw.lowercased() {
    case "damage":         return "hammer.fill"
    case "loss":           return "questionmark.diamond.fill"
    case "shortage":       return "minus.diamond.fill"
    case "delay":          return "clock.badge.exclamationmark.fill"
    case "contamination":  return "drop.triangle.fill"
    case "theft":          return "lock.shield.fill"
    default:                return "shippingbox.and.arrow.backward.fill"
    }
}

private func prettifyType(_ raw: String) -> String {
    raw.replacingOccurrences(of: "_", with: " ").capitalized
}

// MARK: - Screen root

struct ShipperFreightClaims: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .refreshable { await store.refresh() }
        .sheet(item: $selected) { row in
            ClaimDetailSheet(claim: row)
                .environment(\.palette, palette)
                .presentationDragIndicator(.visible)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18),
            value: store.filter
        )
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · FREIGHT CLAIMS")
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
            return "\(d.open) OPEN · \(d.resolved) PAID YTD"
        }
        return "—"
    }

    private var counterAccessibility: String {
        if case .loaded(let d, _) = store.state {
            return "\(d.open) open claims, \(d.resolved) paid year to date"
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
            Text("Damage · short · loss · contamination · temp excursion")
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
        case .empty:
            VStack(alignment: .leading, spacing: 0) {
                kpiStrip(d: nil)
                    .padding(.horizontal, Space.s5)
                sectionLabel("OPEN CLAIMS")
                    .padding(.top, Space.s4)
                emptyHeroCard
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)
                fileClaimCTA
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)
            }
        case .error(let msg):
            errorBanner(msg)
                .padding(.horizontal, Space.s5)
        case .loaded(let dashboard, let claims):
            VStack(alignment: .leading, spacing: 0) {
                kpiStrip(d: dashboard)
                    .padding(.horizontal, Space.s5)

                sectionLabel("OPEN CLAIMS")
                    .padding(.top, Space.s4)

                if dashboard.open == 0 {
                    emptyHeroCard
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)
                } else {
                    activeClaimsBlock(dashboard: dashboard, claims: claims)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)
                }

                fileClaimCTA
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)

                let history = resolvedHistory(from: claims, dashboard: dashboard)
                if !history.isEmpty {
                    sectionLabel("CLAIM HISTORY · \(dashboard.resolved) RESOLVED")
                        .padding(.top, Space.s5)
                    historyCard(rows: history, total: dashboard.resolved)
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
        let openValue     = d.map { "\($0.open)" } ?? "—"
        let openSub       = (d?.open ?? 0) == 0 ? "none active" : "needs triage"
        let openSubTone: SubTone = (d?.open ?? 0) == 0 ? .success : .secondary
        let resolvedValue = d.map { "\($0.resolved)" } ?? "—"
        let resolvedSub: String = {
            guard let d, d.avgResolutionDays > 0 else { return "avg cycle —" }
            return "avg cycle \(Int(d.avgResolutionDays.rounded())) days"
        }()
        let recoveredValue = d.map { formatMoney($0.totalValue) } ?? "—"
        // EUSO-2125 — per-year breakdown not on API surface.
        let recoveredSub = d.map { _ in "lifetime · per-year split pending" } ?? "—"

        HStack(spacing: 8) {
            kpiTile(label: "OPEN",
                    value: openValue,
                    sub:   openSub,
                    valueStyle: .primary,
                    valueSize: 28,
                    subTone: openSubTone)
            kpiTile(label: "RESOLVED YTD",
                    value: resolvedValue,
                    sub:   resolvedSub,
                    valueStyle: .primary,
                    valueSize: 28,
                    subTone: .secondary)
            kpiTile(label: "RECOVERED",
                    value: recoveredValue,
                    sub:   recoveredSub,
                    valueStyle: .gradient,
                    valueSize: 22,
                    subTone: .secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func kpiTile(label: String,
                         value: String,
                         sub: String,
                         valueStyle: KpiValueStyle,
                         valueSize: CGFloat,
                         subTone: SubTone) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 14)
                .padding(.leading, 14)
            valueText(value, size: valueSize, style: valueStyle)
                .padding(.top, 12)
                .padding(.leading, 14)
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(subTone.color(palette: palette))
                .padding(.top, 6)
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .padding(.bottom, 14)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 96)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    // MARK: Empty hero card (clean-record success message)

    private var emptyHeroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.bgCard)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)

            VStack(spacing: 12) {
                CheckCircleGlyph()
                    .frame(width: 48, height: 48)
                VStack(spacing: 4) {
                    Text("No open claims · clean record")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("All deliveries closed without dispute")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(20)
        }
        .frame(minHeight: 140)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No open claims, clean record. All deliveries closed without dispute.")
    }

    // MARK: Active claims block (when open > 0 — supplemental EXTRA-OK)

    @ViewBuilder
    private func activeClaimsBlock(dashboard d: ShipperFreightClaimsAPI.Dashboard,
                                   claims: [ShipperFreightClaimsAPI.ClaimRow]) -> some View {
        VStack(spacing: Space.s3) {
            agingCard(d.aging)
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
                    ForEach(claims.filter { $0.status.lowercased() != "resolved" }) { row in
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
            .clipShape(Capsule())
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
        let inList = claims.filter { $0.status.lowercased() == "resolved" }
        if !inList.isEmpty { return Array(inList.prefix(3)) }
        return Array(dashboard.recentClaims.filter { $0.status.lowercased() == "resolved" }.prefix(3))
    }

    private func historyCard(rows: [ShipperFreightClaimsAPI.ClaimRow], total: Int) -> some View {
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
                Text("See full history → \(total) resolved")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See full history. \(total) resolved claims.")
        }
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func historyRowView(_ row: ShipperFreightClaimsAPI.ClaimRow) -> some View {
        Button(action: { selected = row }) {
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
        let amt = row.amount > 0 ? formatMoney(row.amount) : "—"
        return "\(kind) · settled \(amt)"
    }

    private func historyKicker(_ row: ShipperFreightClaimsAPI.ClaimRow) -> String {
        var parts: [String] = []
        if let load = row.loadNumber, !load.isEmpty, load != "-" {
            parts.append(load)
        }
        if !row.description.isEmpty {
            parts.append(row.description)
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

    private func agingCard(_ aging: ShipperFreightClaimsAPI.AgingBuckets) -> some View {
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
                Text("\(total) open")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            if total == 0 {
                Text("No open claims — every filed claim is moving.")
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
            selected = row
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
                    Text(row.description.isEmpty ? "—" : row.description)
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
                        Spacer(minLength: 4)
                        if !row.filedDate.isEmpty {
                            Text(row.filedDate)
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                if row.amount > 0 {
                    Text(formatMoney(row.amount))
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
    }

    private func statusPill(label: String, color: Color) -> some View {
        Text(prettifyType(label).uppercased())
            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.75))
    }

    // MARK: Notification posts (§20.4)

    private func tapFileClaim() {
        NotificationCenter.default.post(
            name: .eusoShipperClaimFile,
            object: nil,
            userInfo: [
                "source": "219_ShipperFreightClaims",
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapSeeFullHistory() {
        NotificationCenter.default.post(
            name: .eusoShipperClaimHistory,
            object: nil,
            userInfo: [
                "source": "219_ShipperFreightClaims",
                "shipperCompanyId": 1
            ]
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

    private func formatMoney(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 1_000_000 { return String(format: "$%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "$%.0fk", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n == 0          { return "—" }
        return "$\(n)"
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

// MARK: - KPI value style + sub-line tone

private enum KpiValueStyle { case gradient, primary, success, danger }

private enum SubTone {
    case success, secondary

    func color(palette: Theme.Palette) -> Color {
        switch self {
        case .success:   return Brand.success
        case .secondary: return palette.textSecondary
        }
    }
}

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                heroCard
                metaCard
                if let l = claim.loadNumber, !l.isEmpty, l != "-" {
                    associationCard(loadNumber: l)
                }
                if !claim.description.isEmpty {
                    descriptionCard
                }
                actionsCard
                Color.clear.frame(height: 48)
            }
            .padding(Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage.ignoresSafeArea())
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
                if claim.amount > 0 {
                    Text(formatMoney(claim.amount))
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
                kvRow("Filed",   value: claim.filedDate.isEmpty ? "—" : claim.filedDate)
                kvRow("Carrier", value: (claim.carrier?.isEmpty == false && claim.carrier != "-")
                      ? claim.carrier!
                      : "—")
                kvRow("Shipper", value: (claim.shipper?.isEmpty == false && claim.shipper != "-")
                      ? claim.shipper!
                      : "—")
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
            Text(claim.description)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionsCard: some View {
        sectionCard(title: "ACTIONS") {
            VStack(spacing: 6) {
                actionRow(
                    icon: "doc.badge.arrow.up",
                    title: "Add evidence",
                    subtitle: "Photos, BOL, POD, repair invoices.",
                    key: "claims.add-evidence"
                )
                actionRow(
                    icon: "person.2.wave.2.fill",
                    title: "Open dispute",
                    subtitle: "Escalate to mediator if the carrier denies the claim.",
                    key: "claims.open-dispute"
                )
                actionRow(
                    icon: "arrow.up.right.square",
                    title: "View on web",
                    subtitle: "Full claim file lives at eusotrip.com/freight-claims",
                    key: "claims.open-web"
                )
            }
        }
    }

    private func actionRow(icon: String, title: String, subtitle: String, key: String) -> some View {
        Button {
            MeAction.fire(key, userInfo: ["claimId": claim.id, "claimNumber": claim.claimNumber])
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

    private func formatMoney(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 1_000_000 { return String(format: "$%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "$%.0fk", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n == 0          { return "—" }
        return "$\(n)"
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
