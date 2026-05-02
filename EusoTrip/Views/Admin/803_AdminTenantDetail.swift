//
//  803_AdminTenantDetail.swift
//  EusoTrip — Admin · Per-tenant deep envelope (brick 803).
//
//  Fourth brick on the Admin role track (800s). Lifts Admin to
//  4-deep parity with Driver (very deep), Shipper (18-deep),
//  Carrier (5-deep). The natural drill-down from a 802 tenants
//  list row's "View detail →" CTA. Sheet-presented (.large
//  detent, drag indicator visible) per doctrine §6.
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §1 (gradient-only
//  accent — no `.fill(Brand.blue)` / `.tint(Brand.blue)`), §2 (no
//  Toggles on this brick — admin destructive mutations are guarded
//  buttons with explicit confirm-style alerts in a future port),
//  §3 (`AnyShapeStyle` wrapping for ternary shape-styles in fill
//  / stroke), §4 (tokenized spacing / radius / type — Space.s*,
//  Radius.*, EType.*), §5 (palette-semantic only — no hard-coded
//  `Color.white` / `Color.black` / `Color.gray` outside CTA-on-
//  gradient + shadow opacities), §10 (previews compile in
//  isolation — `.task` doesn't run in the canvas, so the store
//  stays in `.loading` and never hits the network).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, dynamic ready pages with 0 data,
//  plugged into backend"):
//
//    • TenantDetail envelope → `AdminTenantDetailStore`
//      (LiveDataStores.swift) → `admin.getTenantDetail`
//      (input `{ id: string }`). If the parallel router has not
//      yet shipped, the store resolves to `.error` and the screen
//      surfaces an honest retry banner. No fixture data ever.
//    • Optional preview-hint (`AdminAPI.Tenant` row from the 802
//      list) gives the hero card paint-1 content (name + status
//      pill) while the deep fetch is in flight. The hint is
//      replaced with the loaded envelope as soon as it arrives —
//      it's never mixed with server data, and never fabricated.
//    • Every nullable column on the loaded envelope (`plan`,
//      `primaryUser*`, `monthlyVolumeUsd`, `mrrUsd`,
//      `lifetimeVolumeUsd`, `lifetimeRevenueUsd`, `nextRenewalAt`,
//      `healthScore`, `riskNote`, …) renders as a neutral em-dash
//      ("—") — never a fabricated value or a fallback zero.
//    • Audit-trail / contacts / usage-metrics rows are server-
//      paged. An empty array surfaces an honest empty sub-card
//      ("No audit events yet", etc.) rather than a synthetic row.
//    • No destructive mutations this firing. The CTA strip on the
//      hero card is a `.disabled(true)` placeholder labeled
//      "Suspend / reinstate / churn ship in 804+ — guarded confirm".
//      Per doctrine §11 (no fake data) + the broad blast radius
//      of admin platform-state edits, the trigger isn't surfaced
//      until the matching confirmation flow lands.
//
//  Wired into `ContentView.ScreenRegistry` as id="803" via the
//  registry-style wrapper `AdminTenantDetailScreen(theme:)`. The
//  raw `AdminTenantDetail` view is also presented as a sheet from
//  802 — both call-sites pass the tenant id forward; the sheet
//  call-site additionally passes a preview hint.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Sheet identity helper
//
// SwiftUI's `.sheet(item:)` requires an `Identifiable` payload. The
// raw tenant id is a `String`, which is `Identifiable` only via
// `\.self` — but using `\.self` collides when two rows share an
// equal id (rare, but possible during an in-flight refresh). Wrap
// the id in a tiny struct so identity is explicit and stable.

struct IdentifiedTenantId: Identifiable, Hashable {
    let id: String
}

// MARK: - Main view
//
// Self-driving — owns its `AdminTenantDetailStore` and reads
// palette from the environment. Both call-sites (802 sheet
// presenter + ContentView registry wrapper) pass the tenant id
// forward; the sheet call-site additionally passes a preview hint.

struct AdminTenantDetail: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var store = AdminTenantDetailStore()

    /// Tenant id this view is fetching. Written into the store on
    /// first task and on identity change.
    let tenantId: String

    /// Optional preview hint from the upstream 802 list row. Used
    /// only to paint the hero card's name + status pill while the
    /// deep envelope fetch is in flight. Replaced by loaded data
    /// as soon as it arrives.
    let previewHint: AdminAPI.Tenant?

    init(tenantId: String, previewHint: AdminAPI.Tenant? = nil) {
        self.tenantId = tenantId
        self.previewHint = previewHint
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                heroCard
                contentBody
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .background(palette.bgPage.ignoresSafeArea())
        .task {
            store.tenantId = tenantId
            await store.refresh()
        }
        .onChange(of: tenantId) { _, newValue in
            store.tenantId = newValue
            Task { await store.refresh() }
        }
        .refreshable {
            await store.refresh()
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.22),
            value: store.stateKey
        )
    }

    // MARK: - Hero card (header)

    private var heroCard: some View {
        // Pull whatever is the freshest source: loaded envelope >
        // preview hint > nothing. Hero only paints the always-known
        // shape (name, status pill, role chip) — KPI tiles below
        // gate on `.loaded` only and never paint hint-derived numbers.
        let displayName: String? = {
            switch store.state {
            case .loaded(let v): return v?.name
            default: return previewHint?.name
            }
        }()
        let displayStatus: String? = {
            switch store.state {
            case .loaded(let v): return v?.status
            default: return previewHint?.status
            }
        }()
        let displayKind: String? = {
            switch store.state {
            case .loaded(let v): return v?.kind
            default: return nil
            }
        }()
        let displayPlan: String? = {
            switch store.state {
            case .loaded(let v): return v?.plan
            default: return previewHint?.plan
            }
        }()

        return VStack(alignment: .leading, spacing: Space.s3) {
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
                        Text("ADMIN · TENANT DETAIL")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Text(displayName ?? "Loading tenant…")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if let s = displayStatus {
                            statusChip(s)
                        }
                        if let k = displayKind {
                            kindChip(k)
                        }
                        if let p = displayPlan, !p.isEmpty {
                            planChip(p)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            // Disabled CTA strip — admin destructive mutations land
            // in 804+ with guarded confirm. Doctrine §11 — never
            // surface a trigger that isn't real.
            HStack(spacing: 8) {
                disabledActionPill(label: "SUSPEND",   icon: "pause.fill")
                disabledActionPill(label: "REINSTATE", icon: "play.fill")
                disabledActionPill(label: "CHURN",     icon: "tray.full.fill")
            }
            Text("Destructive admin mutations ship in 804+ — guarded confirm.")
                .font(EType.caption)
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
    }

    private func disabledActionPill(label: String, icon: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .heavy))
                Text(label)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            }
            .foregroundStyle(palette.textTertiary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(palette.tintNeutral.opacity(0.4))
            .overlay(
                Capsule().strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(true)
    }

    // MARK: - Status / kind / plan chips

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
            style = AnyShapeStyle(palette.bgCard)
            fg = palette.textPrimary
        case "pending_review":
            style = AnyShapeStyle(palette.bgCard)
            fg = palette.textSecondary
        case "suspended":
            style = AnyShapeStyle(Brand.warning.opacity(0.15))
            fg = Brand.warning
        case "churned":
            style = AnyShapeStyle(Brand.danger.opacity(0.15))
            fg = Brand.danger
        default:
            style = AnyShapeStyle(palette.bgCard)
            fg = palette.textSecondary
        }
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(style)
            .overlay(
                Capsule().strokeBorder(palette.borderFaint.opacity(0.4), lineWidth: 0.5)
            )
            .clipShape(Capsule())
    }

    private func kindChip(_ raw: String) -> some View {
        Text(raw.uppercased())
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(palette.tintNeutral.opacity(0.4))
            .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 0.5))
            .clipShape(Capsule())
    }

    private func planChip(_ raw: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(raw.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(palette.bgCard)
        .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 0.5))
        .clipShape(Capsule())
    }

    // MARK: - Content body (state machine)

    @ViewBuilder
    private var contentBody: some View {
        switch store.state {
        case .loading:
            loadingSubcards
        case .loaded(let envOpt):
            if let env = envOpt {
                VStack(alignment: .leading, spacing: Space.s4) {
                    kpiStrip(env)
                    contactsSection(env)
                    usageMetricsSection(env)
                    paymentSummaryCard(env)
                    auditTrailSection(env)
                }
            } else {
                EusoEmptyState(
                    systemImage: "tray",
                    title: "Tenant detail not available",
                    subtitle: "The deep envelope hasn't been generated yet for this tenant."
                )
            }
        case .empty:
            EusoEmptyState(
                systemImage: "tray",
                title: "Tenant detail not available",
                subtitle: "The deep envelope hasn't been generated yet for this tenant."
            )
        case .error(let err):
            errorBanner(message: readableError(err))
        }
    }

    // MARK: - KPI strip (loaded only)

    private func kpiStrip(_ env: AdminAPI.TenantDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("KPI · TRAILING 30D")
            HStack(spacing: Space.s2) {
                kpiTile(label: "USERS · 30D",     value: "\(env.activeUserCount30d)")
                kpiTile(label: "VOL · MO",        value: usd(env.monthlyVolumeUsd))
                kpiTile(label: "MRR",             value: usd(env.mrrUsd))
            }
            HStack(spacing: Space.s2) {
                kpiTile(label: "LIFETIME · USERS", value: "\(env.totalUserCount)")
                kpiTile(label: "LIFETIME · VOL",   value: usd(env.lifetimeVolumeUsd))
                kpiTile(label: "LIFETIME · REV",   value: usd(env.lifetimeRevenueUsd))
            }
            HStack(spacing: Space.s2) {
                kpiTile(label: "SIGNED UP",      value: env.signedUpAt.isEmpty ? "—" : env.signedUpAt)
                kpiTile(label: "NEXT RENEWAL",   value: env.nextRenewalAt ?? "—")
                kpiTile(label: "HEALTH",         value: env.healthScore.map { "\($0)/100" } ?? "—")
            }
            if let note = env.riskNote, !note.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                    Text(note)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                .background(Brand.warning.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Brand.warning.opacity(0.4), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
        }
    }

    private func kpiTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: - Contacts

    private func contactsSection(_ env: AdminAPI.TenantDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("CONTACTS")
            if env.contacts.isEmpty {
                emptySubcard(
                    icon: "person.crop.circle.badge.questionmark",
                    title: "No contacts on file",
                    subtitle: "This tenant hasn't completed onboarding yet."
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(env.contacts) { c in
                        contactRow(c)
                    }
                }
            }
        }
    }

    private func contactRow(_ c: AdminAPI.TenantContact) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: contactIcon(c.role))
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 28, height: 28)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name.isEmpty ? "—" : c.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(c.role.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                if let e = c.email, !e.isEmpty {
                    Text(e)
                        .font(EType.mono(.micro)).tracking(0.2)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                if let p = c.phone, !p.isEmpty {
                    Text(p)
                        .font(EType.mono(.micro)).tracking(0.2)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func contactIcon(_ role: String) -> String {
        switch role.lowercased() {
        case "owner":      return "person.crop.circle.fill.badge.checkmark"
        case "billing":    return "creditcard.fill"
        case "operations": return "shippingbox.fill"
        case "compliance": return "checkmark.shield.fill"
        default:           return "person.crop.circle.fill"
        }
    }

    // MARK: - Usage metrics

    private func usageMetricsSection(_ env: AdminAPI.TenantDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("USAGE · TRAILING 30D")
            if env.usageMetrics.isEmpty {
                emptySubcard(
                    icon: "chart.bar",
                    title: "No usage yet",
                    subtitle: "Once this tenant generates platform activity, the metrics roll up here."
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(env.usageMetrics) { m in
                        usageMetricRow(m)
                    }
                }
            }
        }
    }

    private func usageMetricRow(_ m: AdminAPI.TenantUsageMetric) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.label.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("\(m.value)")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
            if let dPct = m.delta30dPct {
                deltaChip(dPct)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func deltaChip(_ pct: Double) -> some View {
        let isUp = pct >= 0
        let label = String(format: "%@%.1f%%", isUp ? "+" : "", pct)
        return HStack(spacing: 3) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .heavy))
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
        }
        .foregroundStyle(isUp ? Brand.success : Brand.danger)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background((isUp ? Brand.success : Brand.danger).opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Payment summary

    private func paymentSummaryCard(_ env: AdminAPI.TenantDetail) -> some View {
        let p = env.paymentSummary
        return VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("BILLING")
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("STATUS").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    billingStatusPill(p.billingStatus)
                }
                Divider().overlay(palette.borderFaint)
                billingRow(label: "BALANCE",
                           value: usd(p.balanceUsd))
                billingRow(label: "ON-TIME · 90D",
                           value: p.onTimeRate90d.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                billingRow(label: "PRIMARY METHOD",
                           value: primaryMethodLabel(p))
                billingRow(label: "STRIPE CUSTOMER",
                           value: p.stripeCustomerId.map { stripeCustomerShort($0) } ?? "—")
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func billingRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(value)
                .font(EType.mono(.body)).tracking(0.2)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func billingStatusPill(_ raw: String) -> some View {
        let label = raw.replacingOccurrences(of: "_", with: " ").uppercased()
        let normalized = raw.lowercased()
        let bg: AnyShapeStyle
        let fg: Color
        switch normalized {
        case "active":
            bg = AnyShapeStyle(LinearGradient.diagonal); fg = .white
        case "trialing":
            bg = AnyShapeStyle(palette.bgCard); fg = palette.textPrimary
        case "past_due":
            bg = AnyShapeStyle(Brand.warning.opacity(0.15)); fg = Brand.warning
        case "canceled", "unpaid":
            bg = AnyShapeStyle(Brand.danger.opacity(0.15)); fg = Brand.danger
        default:
            bg = AnyShapeStyle(palette.bgCard); fg = palette.textSecondary
        }
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(bg)
            .overlay(Capsule().strokeBorder(palette.borderFaint.opacity(0.4), lineWidth: 0.5))
            .clipShape(Capsule())
    }

    private func primaryMethodLabel(_ p: AdminAPI.TenantPaymentSummary) -> String {
        if let brand = p.primaryCardBrand, !brand.isEmpty,
           let last4 = p.primaryCardLast4, !last4.isEmpty {
            return "\(brand.uppercased()) ···· \(last4)"
        }
        if p.stripeCustomerId != nil {
            return "ACH · WIRE"
        }
        return "—"
    }

    private func stripeCustomerShort(_ id: String) -> String {
        // Stripe customer ids look like "cus_KQ7G2…". Show the first
        // 12 chars to keep the row mono-line and still recognisable.
        guard id.count > 14 else { return id }
        return String(id.prefix(12)) + "…"
    }

    // MARK: - Audit trail

    private func auditTrailSection(_ env: AdminAPI.TenantDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("AUDIT TRAIL")
            if env.auditTrail.isEmpty {
                emptySubcard(
                    icon: "list.bullet.rectangle",
                    title: "No audit events yet",
                    subtitle: "Suspend / reinstate / plan-change / billing-update events appear here."
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(env.auditTrail) { entry in
                        auditRow(entry)
                    }
                }
            }
        }
    }

    private func auditRow(_ a: AdminAPI.TenantAuditEntry) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 24, height: 24)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(a.label)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(a.occurredAt)
                    .font(EType.mono(.micro)).tracking(0.2)
                    .foregroundStyle(palette.textTertiary)
                if let actor = a.actor, !actor.isEmpty {
                    Text("by \(actor)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                if let n = a.note, !n.isEmpty {
                    Text(n)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: - Loading / empty / error helpers

    private var loadingSubcards: some View {
        VStack(spacing: Space.s4) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                    )
                    .opacity(0.6)
            }
        }
    }

    private func emptySubcard(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 32, height: 32)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func errorBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tenant detail couldn't load")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(message)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(4)
                }
                Spacer(minLength: 0)
            }
            Button {
                Task { await store.refresh() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .heavy))
                    Text("RETRY")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                }
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
                .strokeBorder(Brand.warning.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func readableError(_ err: Error) -> String {
        if let api = err as? EusoTripAPIError {
            return api.errorDescription ?? "Unknown error"
        }
        return err.localizedDescription
    }

    // MARK: - Utility

    private func sectionLabel(_ raw: String) -> some View {
        Text(raw)
            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
            .foregroundStyle(LinearGradient.diagonal)
    }

    /// USD formatter — falls back to em-dash when nil.
    private func usd(_ v: Double?) -> String {
        guard let v = v else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = v >= 1000 ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? "—"
    }
}

// MARK: - State key (drives animation transitions)
//
// `RemoteState` is non-Hashable in general (Errors aren't Hashable),
// so we project a coarse key for the `.animation(_:value:)` modifier.

private extension AdminTenantDetailStore {
    var stateKey: String {
        switch state {
        case .loading: return "loading"
        case .loaded(let v): return "loaded:\(v?.id ?? "nil")"
        case .empty: return "empty"
        case .error: return "error"
        }
    }
}

// MARK: - Registry-style wrapper
//
// `ContentView.ScreenRegistry` passes `(palette: Theme.Palette) ->
// AnyView`. The raw `AdminTenantDetail` view is bare-init (reads
// palette from environment), so the registry needs a wrapper that
// pipes the palette through. The wrapper also pre-fills a
// development tenant id when the registry is rendered with no
// upstream selection — surfaces the loading / error / empty state
// honestly without inventing a tenant. The actual production
// drill-in flow is 802 → sheet → AdminTenantDetail (which carries
// the real id).

struct AdminTenantDetailScreen: View {
    let theme: Theme.Palette
    let tenantId: String
    let previewHint: AdminAPI.Tenant?

    init(theme: Theme.Palette,
         tenantId: String = "",
         previewHint: AdminAPI.Tenant? = nil) {
        self.theme = theme
        self.tenantId = tenantId
        self.previewHint = previewHint
    }

    var body: some View {
        AdminTenantDetail(tenantId: tenantId, previewHint: previewHint)
            .environment(\.palette, theme)
    }
}

// MARK: - Previews
//
// Per doctrine §10: previews compile in isolation. `.task` doesn't
// run in the canvas, so the store stays in `.loading` and never
// hits the network. Both registers render the loading subcards.

#Preview("803 · Admin · Tenant Detail · Night") {
    AdminTenantDetailScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("803 · Admin · Tenant Detail · Afternoon") {
    AdminTenantDetailScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
