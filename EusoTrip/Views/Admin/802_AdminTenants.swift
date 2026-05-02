//
//  802_AdminTenants.swift
//  EusoTrip — Admin · Tenants directory (brick 802).
//
//  Second brick on the Admin role track (800s). The natural follow-on
//  to 800_AdminHome — when the operator taps the "View all →" CTA on
//  the new ACTIVE TENANTS section header, this is the deep tenant
//  directory that opens. Until 802 shipped, the home's `activeTenants`
//  KPI was a read-only number with no drill-down. Now the tap presents
//  this real surface, bringing Admin to two-screen depth (parity with
//  Terminal 700/701, Escort 600/601, Catalyst 500/501/502, Carrier
//  300/301/302/303/304, Broker 400/401/402).
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §1 (gradient-only
//  accent — no `.fill(Brand.blue)` / `.tint(Brand.blue)`), §2 (no
//  Toggles on this brick), §3 (`AnyShapeStyle` wrapping for ternary
//  shape-styles in fill / stroke), §4 (tokenized spacing / radius /
//  type — Space.s*, Radius.*, EType.*), §5 (palette-semantic only —
//  no hard-coded `Color.white` / `Color.black` / `Color.gray` outside
//  CTA inverse-text + shadow opacities), §10 (previews compile in
//  isolation — `.task` doesn't run in the canvas, so the store stays
//  in `.loading` and never hits the network).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, dynamic ready pages with 0 data,
//  plugged into backend"):
//
//    • Tenant list → `AdminTenantsStore` (LiveDataStores.swift) →
//      `admin.listTenants` (input `{ limit: number, status: string? }`).
//      If the parallel router has not shipped, the store resolves to
//      `.error` and the screen surfaces an honest retry banner. No
//      fixture data ever.
//    • Status-filter chip row drives a re-fetch with a tighter scope
//      ("All", "Active", "Trial", "Suspended", "Pending review",
//      "Churned"). Each chip mutates the store's `statusFilter` and
//      kicks a fresh `refresh()` round-trip — the chip set itself is
//      a doctrinal whitelist (the server's enum), not a runtime
//      projection of the loaded rows.
//    • Per-row tap → no destructive mutation this firing. The CTA is a
//      `View detail →` placeholder that cycles a row-local highlight
//      — the deep tenant editor (`803_AdminTenantDetail`) lands in a
//      future port. The rationale: admin platform-state mutations
//      (suspend / reinstate / churn) carry irreversibly broad blast
//      radius, so we don't surface the trigger until the matching
//      detail screen + confirmation flow lands. Doctrine §11
//      (no fake data) is preserved either way.
//    • Empty / blank server fields surface as em-dash sentinels
//      ("—") — every nullable column on a fresh tenant row (no plan,
//      no primary user, no monthly volume, no MRR) renders as a
//      neutral em-dash, never a fabricated value.
//
//  Wired into `ContentView.ScreenRegistry` as id="802".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Status filter chip set
//
// Whitelist mirrors the server's `companies.status` enum. The "All"
// pseudo-value maps to `nil` on `AdminTenantsStore.statusFilter` (no
// filter — server returns every tenant). Order matches the operator's
// most-frequent inspection cadence (active first, then trial, then the
// negative-state buckets).

private enum TenantStatusFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case trial
    case pendingReview
    case suspended
    case churned

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:           return "ALL"
        case .active:        return "ACTIVE"
        case .trial:         return "TRIAL"
        case .pendingReview: return "REVIEW"
        case .suspended:     return "SUSPENDED"
        case .churned:       return "CHURNED"
        }
    }

    /// Server-side enum value passed to `admin.listTenants`. nil for
    /// the "All" pseudo-filter — the server returns every tenant.
    var serverValue: String? {
        switch self {
        case .all:           return nil
        case .active:        return "active"
        case .trial:         return "trial"
        case .pendingReview: return "pending_review"
        case .suspended:     return "suspended"
        case .churned:       return "churned"
        }
    }
}

// MARK: - Screen body

struct AdminTenants: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var tenants = AdminTenantsStore()

    /// Selected status filter chip — drives a refresh on change.
    @State private var filter: TenantStatusFilter = .all

    /// Per-row local highlight (row id) — flashed momentarily on tap
    /// before the drill-in sheet presents. Kept for backward-compat
    /// with the pre-803 placeholder pattern; now trails behind the
    /// real drill-in.
    @State private var highlightedRowId: String? = nil

    /// Drill-in sheet target. Set on row tap, presents the
    /// `803_AdminTenantDetail` deep envelope for that tenant id.
    /// Wrapped in `IdentifiedTenantId` so SwiftUI's `.sheet(item:)`
    /// re-presents on identity change.
    @State private var detailTenantId: IdentifiedTenantId? = nil

    /// Light-preview hint passed to 803 so its hero card has paint-1
    /// content (name + status pill) while the deep fetch is in flight.
    /// Read from the row that triggered the drill-in.
    @State private var detailPreviewHint: AdminAPI.Tenant? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                filterRow
                contentBody
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await tenants.refresh() }
        .refreshable { await tenants.refresh() }
        .sheet(item: $detailTenantId) { ident in
            // 161st firing · brick 803: real drill-in. The 803 view
            // owns its own `AdminTenantDetailStore`, so this sheet
            // hands off the tenant id (+ optional preview hint) and
            // gets out of the way.
            AdminTenantDetailScreen(
                theme: palette,
                tenantId: ident.id,
                previewHint: detailPreviewHint
            )
            .environmentObject(session)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 18, weight: .heavy))
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
                        Text("ADMIN · TENANTS")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Text(headline)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text(subhead)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
    }

    /// Identity-aware headline. Falls back to a neutral title so the
    /// header never reads as a placeholder.
    private var headline: String {
        if let name = session.user?.firstName, !name.isEmpty {
            return "Tenants, \(name)"
        }
        return "Tenants"
    }

    private var subhead: String {
        switch tenants.state {
        case .loading:
            return "Loading tenants…"
        case .loaded(let rows):
            let count = rows.count
            let scope = filter == .all ? "" : " · \(filter.label.lowercased())"
            return "\(count) tenant\(count == 1 ? "" : "s")\(scope)"
        case .empty:
            return filter == .all
                ? "0 tenants on the platform"
                : "0 tenants match this filter"
        case .error:
            return "Tenants couldn't load"
        }
    }

    // MARK: - Filter chip row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TenantStatusFilter.allCases) { f in
                    filterChip(f)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(_ f: TenantStatusFilter) -> some View {
        let isActive = (f == filter)
        return Button {
            guard f != filter else { return }
            filter = f
            tenants.statusFilter = f.serverValue
            highlightedRowId = nil
            Task { await tenants.refresh() }
        } label: {
            Text(f.label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(isActive ? Color.white : palette.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(isActive
                            ? AnyShapeStyle(LinearGradient.diagonal)
                            : AnyShapeStyle(palette.bgCard))
                .overlay(
                    Capsule()
                        .strokeBorder(isActive
                                      ? AnyShapeStyle(Color.clear)
                                      : AnyShapeStyle(palette.borderFaint),
                                      lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content body (state machine)

    @ViewBuilder
    private var contentBody: some View {
        switch tenants.state {
        case .loading:
            listSkeleton
        case .loaded(let rows):
            VStack(spacing: Space.s2) {
                ForEach(rows) { row in
                    tenantRow(row)
                }
            }
        case .empty:
            EusoEmptyState(
                systemImage: "building.2",
                title: filter == .all ? "No tenants yet" : "No tenants match this filter",
                subtitle: filter == .all
                    ? "Once a shipper, carrier, brokerage, or catalyst collective signs up on the platform, they'll appear here in real time."
                    : "Try a different status filter, or pull to refresh."
            )
        case .error(let err):
            errorBanner(message: readableError(err))
        }
    }

    // MARK: - Tenant row

    private func tenantRow(_ row: AdminAPI.Tenant) -> some View {
        let isHighlighted = (highlightedRowId == row.id)
        return VStack(alignment: .leading, spacing: Space.s2) {
            // Top: tenant name + status chip
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name.isEmpty ? "—" : row.name)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if let plan = row.plan, !plan.isEmpty {
                        Text(plan.uppercased())
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    } else {
                        Text("—")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
                statusChip(row.status)
            }

            // Middle: primary user + signup date
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text(row.primaryUserName ?? "—")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Text("·").foregroundStyle(palette.textTertiary)
                Image(systemName: "calendar")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text(row.signedUpAt.isEmpty ? "—" : row.signedUpAt)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }

            // Bottom: KPI strip (active users · monthly volume · mrr) + CTA
            HStack(alignment: .center, spacing: Space.s3) {
                kpiCell(label: "USERS · 30D", value: "\(row.activeUserCount)")
                kpiCell(label: "VOL · MO",   value: usd(row.monthlyVolumeUsd))
                kpiCell(label: "MRR",        value: usd(row.mrrUsd))
                Spacer()
                Button {
                    // 161st firing · brick 803: real drill-in. The
                    // momentary row highlight stays for tactile feedback;
                    // the sheet immediately follows with the deep
                    // envelope. No destructive mutation here — admin
                    // platform-state edits live inside the 803 surface
                    // (suspend / reinstate / churn — guarded confirm).
                    highlightedRowId = row.id
                    detailPreviewHint = row
                    detailTenantId = IdentifiedTenantId(id: row.id)
                } label: {
                    HStack(spacing: 4) {
                        Text("View detail")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(LinearGradient.diagonal)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(isHighlighted
                              ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.6))
                              : AnyShapeStyle(palette.borderFaint),
                              lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Status chip

    private func statusChip(_ raw: String) -> some View {
        let label = raw.replacingOccurrences(of: "_", with: " ").uppercased()
        let normalized = raw.lowercased()
        let style: AnyShapeStyle
        let fg: Color
        switch normalized {
        case "active":
            style = AnyShapeStyle(LinearGradient.diagonal)
            fg = .white
        case "trial":
            style = AnyShapeStyle(palette.tintNeutral)
            fg = palette.textSecondary
        case "pending_review":
            style = AnyShapeStyle(Brand.warning.opacity(0.18))
            fg = Brand.warning
        case "suspended":
            style = AnyShapeStyle(Brand.danger.opacity(0.18))
            fg = Brand.danger
        case "churned":
            style = AnyShapeStyle(palette.tintNeutral)
            fg = palette.textTertiary
        default:
            style = AnyShapeStyle(palette.tintNeutral)
            fg = palette.textSecondary
        }
        return Text(label.isEmpty ? "—" : label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(style)
            .clipShape(Capsule())
    }

    // MARK: - KPI cell

    private func kpiCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
        }
    }

    // MARK: - Loading + error states

    private var listSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 108)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Button(action: { Task { await tenants.refresh() } }) {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Helpers

    /// Format an optional USD amount to a compact "$1.2k", "$340k",
    /// "$2.4M" string. Returns "—" when nil so the empty case never
    /// renders as "$0" (which would be a fabricated zero).
    private func usd(_ v: Double?) -> String {
        guard let v = v, v > 0 else { return "—" }
        if v >= 1_000_000 {
            return String(format: "$%.1fM", v / 1_000_000)
        } else if v >= 1_000 {
            return "$\(Int((v / 1_000).rounded()))k"
        } else {
            return "$\(Int(v.rounded()))"
        }
    }

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct AdminTenantsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            AdminTenants()
        } nav: {
            BottomNav(
                leading: adminNavLeading_802(),
                trailing: adminNavTrailing_802(),
                orbState: .idle
            )
        }
    }
}

private func adminNavLeading_802() -> [NavSlot] {
    [NavSlot(label: "Home",    systemImage: "house",         isCurrent: false),
     NavSlot(label: "Tickets", systemImage: "ticket.fill",   isCurrent: false)]
}

private func adminNavTrailing_802() -> [NavSlot] {
    [NavSlot(label: "Tenants", systemImage: "building.2.fill", isCurrent: true),
     NavSlot(label: "Me",      systemImage: "person",          isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("802 · Admin · Tenants · Night") {
    AdminTenantsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("802 · Admin · Tenants · Afternoon") {
    AdminTenantsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
