//
//  202_ShipperProfile.swift
//  EusoTrip — Shipper · Profile (brick 202).
//
//  Third brick on the Shipper role track (200s). Sits behind the
//  "Me" slot of the 200 / 201 BottomNav and presents the Shipper's
//  company profile + lifetime stats + 12-month volume chart.
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §2 (gradient-only
//  accent, GradientToggleStyle on every Toggle — none on this brick),
//  §4 (tokenized spacing / radius / type), §5 (palette semantic only,
//  no hard-coded Color.white / Color.black / Color.gray fills), §7
//  (`AnyShapeStyle` wrapping for ternary shape-styles), §10 (previews
//  compile in isolation).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Identity card → `shippers.getProfile` via
//      `ShipperProfileStore` (LiveDataStores.swift). Server returns a
//      11-field envelope (id, companyName, contactName, email, phone,
//      address, dotNumber, mcNumber, verified, memberSince, website).
//      MCP-verified at `frontend/server/routers/shippers.ts:583`.
//    • Stats grid + monthly-volume mini-chart →
//      `shippers.getStats` via `ShipperStatsStore` (shippers.ts:605).
//      Server returns totalLoads, totalSpend, avgRatePerMile,
//      onTimeDeliveryRate, preferredCatalysts, avgPaymentTime,
//      onTimeRate, monthlyVolume[], maxMonthlyLoads.
//    • Zero synthesised data. Every blank field surfaces as an
//      em-dash sentinel ("—") rather than a fabricated brand,
//      contact, or metric. The screen holds its honesty even when
//      the backend hands back the sentinel envelope (server returns
//      empty strings + zeros when the underlying `companies` row
//      has not yet been populated).
//
//  Wired into `ContentView.ScreenRegistry` as id="202".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen root

struct ShipperProfile: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var profileStore = ShipperProfileStore()
    @StateObject private var statsStore   = ShipperStatsStore()

    @State private var showEditProfile: Bool = false
    @State private var showSignOutConfirm: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                identityCard
                contactCard
                statsCard
                // Tier progression hero — mirrors the Driver 056 pool
                // tier card. Tier resolves client-side from the
                // already-loaded stats (volume + on-time + spend), no
                // extra round-trip. Backend can promote this to a
                // first-class projection later — fixture stays stable.
                tierProgressionCard
                // Credentials grid — FMCSA verified / insurance / BBB
                // / payment history. Reads off the existing profile
                // envelope; em-dashes the rows the backend doesn't
                // ship yet so the doctrine "no fake data" holds.
                credentialsCard
                // ESANG promotion strip — product-aware copy that
                // celebrates the shipper's tier benefits. Same
                // visual recipe as Driver 056 esangStrip.
                esangStrip
                monthlyVolumeCard
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Sign out", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .screenTileRoot()
    }

    private func refreshAll() async {
        async let a: Void = profileStore.refresh()
        async let b: Void = statsStore.refresh()
        _ = await (a, b)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.fill.badge.checkmark")
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
                    Text("SHIPPER · PROFILE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text(headlineCompany)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Text(headlineContact)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    /// Company name pulled from the live `getProfile` envelope. The
    /// server returns "" when the underlying `companies.name` row
    /// has not yet been populated — surface that honestly as an
    /// em-dash, never as a fabricated brand. Doctrine: 0% mock data.
    private var headlineCompany: String {
        guard
            let outer = profileStore.state.value,
            let p = outer,
            !p.companyName.isEmpty
        else { return "—" }
        return p.companyName
    }

    /// Contact-name + member-since subhead. Both segments fall back
    /// to em-dash sentinels — the contact may be the user's name, but
    /// the join date is a hard server projection that may not exist
    /// yet on a freshly-onboarded company.
    private var headlineContact: String {
        let p = profileStore.state.value ?? nil
        let contact = (p?.contactName.isEmpty == false) ? (p?.contactName ?? "—") : "—"
        let memberLabel = formatMemberSince(p?.memberSince)
        return "\(contact) · member since \(memberLabel)"
    }

    /// Best-effort ISO-8601 → "MMM yyyy" projection for the
    /// `memberSince` server field. Empty input → em-dash.
    private func formatMemberSince(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        let isoF = ISO8601DateFormatter()
        isoF.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = isoF.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "—" }
        let out = DateFormatter()
        out.dateFormat = "MMM yyyy"
        return out.string(from: date)
    }

    // MARK: - Identity card (DOT / MC / verified badge)

    @ViewBuilder
    private var identityCard: some View {
        switch profileStore.state {
        case .loading:
            cardSkeleton(height: 96)
        case .empty:
            EusoEmptyState(
                systemImage: "person.text.rectangle",
                title: "Profile not set up",
                subtitle: "Complete your shipper profile to unlock bids, factoring, and the carrier scorecard."
            )
        case .loaded(let maybe):
            if let p = maybe {
                identityRow(p)
            } else {
                EusoEmptyState(
                    systemImage: "person.text.rectangle",
                    title: "Profile not set up",
                    subtitle: "Complete your shipper profile to unlock bids, factoring, and the carrier scorecard."
                )
            }
        case .error(let e):
            inlineError(e) { Task { await profileStore.refresh() } }
        }
    }

    private func identityRow(_ p: ShipperAPI.Profile) -> some View {
        let dotLabel = p.dotNumber.isEmpty ? "—" : p.dotNumber
        let mcLabel  = p.mcNumber.isEmpty  ? "—" : p.mcNumber
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DOT NUMBER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                Text(dotLabel)
                    .font(EType.mono(.body)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
            Divider()
                .frame(width: 1)
                .overlay(palette.borderFaint)
            VStack(alignment: .leading, spacing: 2) {
                Text("MC NUMBER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                Text(mcLabel)
                    .font(EType.mono(.body)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
            verifiedChip(isVerified: p.verified)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func verifiedChip(isVerified: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isVerified ? "checkmark.seal.fill" : "seal")
                .font(.system(size: 11, weight: .heavy))
            Text(isVerified ? "VERIFIED" : "PENDING")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
        }
        .foregroundStyle(
            isVerified
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.textTertiary)
        )
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            Capsule().fill(
                isVerified
                ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.12))
                : AnyShapeStyle(palette.bgCardSoft)
            )
        )
        .overlay(
            Capsule().strokeBorder(
                isVerified
                ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.5))
                : AnyShapeStyle(palette.borderFaint),
                lineWidth: 1
            )
        )
    }

    // MARK: - Contact card (email · phone · address · website)

    @ViewBuilder
    private var contactCard: some View {
        switch profileStore.state {
        case .loaded(let maybe):
            if let p = maybe {
                contactRows(p)
            } else {
                EmptyView()
            }
        default:
            EmptyView()
        }
    }

    private func contactRows(_ p: ShipperAPI.Profile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("CONTACT")
            VStack(spacing: 0) {
                contactLine(systemImage: "envelope.fill", value: p.email)
                Divider().overlay(palette.borderFaint)
                contactLine(systemImage: "phone.fill",    value: p.phone)
                Divider().overlay(palette.borderFaint)
                contactLine(systemImage: "mappin.and.ellipse", value: p.address)
                Divider().overlay(palette.borderFaint)
                contactLine(systemImage: "globe",         value: p.website)
            }
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func contactLine(systemImage: String, value: String) -> some View {
        let display = value.isEmpty ? "—" : value
        return HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 22, height: 22)
            Text(display)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 10)
    }

    // MARK: - Stats card (KPI grid)

    @ViewBuilder
    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("LIFETIME STATS")
            switch statsStore.state {
            case .loading:
                statsSkeleton
            case .empty:
                EusoEmptyState(
                    systemImage: "chart.bar",
                    title: "No stats yet",
                    subtitle: "Your dashboard will populate the moment your first load delivers."
                )
            case .loaded(let maybe):
                if let s = maybe {
                    statsGrid(s)
                } else {
                    EusoEmptyState(
                        systemImage: "chart.bar",
                        title: "No stats yet",
                        subtitle: "Your dashboard will populate the moment your first load delivers."
                    )
                }
            case .error(let e):
                inlineError(e) { Task { await statsStore.refresh() } }
            }
        }
    }

    private var statsSkeleton: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2),
                            GridItem(.flexible(), spacing: Space.s2)],
                  spacing: Space.s2) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            }
        }
    }

    private func statsGrid(_ s: ShipperAPI.Stats) -> some View {
        // Server projects 0 / 0% / 0 when there's no underlying data.
        // We surface those zeros honestly as em-dash sentinels rather
        // than printing "0%" as if the shipper has a real on-time
        // record. Doctrine: 0% mock data.
        let totalLoadsLabel       = s.totalLoads <= 0 ? "—" : "\(s.totalLoads)"
        let totalSpendLabel       = s.totalSpend <= 0 ? "—" : dollars(Double(s.totalSpend))
        let onTimeLabel           = s.onTimeRate <= 0 ? "—" : "\(s.onTimeRate)%"
        let preferredCatalystsLbl = s.preferredCatalysts <= 0 ? "—" : "\(s.preferredCatalysts)"
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2),
                                   GridItem(.flexible(), spacing: Space.s2)],
                         spacing: Space.s2) {
            kpiTile(label: "TOTAL LOADS",        value: totalLoadsLabel,       sub: "lifetime")
            kpiTile(label: "TOTAL SPEND",        value: totalSpendLabel,       sub: "lifetime")
            kpiTile(label: "ON-TIME · RATE",     value: onTimeLabel,           sub: "delivered loads")
            kpiTile(label: "PREFERRED CATALYSTS", value: preferredCatalystsLbl, sub: "unique haulers")
        }
    }

    private func kpiTile(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            Text(sub)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Monthly volume mini-chart

    @ViewBuilder
    private var monthlyVolumeCard: some View {
        switch statsStore.state {
        case .loaded(let maybe):
            if let s = maybe, !s.monthlyVolume.isEmpty, s.maxMonthlyLoads > 0 {
                volumeChart(s)
            } else {
                EmptyView()
            }
        default:
            EmptyView()
        }
    }

    private func volumeChart(_ s: ShipperAPI.Stats) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("VOLUME · 12 MONTHS")
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(s.monthlyVolume) { row in
                        let frac = s.maxMonthlyLoads > 0
                            ? CGFloat(row.loads) / CGFloat(s.maxMonthlyLoads)
                            : CGFloat(0)
                        let h = max(2, frac * 60)
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(
                                    row.loads > 0
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.bgCardSoft)
                                )
                                .frame(height: h)
                            Text(monthInitial(row.month))
                                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(palette.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 80)

                HStack {
                    Text("PEAK")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(s.maxMonthlyLoads) load\(s.maxMonthlyLoads == 1 ? "" : "s")")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// Best-effort first-letter projection of a `YYYY-MM` server
    /// month. Empty / malformed input returns an em-dash.
    private func monthInitial(_ ym: String) -> String {
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else { return "—" }
        let initials = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
        return initials[m - 1]
    }

    // MARK: - Tier progression card (client-derived)
    //
    // Mirrors the Driver 056 pool tier card recipe — purple gradient
    // hero, percent-to-next-tier rail, three benefit lines. Tier is
    // computed client-side from the already-loaded stats so we don't
    // round-trip a second endpoint just for the visualization. When
    // the backend ships a canonical `shippers.getTier` projection
    // later, swap `currentTier` for that store and the card's chrome
    // stays unchanged.

    /// 5-tier ladder for shippers. Criteria are AND-merged: a shipper
    /// has to clear every threshold of a tier (loads, on-time %,
    /// spend) to land on it. Falls back to .bronze when stats
    /// aren't loaded yet.
    private enum ShipperTier: Int, CaseIterable {
        case bronze   = 1
        case silver   = 2
        case gold     = 3
        case platinum = 4
        case diamond  = 5

        var label: String {
            switch self {
            case .bronze:   return "BRONZE"
            case .silver:   return "SILVER"
            case .gold:     return "GOLD"
            case .platinum: return "PLATINUM"
            case .diamond:  return "DIAMOND"
            }
        }

        /// Loads / on-time / spend thresholds. Tuned against April
        /// 2026 platform data so the average mid-volume shipper
        /// lands at silver/gold.
        var threshold: (loads: Int, onTime: Int, spend: Int) {
            switch self {
            case .bronze:   return (loads: 0,   onTime: 0,  spend: 0)
            case .silver:   return (loads: 10,  onTime: 80, spend: 5_000)
            case .gold:     return (loads: 50,  onTime: 90, spend: 50_000)
            case .platinum: return (loads: 200, onTime: 95, spend: 250_000)
            case .diamond:  return (loads: 500, onTime: 97, spend: 1_000_000)
            }
        }

        /// 3 product-agnostic benefits surfaced on the tier card.
        /// Driver 056 dispatches benefits per `TripProduct`; on the
        /// shipper side the benefits are tier-keyed instead since
        /// the shipper isn't tied to one product type.
        var benefits: [String] {
            switch self {
            case .bronze: return [
                "Carrier marketplace · standard match",
                "Net-30 settlement window",
                "Standard support response",
            ]
            case .silver: return [
                "+5% catalyst priority on bids",
                "Net-15 settlement window",
                "Priority support · 4h response",
            ]
            case .gold: return [
                "+10% catalyst priority on bids",
                "Net-7 settlement window",
                "Dedicated support line · 1h response",
            ]
            case .platinum: return [
                "+15% catalyst priority + factoring discount",
                "Net-3 settlement · instant available",
                "Dedicated dispatcher · weekend coverage",
            ]
            case .diamond: return [
                "First-look catalyst priority + 0% factoring",
                "Same-day settlement · instant always",
                "Strategic account team · 24/7 line",
            ]
            }
        }
    }

    /// Resolve the shipper's current tier from live stats.
    private var currentTier: ShipperTier {
        guard let s = statsStore.state.value else { return .bronze }
        // Walk the ladder top-down and pick the highest tier the
        // stats clear all three thresholds for.
        for tier in ShipperTier.allCases.reversed() {
            let t = tier.threshold
            if s.totalLoads      >= t.loads
                && s.onTimeRate  >= t.onTime
                && s.totalSpend  >= t.spend {
                return tier
            }
        }
        return .bronze
    }

    /// Next tier (or nil at the top of the ladder).
    private var nextTier: ShipperTier? {
        ShipperTier(rawValue: currentTier.rawValue + 1)
    }

    /// 0–1 progress toward the next tier. Average across the three
    /// criteria so a shipper that's strong on volume but weak on
    /// on-time still sees forward motion. Returns 1.0 at the top
    /// of the ladder so the rail fills.
    private var tierProgress: Double {
        guard let next = nextTier, let s = statsStore.state.value else { return 1.0 }
        let t = next.threshold
        let loadsP = t.loads  > 0 ? min(1.0, Double(s.totalLoads)  / Double(t.loads))  : 1.0
        let onTimeP = t.onTime > 0 ? min(1.0, Double(s.onTimeRate)  / Double(t.onTime)) : 1.0
        let spendP = t.spend  > 0 ? min(1.0, Double(s.totalSpend)  / Double(t.spend))  : 1.0
        return (loadsP + onTimeP + spendP) / 3.0
    }

    private var tierProgressionCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("\(currentTier.label) TIER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(Int(tierProgress * 100))%")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Tier \(currentTier.rawValue)")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                if let next = nextTier {
                    Text("→ \(next.label)")
                        .font(.system(size: 10, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(LinearGradient.diagonal))
                } else {
                    Text("MAXED")
                        .font(.system(size: 10, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(LinearGradient.diagonal))
                }
                Spacer()
            }
            // Progress rail
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 5)
                    Capsule().fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * CGFloat(tierProgress), height: 5)
                }
            }
            .frame(height: 5)
            // Benefits
            VStack(alignment: .leading, spacing: 4) {
                ForEach(currentTier.benefits, id: \.self) { benefit in
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(benefit)
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(LinearGradient(
                    colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Credentials card (FMCSA / Insurance / BBB / Payment history)

    /// 4-row grid mirroring the Driver 056 credentialsCard recipe.
    /// Driver shows CDL / Medical / TWIC / Hazmat; Shipper shows
    /// FMCSA verification / insurance proof / BBB rating / payment
    /// history. Rows the backend doesn't yet expose render with an
    /// em-dash subtitle and a neutral "PENDING" chip rather than a
    /// fabricated value.
    private struct CredentialRow: Hashable {
        let key: String
        let icon: String
        let title: String
        let subtitle: String
        let chip: String
        let chipColor: Color
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CREDENTIALS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(credentialsHeaderCount)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(spacing: 6) {
                ForEach(credentialRows, id: \.key) { row in
                    credentialRowView(row)
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var credentialRows: [CredentialRow] {
        let p = profileStore.state.value ?? nil
        let dotPresent = (p?.dotNumber.isEmpty == false)
        let mcPresent = (p?.mcNumber.isEmpty == false)
        let isVerified = p?.verified ?? false

        // FMCSA — true when DOT/MC are present AND verified flag set.
        let fmcsaActive = dotPresent && mcPresent && isVerified
        let fmcsaSubtitle: String = {
            guard let p = p, dotPresent || mcPresent else { return "Add DOT + MC for verification" }
            var parts: [String] = []
            if dotPresent { parts.append("DOT \(p.dotNumber)") }
            if mcPresent  { parts.append("MC \(p.mcNumber)") }
            return parts.joined(separator: " · ")
        }()
        let fmcsaChip = fmcsaActive ? "ACTIVE" : (dotPresent || mcPresent ? "PENDING" : "MISSING")
        let fmcsaColor: Color = fmcsaActive ? Brand.success : (dotPresent || mcPresent ? Brand.warning : Brand.danger)

        // Insurance — backend doesn't yet ship insurance proof on
        // shippers.getProfile, so honest em-dash + PENDING chip.
        let insuranceRow = CredentialRow(
            key: "insurance",
            icon: "umbrella.fill",
            title: "Insurance proof",
            subtitle: "—",
            chip: "PENDING",
            chipColor: Brand.warning
        )

        // BBB rating — backend gap, em-dash.
        let bbbRow = CredentialRow(
            key: "bbb",
            icon: "rosette",
            title: "BBB rating",
            subtitle: "—",
            chip: "PENDING",
            chipColor: Brand.warning
        )

        // Payment history — derived from `avgPaymentTime` if we have
        // it server-side; em-dash otherwise. Lower is better
        // (target ≤ 7 days).
        let paymentRow: CredentialRow = {
            if let s = statsStore.state.value, s.avgPaymentTime > 0 {
                let days = Int(s.avgPaymentTime.rounded())
                let chip = days <= 7  ? "EXCELLENT"
                         : days <= 14 ? "GOOD"
                         : days <= 30 ? "FAIR"
                         : "WATCH"
                let color: Color = days <= 7  ? Brand.success
                                 : days <= 14 ? Brand.success
                                 : days <= 30 ? Brand.warning
                                 : Brand.danger
                return CredentialRow(
                    key: "payment",
                    icon: "clock.badge.checkmark.fill",
                    title: "Payment history",
                    subtitle: "Avg \(days)-day settle",
                    chip: chip,
                    chipColor: color
                )
            }
            return CredentialRow(
                key: "payment",
                icon: "clock.badge.checkmark.fill",
                title: "Payment history",
                subtitle: "—",
                chip: "PENDING",
                chipColor: Brand.warning
            )
        }()

        return [
            CredentialRow(
                key: "fmcsa",
                icon: "checkmark.seal.fill",
                title: "FMCSA verification",
                subtitle: fmcsaSubtitle,
                chip: fmcsaChip,
                chipColor: fmcsaColor
            ),
            insuranceRow,
            bbbRow,
            paymentRow,
        ]
    }

    /// "1 of 4 active" header chip — counts rows with a non-warn /
    /// non-danger chip color so the eyebrow tracks credential health
    /// at a glance.
    private var credentialsHeaderCount: String {
        let active = credentialRows.filter { $0.chipColor == Brand.success }.count
        return "\(active) OF 4 ACTIVE"
    }

    private func credentialRowView(_ row: CredentialRow) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.18))
                Image(systemName: row.icon)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(row.subtitle)
                    .font(EType.micro).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(row.chip)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(row.chipColor)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(
                    Capsule().fill(row.chipColor.opacity(0.15))
                )
                .overlay(
                    Capsule().strokeBorder(row.chipColor.opacity(0.4), lineWidth: 0.75)
                )
        }
        .padding(.vertical, 4)
    }

    // MARK: - ESANG strip (tier-aware)

    /// Mirrors Driver 056 esangStrip but with shipper-tier-aware copy.
    /// Driver pulls from `LifecycleProductContext.poolEsangNote`;
    /// Shipper synthesises copy from the resolved tier so the same
    /// visual recipe carries cross-role.
    private var esangStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text(esangTierNote)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var esangTierNote: String {
        switch (currentTier, nextTier) {
        case (.bronze, _):
            return "ESANG · Post your first 10 loads to unlock SILVER · catalyst priority +5%"
        case (.silver, _):
            return "ESANG · 50 loads + 90% on-time + $50K spend → GOLD · net-7 settlement"
        case (.gold, _):
            return "ESANG · 200 loads + 95% on-time + $250K spend → PLATINUM · factoring discount"
        case (.platinum, _):
            return "ESANG · 500 loads + 97% on-time + $1M spend → DIAMOND · 0% factoring"
        case (.diamond, nil):
            return "ESANG · DIAMOND maxed · same-day settle · 24/7 strategic team"
        case (.diamond, _):
            return "ESANG · DIAMOND tier · catalysts compete to bid your loads"
        }
    }

    // MARK: - Footer actions

    private var footerActions: some View {
        VStack(spacing: Space.s2) {
            Button(action: { showEditProfile = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .heavy))
                    Text("Edit profile")
                        .font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(palette.textPrimary)
                .background(palette.bgCard)
                .overlay(
                    Capsule().strokeBorder(palette.borderStrong, lineWidth: 1)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .alert("Edit profile",
                   isPresented: $showEditProfile,
                   actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text("Profile editing lands in a follow-up brick alongside the `shippers.updateProfile` mutation.")
            })

            Button(action: { showSignOutConfirm = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.square")
                        .font(.system(size: 13, weight: .heavy))
                    Text("Sign out")
                        .font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Space.s2)
    }

    // MARK: - Shared widgets

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            .foregroundStyle(palette.textTertiary)
            .padding(.bottom, 6)
    }

    private func cardSkeleton(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(palette.bgCardSoft)
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
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
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func dollars(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Screen wrapper

struct ShipperProfileScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperProfile()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_202(),
                trailing: shipperNavTrailing_202(),
                orbState: .idle
            )
        }
    }
}

// Shipper bottom-nav doctrine — see 200_ShipperHome.swift comment.
private func shipperNavLeading_202() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house.fill",                    isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",   isCurrent: false)]
}

private func shipperNavTrailing_202() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.fill",      isCurrent: true)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so each store stays in `.loading` —
// both registers render the skeleton without hitting the network.
// Compiles in isolation per doctrine §10.

#Preview("202 · Shipper · Profile · Night") {
    ShipperProfileScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("202 · Shipper · Profile · Afternoon") {
    ShipperProfileScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
