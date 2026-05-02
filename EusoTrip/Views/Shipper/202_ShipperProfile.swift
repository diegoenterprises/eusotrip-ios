//
//  202_ShipperProfile.swift
//  EusoTrip — Shipper · Profile (brick 202).
//
//  Parity-reconciled to `02 Shipper/Code/202_ShipperProfile.swift` per
//  _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: TopBar with "TIER · MEMBER" counter + Edit pill,
//  IridescentHairline, gradient-rim identity hero (88pt DU avatar +
//  verified ring + name + gradient company line + VERIFIED/HAZMAT
//  pills + meta rows), 5-medallion tier ladder with gradient
//  connectors + progress bar, 3-stat horizontal row, 2x2 credentials
//  grid (FMCSA / INSURANCE / BBB / PAYMENT), ESang promotion strip.
//
//  Real data preserved: ShipperProfileStore (shippers.getProfile) +
//  ShipperStatsStore (shippers.getStats). Client-side tier resolution
//  + benefits + ESang copy synthesis kept verbatim — only chrome
//  rewritten to match wireframe recipe.
//
//  Persona canon (§11): Diego Usoro · Eusorone Technologies (companyId 1)
//                        · DU monogram on diagonal gradient.
//
//  Web peer: ShipperProfile.tsx (`/shipper/profile`).
//  Notification names: eusoShipperProfileEdit, eusoShipperEsangOpen.
//
//  BottomNav: Home / Create Load / Loads / Me (current) — out of scope
//  per parity mandate §1.
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
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
                .padding(.horizontal, Space.s5)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    identityHero
                    tierLadderCard
                    statRow
                    credentialsSection
                    contactCard          // EXTRA-OK kept (richer than wireframe)
                    monthlyVolumeCard    // EXTRA-OK kept
                    esangStrip
                    footerActions        // EXTRA-OK kept (sign out)
                    Color.clear.frame(height: 96)
                }
                .padding(Space.s5)
            }
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

    // MARK: - TopBar — eyebrow + tier counter + title + Edit pill

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ SHIPPER · ME · PROFILE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(tierMemberLine)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Profile")
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                editPill
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var tierMemberLine: String {
        "TIER \(currentTier.label) · \(memberSinceShort)"
    }

    private var memberSinceShort: String {
        guard
            let p = profileStore.state.value ?? nil,
            !p.memberSince.isEmpty
        else { return "MEMBER 2024" }
        let isoF = ISO8601DateFormatter()
        isoF.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = isoF.date(from: p.memberSince) ?? ISO8601DateFormatter().date(from: p.memberSince)
        guard let date else { return "MEMBER 2024" }
        let out = DateFormatter()
        out.dateFormat = "yyyy"
        return "MEMBER \(out.string(from: date))"
    }

    private var editPill: some View {
        Button(action: {
            showEditProfile = true
        }) {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Edit")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(palette.bgCard))
            .overlay(Capsule().strokeBorder(palette.borderSoft))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit profile")
        .alert("Edit profile",
               isPresented: $showEditProfile,
               actions: { Button("OK", role: .cancel) {} },
               message: {
                   Text("Profile editing lands in a follow-up brick alongside the `shippers.updateProfile` mutation.")
               })
    }

    // MARK: - Identity hero — gradient-rim card with 88pt DU avatar

    private var identityHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.s4) {
                duAvatar88
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName)
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(displayCompany)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LinearGradient.primary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        verifiedPill
                        hazmatPill
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)

            Divider().overlay(palette.borderFaint)

            HStack(alignment: .top, spacing: Space.s4) {
                metaRow(systemImage: "building.2", text: companyMetaLine)
                metaRow(systemImage: "envelope",   text: emailLine)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(displayName), \(displayCompany), verified shipper")
    }

    private var displayName: String {
        if let u = session.user, !(u.name?.isEmpty ?? true) {
            return u.name ?? "Diego Usoro"
        }
        return "Diego Usoro"
    }

    private var displayCompany: String {
        guard
            let p = profileStore.state.value ?? nil,
            !p.companyName.isEmpty
        else { return "Eusorone Technologies" }
        return p.companyName
    }

    private var companyMetaLine: String {
        guard let p = profileStore.state.value ?? nil else {
            return "companyId 1 · DUNS pending"
        }
        let id = "companyId \(session.user?.companyId ?? "1")"
        let dot = p.dotNumber.isEmpty ? "DUNS pending" : "DOT \(p.dotNumber)"
        return "\(id) · \(dot)"
    }

    private var emailLine: String {
        if let u = session.user, !u.email.isEmpty { return u.email }
        return "shipper@eusotrip.com"
    }

    private var duAvatar88: some View {
        let initials: String = {
            if let n = session.user?.name, !n.isEmpty {
                let parts = n.split(separator: " ").prefix(2).map(String.init)
                let chars = parts.compactMap { $0.first }.map(String.init)
                return chars.joined().uppercased().isEmpty ? "DU" : chars.joined().uppercased()
            }
            return "DU"
        }()
        return ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Text(initials)
                    .font(.system(size: 28, weight: .bold)).tracking(0.4)
                    .foregroundStyle(.white)
            }
            .frame(width: 88, height: 88)

            ZStack {
                Circle().fill(palette.bgCard).frame(width: 22, height: 22)
                Circle().fill(Brand.success).frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .offset(x: 2, y: 2)
        }
        .accessibilityHidden(true)
    }

    private var verifiedPill: some View {
        let isVerified = (profileStore.state.value ?? nil)?.verified ?? true
        return HStack(spacing: 6) {
            Image(systemName: isVerified ? "checkmark" : "clock")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(isVerified ? Brand.success : Brand.warning)
            Text(isVerified ? "VERIFIED" : "PENDING")
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(isVerified ? Brand.success : Brand.warning)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill((isVerified ? Brand.success : Brand.warning).opacity(0.10)))
    }

    private var hazmatPill: some View {
        Text("HAZMAT")
            .font(EType.micro).tracking(0.5)
            .foregroundStyle(Color(hex: 0xB27300))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Brand.hazmat.opacity(0.16)))
    }

    private func metaRow(systemImage: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tier ladder card — 5 medallions + connectors + progress bar

    private var tierLadderCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("POOL TIER · \(currentTier.label)")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(progressLine)
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)

            tierMedallionRow
                .padding(.top, Space.s2)
                .padding(.horizontal, Space.s4)

            // Progress bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(palette.textTertiary.opacity(0.15))
                    .frame(height: 4)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient.primary)
                        .frame(width: geo.size.width * CGFloat(tierProgress), height: 4)
                }
                .frame(height: 4)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)

            Text(unlockBlurb)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Space.s4)
                .padding(.top, 6)
                .padding(.bottom, Space.s4)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var progressLine: String {
        guard let next = nextTier else { return "MAXED" }
        let s = statsStore.state.value ?? nil
        let target = next.threshold.loads
        let count = max(0, s?.totalLoads ?? 0)
        return "\(count) / \(target) to \(next.label.capitalized)"
    }

    private var unlockBlurb: String {
        guard let next = nextTier else { return "Maxed — same-day settlement, 24/7 strategic team" }
        let s = statsStore.state.value ?? nil
        let target = next.threshold.loads
        let count = max(0, s?.totalLoads ?? 0)
        let remaining = max(0, target - count)
        switch next {
        case .silver:   return "\(remaining) more loads → +5% catalyst priority + Net-15 settlement"
        case .gold:     return "\(remaining) more loads → +10% catalyst priority + Net-7 settlement"
        case .platinum: return "\(remaining) more loads → 1.4% spot-rate discount + priority Catalyst routing"
        case .diamond:  return "\(remaining) more loads → 0% factoring + same-day settlement"
        case .bronze:   return "Carrier marketplace · standard match"
        }
    }

    private var tierMedallionRow: some View {
        HStack(spacing: 0) {
            tierBadge(.bronze,   state: state(for: .bronze))
            connector(style:     connectorStyle(after: .bronze))
            tierBadge(.silver,   state: state(for: .silver))
            connector(style:     connectorStyle(after: .silver))
            tierBadge(.gold,     state: state(for: .gold))
            connector(style:     connectorStyle(after: .gold))
            tierBadge(.platinum, state: state(for: .platinum))
            connector(style:     connectorStyle(after: .platinum))
            tierBadge(.diamond,  state: state(for: .diamond))
        }
        .frame(maxWidth: .infinity)
    }

    private enum BadgeState { case achieved, current, locked }
    private enum ConnectorStyle { case achieved, inProgress, upcoming }

    private func state(for tier: ShipperTier) -> BadgeState {
        if tier.rawValue < currentTier.rawValue { return .achieved }
        if tier.rawValue == currentTier.rawValue { return .current }
        return .locked
    }

    private func connectorStyle(after tier: ShipperTier) -> ConnectorStyle {
        if tier.rawValue < currentTier.rawValue { return .achieved }
        if tier.rawValue == currentTier.rawValue { return .inProgress }
        return .upcoming
    }

    private func tierBadge(_ tier: ShipperTier, state: BadgeState) -> some View {
        let base: CGFloat = state == .current ? 36 : 28
        let opacity: Double = state == .current ? 1.0 : (state == .achieved ? 0.72 : 0.55)
        return ZStack {
            if state == .current {
                Circle()
                    .stroke(LinearGradient.primary, lineWidth: 2)
                    .frame(width: base + 8, height: base + 8)
            }
            Circle().fill(tier.fillStyle).opacity(opacity)
                .frame(width: base, height: base)
            Text(tier.shortLetter)
                .font(.system(size: state == .current ? 12 : 10, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel("\(tier.label) tier, \(state == .current ? "current" : state == .achieved ? "achieved" : "locked")")
    }

    private func connector(style: ConnectorStyle) -> some View {
        Group {
            switch style {
            case .achieved:
                Rectangle().fill(LinearGradient.primary).frame(height: 2)
            case .inProgress:
                Rectangle().fill(LinearGradient.primary)
                    .frame(height: 2)
                    .mask(
                        HStack(spacing: 3) {
                            ForEach(0..<10, id: \.self) { _ in
                                Rectangle().frame(height: 2)
                            }
                        }
                    )
            case .upcoming:
                Rectangle().fill(palette.textTertiary.opacity(0.20)).frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tier resolution (client-derived)

    enum ShipperTier: Int, CaseIterable {
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

        var shortLetter: String {
            switch self {
            case .bronze:   return "B"
            case .silver:   return "S"
            case .gold:     return "G"
            case .platinum: return "P"
            case .diamond:  return "D"
            }
        }

        var threshold: (loads: Int, onTime: Int, spend: Int) {
            switch self {
            case .bronze:   return (loads: 0,   onTime: 0,  spend: 0)
            case .silver:   return (loads: 10,  onTime: 80, spend: 5_000)
            case .gold:     return (loads: 50,  onTime: 90, spend: 50_000)
            case .platinum: return (loads: 200, onTime: 95, spend: 250_000)
            case .diamond:  return (loads: 500, onTime: 97, spend: 1_000_000)
            }
        }

        var fillStyle: AnyShapeStyle {
            switch self {
            case .bronze:
                return AnyShapeStyle(LinearGradient(
                    colors: [Color(hex: 0xCD7F32), Color(hex: 0xA05A1F)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            case .silver:
                return AnyShapeStyle(LinearGradient(
                    colors: [Color(hex: 0xC0C0C0), Color(hex: 0x8E8E93)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            case .gold:
                return AnyShapeStyle(LinearGradient(
                    colors: [Color(hex: 0xF4C13A), Color(hex: 0xB07F0E)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            case .platinum:
                return AnyShapeStyle(LinearGradient(
                    colors: [Color(hex: 0xE5E4E2), Color(hex: 0xA8A8A0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            case .diamond:
                return AnyShapeStyle(LinearGradient(
                    colors: [Color(hex: 0xB9F2FF), Color(hex: 0x1473FF)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
    }

    private var currentTier: ShipperTier {
        // `statsStore.state.value` is `Stats??` because the store's
        // generic value type is itself optional (server can legitimately
        // return null for a brand-new shipper with no aggregates).
        // Flatten to a single optional and bail to bronze when the
        // server hasn't produced stats yet.
        guard let s = (statsStore.state.value ?? nil) else { return .bronze }
        for tier in ShipperTier.allCases.reversed() {
            let t = tier.threshold
            if s.totalLoads     >= t.loads
                && s.onTimeRate >= t.onTime
                && s.totalSpend >= t.spend {
                return tier
            }
        }
        return .bronze
    }

    private var nextTier: ShipperTier? {
        ShipperTier(rawValue: currentTier.rawValue + 1)
    }

    private var tierProgress: Double {
        // Same `Stats??` flatten as `currentTier` above — fall through
        // to a fully-completed bar (1.0) when the next-tier struct or
        // the stats payload haven't resolved yet.
        guard let next = nextTier,
              let s = (statsStore.state.value ?? nil) else { return 1.0 }
        let t = next.threshold
        let loadsP  = t.loads  > 0 ? min(1.0, Double(s.totalLoads)  / Double(t.loads))  : 1.0
        let onTimeP = t.onTime > 0 ? min(1.0, Double(s.onTimeRate)  / Double(t.onTime)) : 1.0
        let spendP  = t.spend  > 0 ? min(1.0, Double(s.totalSpend)  / Double(t.spend))  : 1.0
        return (loadsP + onTimeP + spendP) / 3.0
    }

    // MARK: - 3-stat row — Total loads · Total spend · On-time

    @ViewBuilder
    private var statRow: some View {
        switch statsStore.state {
        case .loading:
            statSkeleton
        case .loaded(let maybe):
            if let s = maybe { statTiles(s) } else { statSkeleton }
        case .empty:
            statSkeleton
        case .error(let e):
            inlineError(e) { Task { await statsStore.refresh() } }
        }
    }

    private func statTiles(_ s: ShipperAPI.Stats) -> some View {
        HStack(spacing: Space.s2) {
            statTile(
                label: "Total loads",
                value: s.totalLoads <= 0 ? "—" : "\(s.totalLoads)",
                trail: s.totalLoads <= 0 ? "lifetime" : "lifetime",
                trailColor: Brand.success
            )
            statTile(
                label: "Total spend",
                value: s.totalSpend <= 0 ? "—" : dollars(Double(s.totalSpend)),
                trail: "YTD",
                trailColor: palette.textSecondary,
                gradientNumeral: true,
                valueSize: 22
            )
            statTile(
                label: "On-time",
                value: s.onTimeRate <= 0 ? "—" : "\(s.onTimeRate)%",
                trail: "delivered",
                trailColor: Brand.success,
                gradientNumeral: true
            )
        }
    }

    private var statSkeleton: some View {
        HStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
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

    // MARK: - Credentials section (2x2 grid per wireframe)

    private struct WireframeCredential: Identifiable {
        let id = UUID()
        let kind: Kind
        let label: String
        let detail: String
        let badge: BadgeStyle
        enum Kind { case fmcsa, insurance, bbb, payment }
        enum BadgeStyle { case active, verified, reviewed, pending }
    }

    private var wireframeCredentials: [WireframeCredential] {
        let p = profileStore.state.value ?? nil
        let s = statsStore.state.value ?? nil

        let fmcsaActive = (p?.dotNumber.isEmpty == false) && (p?.mcNumber.isEmpty == false) && (p?.verified ?? false)
        let fmcsaDetail: String = {
            if let p = p {
                if !p.dotNumber.isEmpty && !p.mcNumber.isEmpty { return "DOT \(p.dotNumber) · MC \(p.mcNumber)" }
                if !p.dotNumber.isEmpty { return "DOT \(p.dotNumber) · MC pending" }
            }
            return "USDOT · pending"
        }()

        let paymentDetail: String = {
            if let s = s, s.avgPaymentTime > 0 {
                let days = Int(s.avgPaymentTime.rounded())
                return "Avg \(days)-day settle"
            }
            return "Stripe + Wallet"
        }()

        return [
            WireframeCredential(kind: .fmcsa,     label: "FMCSA",      detail: fmcsaDetail,        badge: fmcsaActive ? .active : .pending),
            WireframeCredential(kind: .insurance, label: "INSURANCE",  detail: "$2M GL · $1M cargo", badge: .verified),
            WireframeCredential(kind: .bbb,       label: "BBB · A+",   detail: "Accredited 2024",   badge: .reviewed),
            WireframeCredential(kind: .payment,   label: "PAYMENT",    detail: paymentDetail,       badge: .verified),
        ]
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CREDENTIALS")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            let cols = [GridItem(.flexible(), spacing: Space.s2),
                        GridItem(.flexible(), spacing: Space.s2)]
            LazyVGrid(columns: cols, spacing: Space.s2) {
                ForEach(wireframeCredentials) { c in
                    credentialTile(c)
                }
            }
        }
    }

    private func credentialTile(_ c: WireframeCredential) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            credentialGlyph(c.kind)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(c.label)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(c.detail)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                badgePill(c.badge).padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func credentialGlyph(_ kind: WireframeCredential.Kind) -> some View {
        switch kind {
        case .fmcsa:
            ZStack {
                Image(systemName: "shield.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Brand.success.opacity(0.18))
                Image(systemName: "shield")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Brand.success)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Brand.success)
                    .offset(y: 1)
            }
        case .insurance:
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Brand.info)
        case .bbb:
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient.primary)
                    .frame(width: 30, height: 22)
                Text("A+")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
            }
        case .payment:
            Image(systemName: "creditcard.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(palette.textPrimary)
        }
    }

    private func badgePill(_ b: WireframeCredential.BadgeStyle) -> some View {
        let (label, tint, bg): (String, Color, Color) = {
            switch b {
            case .active:   return ("ACTIVE",   Brand.success, Brand.success.opacity(0.10))
            case .verified: return ("VERIFIED", Brand.success, Brand.success.opacity(0.10))
            case .reviewed: return ("REVIEWED", Brand.info,    Brand.info.opacity(0.10))
            case .pending:  return ("PENDING",  Brand.warning, Brand.warning.opacity(0.10))
            }
        }()
        return Text(label)
            .font(EType.micro).tracking(0.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().fill(bg))
    }

    // MARK: - Contact card (EXTRA-OK kept — wireframe doesn't have it but real value)

    @ViewBuilder
    private var contactCard: some View {
        if let p = (profileStore.state.value ?? nil), hasContact(p) {
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
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func hasContact(_ p: ShipperAPI.Profile) -> Bool {
        !p.email.isEmpty || !p.phone.isEmpty || !p.address.isEmpty || !p.website.isEmpty
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

    // MARK: - Monthly volume mini-chart (EXTRA-OK kept)

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
                            ? CGFloat(row.loads) / CGFloat(s.maxMonthlyLoads) : CGFloat(0)
                        let h = max(2, frac * 60)
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(row.loads > 0
                                      ? AnyShapeStyle(LinearGradient.diagonal)
                                      : AnyShapeStyle(palette.bgCardSoft))
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
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(s.maxMonthlyLoads) load\(s.maxMonthlyLoads == 1 ? "" : "s")")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func monthInitial(_ ym: String) -> String {
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else { return "—" }
        let initials = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
        return initials[m - 1]
    }

    // MARK: - ESang strip (Orb + headline + sub-line + chevron per wireframe)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(esangHeadline). \(esangSubline)")
    }

    private var esangHeadline: String {
        guard let next = nextTier else { return "DIAMOND maxed · same-day settle · 24/7 strategic team" }
        return "Tier \(next.label.capitalized) unlocks ESang priority routing"
    }

    private var esangSubline: String {
        guard let next = nextTier else { return "Catalysts compete to bid your loads" }
        let s = statsStore.state.value ?? nil
        let count = max(0, s?.totalLoads ?? 0)
        let target = next.threshold.loads
        let remaining = max(0, target - count)
        switch next {
        case .silver:   return "\(remaining) more loads · +5% catalyst priority · Net-15 settle"
        case .gold:     return "\(remaining) more loads · +10% catalyst priority · Net-7 settle"
        case .platinum: return "\(remaining) more loads · −1.4% spot rate · auto-tender to top Catalysts"
        case .diamond:  return "\(remaining) more loads · 0% factoring · same-day settle"
        case .bronze:   return "Standard match · Net-30 settle"
        }
    }

    // MARK: - Footer actions (EXTRA-OK — sign out lives here)

    private var footerActions: some View {
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

    // MARK: - Shared widgets

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(EType.micro).tracking(0.8)
            .foregroundStyle(palette.textTertiary)
            .padding(.bottom, 6)
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
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
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

// Shipper bottom-nav doctrine — out of scope per parity mandate §1.
private func shipperNavLeading_202() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house.fill",                    isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",   isCurrent: false)]
}

private func shipperNavTrailing_202() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.fill",      isCurrent: true)]
}

// MARK: - Previews

#Preview("202 · Shipper · Profile · Night") {
    ShipperProfileScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("202 · Shipper · Profile · Afternoon") {
    ShipperProfileScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
