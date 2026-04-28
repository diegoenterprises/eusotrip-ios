//
//  219_ShipperFreightClaims.swift
//  EusoTrip 2027 UI — brick 219 (shipper · freight claims)
//
//  Damage / loss / shortage / delay / contamination claims dashboard
//  for the shipper-as-claimant. Mirrors web `/freight-claims`
//  (`FreightClaims.tsx`) backed by the shipper-scope subset of
//  `freightClaimsRouter`.
//
//  Cohort B day-1 — fully dynamic. No fixtures.
//
//    • Dashboard hero (open/pending/resolved/denied counts +
//      total value + avg resolution days + aging breakdown +
//      recent claims) → `freightClaims.getClaimsDashboard`
//    • Claims list (status/type/search filters)
//      → `freightClaims.getClaims(...)`
//
//  Filing a new claim is intentionally NOT wired on this brick — the
//  multi-field form (type · severity · description · evidence
//  upload · carrier attribution · damages valuation) is heavy
//  enough to deserve its own brick. iOS surfaces a "File on web"
//  disclosure on the empty state so a shipper isn't blocked.
//
//  Powered by ESANG AI™.
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

    /// Maps to the server's status enum. Open = investigating.
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

// MARK: - Store

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
    @Published var filter: ClaimStatusFilter = .all {
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

// MARK: - Severity helpers

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
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
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

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · FREIGHT CLAIMS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Damage & loss recovery")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("Open · pending · resolved · denied — every claim against a delivered load, with carrier attribution and aging.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
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
        case .empty:
            emptyHero
        case .error(let msg):
            errorBanner(msg)
        case .loaded(let dashboard, let claims):
            dashboardHero(dashboard)
            agingCard(dashboard.aging)
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
                    ForEach(claims) { row in
                        claimRow(row)
                    }
                }
            }
        }
    }

    // MARK: Dashboard hero

    private func dashboardHero(_ d: ShipperFreightClaimsAPI.Dashboard) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("CLAIMS PIPELINE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if d.totalValue > 0 {
                    Text(formatMoney(d.totalValue))
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(LinearGradient.diagonal)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(LinearGradient.diagonal.opacity(0.18)))
                }
            }
            HStack(spacing: Space.s2) {
                heroTile(value: "\(d.open)",     label: "OPEN",     tint: Brand.warning)
                heroTile(value: "\(d.pending)",  label: "PENDING",  tint: Brand.info)
                heroTile(value: "\(d.resolved)", label: "RESOLVED", tint: Brand.success)
                heroTile(value: "\(d.denied)",   label: "DENIED",   tint: Brand.danger)
            }
            if d.avgResolutionDays > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textSecondary)
                    Text("Avg resolution \(Int(d.avgResolutionDays.rounded())) days")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
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

    private func heroTile(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Aging breakdown card

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
                // Stacked bar
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

    // MARK: Search + filter

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

    // MARK: Claim row

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

    // MARK: States

    private var emptyHero: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(LinearGradient.diagonal)
            Text("No claims filed")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text("Cargo damaged, short, or never made it? File on web — multi-step intake (type / severity / evidence / valuation) lives at eusotrip.com/freight-claims.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s4)
                .fixedSize(horizontal: false, vertical: true)
            Text("eusotrip.com/freight-claims")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s5)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

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

// MARK: - Detail sheet

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

#Preview("219 · Freight Claims · Night") {
    ShipperFreightClaims()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("219 · Freight Claims · Afternoon") {
    ShipperFreightClaims()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
