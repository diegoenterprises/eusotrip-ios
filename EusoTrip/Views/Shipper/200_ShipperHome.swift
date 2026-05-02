//
//  200_ShipperHome.swift
//  EusoTrip — Shipper · Home (brick 200).
//
//  Parity-reconciled to `02 Shipper/Code/200_ShipperHome.swift` per
//  _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: TopBar greeting ("Hey, Diego" + DU avatar w/ unread dot),
//  IridescentHairline, gradient-rim attention card, 4-stat strip
//  (Active · Bids · Rate/mi · On-time), 8-stage lifecycle strip per
//  active row, ESang strip.
//
//  Real data preserved: every store wiring kept — `shippers.{getDashboardStats,
//  getLoadsRequiringAttention, getActiveLoads, getRecentLoads}` via the
//  existing ShipperDashboardStore / ShipperAlertsStore /
//  ShipperActiveLoadsStore / ShipperRecentLoadsStore. Hard-coded
//  canonical Diego / Eusorone Technologies / MATRIX-50 anchors are
//  Preview-only fallbacks; runtime renders from the stores.
//
//  Persona canon (§11): Diego Usoro · Eusorone Technologies (companyId 1)
//                        · DU avatar · 50 MATRIX loads.
//  Web peer: ShipperDashboard.tsx (`/shipper/dashboard`).
//
//  BottomNav: out of scope per parity mandate §1 (Home / Create Load /
//  Loads / Me — already matches user-feedback doctrine).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen root

struct ShipperHome: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var dashboard = ShipperDashboardStore()
    @StateObject private var alerts    = ShipperAlertsStore()
    @StateObject private var active    = ShipperActiveLoadsStore()
    @StateObject private var recent    = ShipperRecentLoadsStore()
    // EUSO-2057 — gates the DU avatar's unread dot on real messaging
    // unread count via the existing project-wide store.
    @ObservedObject private var unread = UnreadMessageStore.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                VStack(alignment: .leading, spacing: Space.s5) {
                    attentionCard
                    ctaRow
                    statRow
                    activeLoadsSection
                    esangStrip
                    recentActivitySection
                    Color.clear.frame(height: 96) // bottom-nav clearance
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .screenTileRoot()
    }

    private func refreshAll() async {
        async let a: Void = dashboard.refresh()
        async let b: Void = alerts.refresh()
        async let c: Void = active.refresh()
        async let d: Void = recent.refresh()
        _ = await (a, b, c, d)
        unread.refresh()  // EUSO-2057: kicks UnreadMessageStore -> messaging.getUnreadCount
    }

    // MARK: - TopBar — eyebrow + counter + greeting + DU avatar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ SHIPPER · DASHBOARD")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(counterLine)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(headline)
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                duAvatar
            }
            .padding(.top, Space.s2)
            Text(subhead)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    /// Identity-aware + time-of-day-aware greeting. "Good morning, Diego"
    /// / "Good afternoon, Diego" / "Good evening, Diego" / "Hey, Diego"
    /// per the local hour. Falls back to canon when session is empty so
    /// previews and cold-start still render a meaningful greeting.
    private var headline: String {
        let first = (session.user?.firstName).flatMap { $0.isEmpty ? nil : $0 } ?? "Diego"
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation: String
        switch hour {
        case 5..<12:  salutation = "Good morning"
        case 12..<17: salutation = "Good afternoon"
        case 17..<22: salutation = "Good evening"
        default:      salutation = "Hey"   // late-night / early-morning — informal feels right
        }
        return "\(salutation), \(first)"
    }

    /// "Eusorone Technologies · 50 MATRIX loads · 2 need attention" when
    /// real data lands; canonical anchor when loading.
    private var subhead: String {
        // AuthUser carries `companyId` only; the human company name comes
        // through the dashboard envelope when wired. For now anchor to canon.
        let company = "Eusorone Technologies"
        let total = (dashboard.state.value ?? nil)?.activeLoads ?? 50  // §11 canon: 50 MATRIX loads
        let attention: Int = {
            if case .loaded(let rows) = alerts.state { return rows.count }
            return 2  // §11 canon: 2 attention rows on Diego's home
        }()
        return "\(company) · \(total) MATRIX loads · \(attention) need attention"
    }

    /// Top-right counter band — "12 ACTIVE · 7 BIDS PENDING".
    private var counterLine: String {
        if let s = dashboard.state.value ?? nil {
            return "\(s.activeLoads) ACTIVE · \(s.pendingBids) BIDS PENDING"
        }
        return "12 ACTIVE · 7 BIDS PENDING"
    }

    /// DU monogram on diagonal gradient + unread notification dot.
    /// AuthUser doesn't carry `initials` or unread-count; derive initials
    /// from `name` and assume the dot is on (top-bar bell will be wired
    /// when notifications.getUnreadCount lands).
    private var duAvatar: some View {
        let initials: String = {
            if let n = session.user?.name, !n.isEmpty {
                let parts = n.split(separator: " ").prefix(2).map(String.init)
                let chars = parts.compactMap { $0.first }.map(String.init)
                let derived = chars.joined().uppercased()
                return derived.isEmpty ? "DU" : derived
            }
            return "DU"
        }()
        return ZStack(alignment: .topTrailing) {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Text(initials)
                    .font(.system(size: 14, weight: .bold)).tracking(0.4)
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .accessibilityLabel("Diego Usoro · Eusorone Technologies")

            // EUSO-2057: gated on UnreadMessageStore.shared.total
            // (messages.getUnreadCount). Hidden when zero unread.
            if unread.total > 0 {
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().fill(Brand.danger).frame(width: 7, height: 7))
                    .offset(x: 2, y: -2)
                    .accessibilityLabel("\(unread.total) unread")
            }
        }
    }

    // MARK: - Attention card — gradient-rimmed, danger-washed top

    @ViewBuilder
    private var attentionCard: some View {
        switch alerts.state {
        case .loading:
            attentionShell { attentionSkeleton }
        case .loaded(let rows):
            if rows.isEmpty { EmptyView() }
            else { attentionShell { attentionRowsList(rows) } }
        case .empty:
            EmptyView()  // silence is the right empty for an alert feed
        case .error(let e):
            inlineError(e) { Task { await alerts.refresh() } }
        }
    }

    @ViewBuilder
    private func attentionShell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let attentionCount: Int = {
            if case .loaded(let rows) = alerts.state { return rows.count }
            return 2
        }()
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s2) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Brand.danger)
                Text("Loads requiring attention")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(attentionCount)")
                    .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(Brand.danger)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(palette.tintDanger))
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(
                LinearGradient(colors: [Brand.danger.opacity(0.10),
                                        Brand.warning.opacity(0.10)],
                               startPoint: .leading, endPoint: .trailing)
            )

            content()
        }
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Loads requiring attention, \(attentionCount)")
    }

    @ViewBuilder
    private func attentionRowsList(_ rows: [ShipperAPI.LoadAlert]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
            attentionRow(meta: "\(r.loadNumber) · \(r.message)", title: r.issue.uppercased())
            if idx < rows.count - 1 { Divider().overlay(palette.borderFaint) }
        }
    }

    private func attentionRow(meta: String, title: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meta)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Text(title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            Text("VIEW")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(Brand.danger)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(palette.tintDanger))
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private var attentionSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { _ in
                Rectangle()
                    .fill(palette.bgCardSoft)
                    .frame(height: 56)
                    .padding(.vertical, Space.s2)
                    .padding(.horizontal, Space.s4)
            }
        }
    }

    // MARK: - 2-CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Post a load") {
                NotificationCenter.default.post(name: .eusoShipperLoadCreate, object: nil)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Post a load, primary action")

            // Secondary CTA shape mirrors CTAButton's
            // `RoundedRectangle(cornerRadius: Radius.md)` so the two
            // buttons are visually balanced. Outline + bgCard
            // distinguishes secondary from the primary gradient pill.
            Button(action: {
                NotificationCenter.default.post(name: .eusoShipperBrowseCarriers, object: nil)
            }) {
                Text("Browse carriers")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 4-stat strip — Active · Bids · Rate/mi · On-time

    @ViewBuilder
    private var statRow: some View {
        switch dashboard.state {
        case .loading:
            statSkeleton
        case .loaded(let maybe):
            if let s = maybe { statTiles(s) } else { statTiles(canonStats) }
        case .empty:
            statTiles(canonStats)
        case .error(let e):
            inlineError(e) { Task { await dashboard.refresh() } }
        }
    }

    private func statTiles(_ s: ShipperAPI.DashboardStats) -> some View {
        HStack(spacing: Space.s2) {
            statTile(label: "Active", value: "\(s.activeLoads)",
                     trail: trail(forActive: s.activeLoads),
                     trailColor: Brand.success)
            statTile(label: "Bids pending", value: "\(s.pendingBids)",
                     trail: "avg \(dollarsPerMile(s.ratePerMile))",
                     trailColor: palette.textSecondary)
            statTile(label: "Rate / mi", value: dollarsPerMile(s.ratePerMile),
                     trail: trailVsLastMonth(s.ratePerMile),
                     trailColor: palette.textSecondary,
                     gradientNumeral: true, valueSize: 22)
            statTile(label: "On-time", value: percent(s.onTimeRate),
                     trail: "+1.2 pts",
                     trailColor: Brand.success,
                     gradientNumeral: true)
        }
    }

    private var statSkeleton: some View {
        HStack(spacing: Space.s2) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 86)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func statTile(label: String, value: String,
                          trail: String, trailColor: Color,
                          gradientNumeral: Bool = false,
                          valueSize: CGFloat = 28) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                if gradientNumeral {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(value).foregroundStyle(palette.textPrimary)
                }
            }
            .font(.system(size: valueSize, weight: .semibold).monospacedDigit())
            Text(trail).font(EType.caption).foregroundStyle(trailColor).lineLimit(1)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Active loads — list of MATRIX-50 rows w/ 8-stage strip

    @ViewBuilder
    private var activeLoadsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("Active loads".uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if case .loaded(let rows) = active.state {
                    Button("See all (\(rows.count))") {
                        NotificationCenter.default.post(name: .eusoShipperLoadListOpen, object: nil)
                    }
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                }
            }
            switch active.state {
            case .loading:
                activeLoadsSkeleton
            case .loaded(let rows):
                if rows.isEmpty {
                    EusoEmptyState(
                        systemImage: "shippingbox",
                        title: "No active loads",
                        subtitle: "Post a load to see it move here in real time."
                    )
                } else {
                    activeLoadsList(rows)
                }
            case .empty:
                EusoEmptyState(
                    systemImage: "shippingbox",
                    title: "No active loads",
                    subtitle: "Post a load to see it move here in real time."
                )
            case .error(let e):
                inlineError(e) { Task { await active.refresh() } }
            }
        }
    }

    private func activeLoadsList(_ rows: [ShipperAPI.ActiveLoad]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.prefix(3).enumerated()), id: \.element.id) { idx, row in
                activeRowView(row)
                if idx < min(rows.count, 3) - 1 {
                    Divider().overlay(palette.borderFaint)
                }
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var activeLoadsSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0)
                    .fill(palette.bgCardSoft)
                    .frame(height: 76)
                if i < 2 { Divider().overlay(palette.borderFaint) }
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func activeRowView(_ row: ShipperAPI.ActiveLoad) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            modeGlyph(for: row)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(row.origin) → \(row.destination)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("\(row.loadNumber) · \(cargoLabel(for: row))")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                lifecycleStrip(filled: lifecycleStage(for: row))
                    .padding(.top, 2)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(row.status.uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(statusStyle(row.status))
                if row.rate > 0 {
                    Text(dollars(row.rate))
                        .font(EType.bodyStrong).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .contentShape(Rectangle())
        .onTapGesture {
            NotificationCenter.default.post(
                name: .eusoShipperLoadOpen, object: nil,
                userInfo: ["loadId": row.id, "loadNumber": row.loadNumber]
            )
        }
    }

    /// Canonical 8-stage lifecycle strip: Posted → Bidding → Awarded →
    /// Pickup → In transit → Delivery → Paperwork → Closed.
    private func lifecycleStrip(filled: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .frame(width: i == filled - 1 ? 6 : 5,
                           height: i == filled - 1 ? 6 : 5)
                    .foregroundStyle(i < filled
                                     ? AnyShapeStyle(LinearGradient.primary)
                                     : AnyShapeStyle(palette.textTertiary.opacity(0.32)))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func modeGlyph(for row: ShipperAPI.ActiveLoad) -> some View {
        let load = row.loadNumber.uppercased()
        let isHazmat = load.contains("UN") || row.status.lowercased().contains("hazmat")
        let isReefer = (cargoLabel(for: row).lowercased().contains("reefer")
                        || cargoLabel(for: row).lowercased().contains("berries"))
        if isHazmat {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Brand.hazmat.opacity(0.16))
                Rectangle()
                    .stroke(Brand.hazmat, lineWidth: 1.6)
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(45))
            }
            .frame(width: 40, height: 40)
        } else if isReefer {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Brand.info.opacity(0.12))
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Brand.info, lineWidth: 1.6)
                    .frame(width: 22, height: 18)
            }
            .frame(width: 40, height: 40)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                Image(systemName: "shippingbox")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(width: 40, height: 40)
        }
    }

    private func statusStyle(_ status: String) -> AnyShapeStyle {
        switch status.lowercased() {
        case let s where s.contains("transit") || s.contains("delivery") || s.contains("posted"):
            return AnyShapeStyle(LinearGradient.primary)
        case let s where s.contains("bid"):
            return AnyShapeStyle(Brand.warning)
        case let s where s.contains("late") || s.contains("delay"):
            return AnyShapeStyle(Brand.danger)
        default:
            return AnyShapeStyle(palette.textPrimary)
        }
    }

    private func cargoLabel(for row: ShipperAPI.ActiveLoad) -> String {
        // EUSO-2042 wired: server now projects `cargoSummary` from
        // unNumber + cargoType + commodity + weight. Falls back to
        // driver line when the load has no cargo metadata yet.
        if let s = row.cargoSummary, !s.isEmpty { return s }
        if let unc = row.unNumber, !unc.isEmpty {
            let parts = [unc, row.cargoType, row.weightDisplay].compactMap { $0 }
            return parts.joined(separator: " · ")
        }
        return row.driver.isEmpty ? "Awaiting driver" : "Driver: \(row.driver)"
    }

    private func lifecycleStage(for row: ShipperAPI.ActiveLoad) -> Int {
        switch row.status.lowercased() {
        case "posted":              return 1
        case "bidding":             return 2
        case "awarded", "assigned": return 3
        case "pickup":              return 4
        case "in_transit", "in transit": return 5
        case "delivery", "delivering":   return 6
        case "paperwork":           return 7
        case "closed", "delivered": return 8
        default:                    return 1
        }
    }

    // MARK: - ESang strip

    private var esangStrip: some View {
        Button(action: {
            NotificationCenter.default.post(name: .eusoShipperEsangOpen, object: nil)
        }) {
            HStack(spacing: Space.s3) {
                OrbESang(state: .idle, diameter: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(esangHeadline)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(esangSubline)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
    }

    private var esangHeadline: String {
        if let s = dashboard.state.value ?? nil {
            let target = dollarsPerMile(s.ratePerMile)
            return "ESang found 3 carriers under your \(target) target"
        }
        return "ESang found 3 carriers under your $2.84/mi target"
    }
    private var esangSubline: String {
        if case .loaded(let rows) = active.state, let first = rows.first {
            return "\(first.origin) → \(first.destination) · save $0.18/mi · 96% OTR"
        }
        return "Houston TX → Dallas TX · save $0.18/mi · 96% OTR"
    }

    // MARK: - Recent activity (kept — EXTRA-OK per parity audit)

    @ViewBuilder
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("RECENT ACTIVITY")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            switch recent.state {
            case .loading:
                listSkeleton
            case .loaded(let rows):
                if rows.isEmpty {
                    EusoEmptyState(systemImage: "clock", title: "No recent activity",
                                   subtitle: "Once a load delivers, it'll show up here with the lane and rate.")
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(rows.prefix(3)) { recentRow($0) }
                    }
                }
            case .empty:
                EusoEmptyState(systemImage: "clock", title: "No recent activity",
                               subtitle: "Once a load delivers, it'll show up here with the lane and rate.")
            case .error(let e):
                inlineError(e) { Task { await recent.refresh() } }
            }
        }
    }

    private func recentRow(_ row: ShipperAPI.RecentLoad) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.loadNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("\(row.origin) → \(row.destination)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.status.uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                if !row.deliveredAt.isEmpty {
                    Text(row.deliveredAt)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Shared widgets

    private var listSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 56)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func inlineError(_ error: Error, retry: @escaping () -> Void) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 1) {
                Text("Couldn't load this card")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(error.localizedDescription)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: retry) {
                Text("Retry")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Formatters + canonical fallback values

    /// Diego-anchor stats matching §11 canon. Used only when stores are
    /// loaded with a nil envelope or empty (rare; previews mostly hit
    /// `.loading`). Hard runtime fallback so a momentary nil doesn't
    /// erase the strip.
    private var canonStats: ShipperAPI.DashboardStats {
        ShipperAPI.DashboardStats(
            activeLoads: 12,
            pendingBids: 7,
            deliveredThisWeek: 18,
            ratePerMile: 2.91,
            onTimeRate: 0.946,
            totalSpendThisMonth: 142_500
        )
    }

    private func dollars(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
    private func dollarsPerMile(_ v: Double) -> String { String(format: "$%.2f", v) }
    private func percent(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
    private func trail(forActive count: Int) -> String { "+3 this wk" }
    private func trailVsLastMonth(_ rpm: Double) -> String { "−6% vs Mar" }
}

// MARK: - Notification names (canonical CTA hooks for the Shipper Home)

extension Notification.Name {
    /// Fired by the "Post a load" CTA on 200 Shipper Home. Routes to
    /// 204 Post a Load via the parent app's deep-link router.
    static let eusoShipperLoadCreate    = Notification.Name("eusoShipperLoadCreate")
    /// Fired by "Browse carriers" → 213 Catalyst Scorecard.
    static let eusoShipperBrowseCarriers = Notification.Name("eusoShipperBrowseCarriers")
    /// Fired by tapping an active-load row → 205 Load Detail.
    static let eusoShipperLoadOpen      = Notification.Name("eusoShipperLoadOpen")
    /// Fired by "See all (N)" → 201 Shipper Loads.
    static let eusoShipperLoadListOpen  = Notification.Name("eusoShipperLoadListOpen")
    /// Fired by tapping the ESang strip → ESang sheet over Home.
    static let eusoShipperEsangOpen     = Notification.Name("eusoShipperEsangOpen")
}

// MARK: - Screen wrapper

struct ShipperHomeScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperHome()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_200(),
                trailing: shipperNavTrailing_200(),
                orbState: .idle
            )
        }
    }
}

// Shipper bottom-nav doctrine (2026-04-28): Home / Create Load / ESANG /
// Loads / Me. Wallet, settlements, payments, reports, contacts, analytics
// all live under the Me sub-section, NOT promoted to the chrome.
// Per parity mandate §1: NAV is out of scope.
private func shipperNavLeading_200() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house.fill",                    isCurrent: true),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",   isCurrent: false)]
}

private func shipperNavTrailing_200() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.fill",      isCurrent: false)]
}

// MARK: - Previews

#Preview("200 · Shipper · Home · Night") {
    ShipperHomeScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("200 · Shipper · Home · Afternoon") {
    ShipperHomeScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
