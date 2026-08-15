//
//  397_CatalystCarrierTier.swift
//  EusoTrip — Catalyst track · carrier back-office growth band.
//
//  Verbatim iOS port of the canonical bespoke 397 Catalyst Carrier Tier
//  (03 Catalyst/Code/397_CatalystCarrierTier.swift) into the iOS house
//  chrome (Shell + BottomNav). NOT the stamped home/detail skeleton: the
//  body is a TIER-LADDER — a circular progress-ring hero showing the gap
//  to the next tier, then a vertical rung ladder
//  (Diamond → Platinum → Gold[current] → Silver → Bronze) where each rung
//  states its qualification thresholds + achieved/locked state, then the
//  active tier's benefit tiles. The screen makes the reward for
//  reliability legible: 160 points + an OTR target unlock Platinum's
//  1.32× dispatch boost and net-3 pay.
//
//  Moment: Michael Eusorone (Eusotrans LLC owner-op) opens his network
//          standing from the Me tab. Web peer: /catalyst/profile/tier.
//
//  tRPC wiring manifest (line-confirmed on the Code/ spec):
//    • hero tier + points + ring   → carrierTier.getCarrierTier      (carrierTier.ts:27)
//    • dispatch-boost multiplier    → carrierTier.getDispatchBoost     (carrierTier.ts:219)
//    • ladder rungs + thresholds    → carrierTier.getTierDefinitions   (carrierTier.ts:135)
//    • active-tier benefit tiles    → carrierTier.getTierBenefits      (carrierTier.ts:141)
//    • peer rank context            → carrierTier.getTierDistribution  (carrierTier.ts:390)
//  Tier recomputed from carrierScorecard + csaScores + OTR; an upgrade
//  writes a blockchainAudit row and broadcasts WS_EVENTS.CARRIER_TIER_CHANGED
//  on WS_CHANNELS.catalyst(carrierId). RBAC: isolatedProcedure.
//
//  LIVE WIRING (zero-fallback purge · 2026-06-09 · audit B13): reload()
//  fans in carrierTier.getCarrierTier + getTierDefinitions + getTierBenefits
//  + getDispatchBoost against the session company id and builds the entire
//  VM from the real CarrierTierResult (tier, composite score, promotion
//  path, real Gold/Silver/Bronze/Standard ladder from TIER_DEFINITIONS).
//  The old seed's Diamond/Platinum ladder never existed server-side and is
//  GONE. Honest EusoEmptyState when no company tier is computable; em-dash
//  for any missing field. getTierDistribution intentionally not called
//  (N+1 over 500 carriers server-side — peer rank renders em-dash).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Shell wrapper + Catalyst BottomNav (HOME · DISPATCH · [orb] · WALLET · ME — ME current)

struct CatalystCarrierTierScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            CarrierTierBody_397()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_397(),
                trailing: catalystNavTrailing_397(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_397() -> [NavSlot] {
    CarrierNavRoute.leading(current: .me)
}

private func catalystNavTrailing_397() -> [NavSlot] {
    CarrierNavRoute.trailing(current: .me)
}

// MARK: - View model (verbatim from Code/ spec)

private enum TierRungState_397 { case locked, next, current, achieved }

private struct TierRung_397: Identifiable {
    let id: String
    let name: String
    let threshold: String     // mono qualification line
    let state: TierRungState_397
    let trailing: String      // "LOCKED" / "+160 PTS" / "CURRENT" / "ACHIEVED"
}

private struct TierBenefit_397: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let highlight: Bool
}

private struct CarrierTierVM_397 {
    let currentTier: String       // "Gold"
    let points: String            // "1,840"
    let rankLine: String          // "rank 38 of 412"
    let boostLabel: String        // "1.18× DISPATCH BOOST"
    let progressPct: Int          // 72
    let nextTier: String          // "Platinum"
    let ptsToGo: String           // "160 pts to go"
    let rungs: [TierRung_397]
    let benefits: [TierBenefit_397]
    let nextUnlockNote: String    // footer line
}

// MARK: - Body

private struct CarrierTierBody_397: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    // Live VM — starts on the honest em-dash envelope, never a seed.
    @State private var vm: CarrierTierVM_397 = .empty
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var showReachNext: Bool = false
    @State private var showAllBenefits: Bool = false

    private let gold = LinearGradient(
        colors: [Color(red: 0.965, green: 0.776, blue: 0.322),
                 Color(red: 0.843, green: 0.604, blue: 0.133)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            VStack(alignment: .leading, spacing: Space.s4) {
                heroCard
                ladderSection
                benefitsSection
                ctaRow
                if !vm.nextUnlockNote.isEmpty {
                    Text(vm.nextUnlockNote)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s7)
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await reload() }
        }
        .eusoRefreshHandler { await reload() }
        .sheet(isPresented: $showReachNext) { reachNextSheet }
        .sheet(isPresented: $showAllBenefits) { allBenefitsSheet }
    }

    // MARK: TopBar (inlined — eyebrow / period / back / title)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EusoTripEyebrow(verbatim: "CATALYST · NETWORK TIER")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(currentQuarterLabel_397())
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Back")
                Text("Carrier tier")
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: Hero — tier + progress ring

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CURRENT TIER · EUSOTRIP NETWORK")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    HStack(spacing: 10) {
                        medal(size: 28)
                        Text(vm.currentTier)
                            .font(.system(size: 30, weight: .bold)).tracking(-0.4)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    (Text(vm.points).fontWeight(.bold).foregroundColor(palette.textPrimary)
                        + Text(" composite · \(vm.rankLine)"))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                    Text(vm.boostLabel)
                        .font(.system(size: 11, weight: .heavy)).tracking(0.2).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(LinearGradient.primary))
                }
                Spacer()
                VStack(spacing: 4) {
                    progressRing
                    Text(vm.ptsToGo)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 150)
    }

    private var progressRing: some View {
        ZStack {
            Circle().stroke(palette.textTertiary.opacity(0.20), lineWidth: 8)
            Circle().trim(from: 0, to: CGFloat(vm.progressPct) / 100)
                .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(vm.progressPct)%")
                    .font(.system(size: 19, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Text(vm.nextTier.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(width: 68, height: 68)
        .accessibilityLabel("\(vm.progressPct)% to \(vm.nextTier)")
    }

    private func medal(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(gold)
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(width: size, height: size)
    }

    // MARK: Tier ladder

    private var ladderSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("TIER LADDER · QUALIFICATION")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                if vm.rungs.isEmpty {
                    EusoEmptyState(
                        systemImage: "chart.bar.doc.horizontal",
                        title: loading ? "Computing tier…" : "Tier not yet computed",
                        subtitle: loading ? "" : (loadError ?? "Your network tier appears here once your company record and load history are on file.")
                    )
                    .padding(.vertical, Space.s2)
                } else {
                    ForEach(Array(vm.rungs.enumerated()), id: \.element.id) { idx, rung in
                        if rung.state == .current {
                            currentRung(rung)
                        } else {
                            rungRow(rung)
                            if idx < vm.rungs.count - 1, vm.rungs[idx + 1].state != .current {
                                Rectangle().fill(palette.borderFaint)
                                    .frame(height: 1)
                                    .padding(.leading, 42)
                            }
                        }
                    }
                }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func rungRow(_ r: TierRung_397) -> some View {
        HStack(spacing: Space.s3) {
            rungBadge(r)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.name).font(EType.bodyStrong)
                    .foregroundStyle(r.state == .locked ? palette.textTertiary : palette.textPrimary)
                Text(r.threshold).font(EType.mono(.caption))
                    .foregroundStyle(r.state == .locked ? palette.textTertiary : palette.textSecondary)
            }
            Spacer()
            trailingTag(r)
        }
        .padding(.vertical, Space.s2)
    }

    private func currentRung(_ r: TierRung_397) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.md - 1.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)
            HStack(spacing: Space.s3) {
                medal(size: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(r.threshold).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Text("CURRENT")
                    .font(EType.micro).tracking(0.4).fontWeight(.heavy)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        }
        .frame(height: 54)
        .padding(.vertical, Space.s1)
    }

    @ViewBuilder
    private func rungBadge(_ r: TierRung_397) -> some View {
        switch r.state {
        case .achieved:
            ZStack {
                Circle().fill(Brand.success.opacity(0.18))
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.success)
            }.frame(width: 26, height: 26)
        case .next:
            ZStack {
                Circle().fill(Brand.neutral.opacity(0.18))
                Image(systemName: "diamond")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.neutral)
            }.frame(width: 26, height: 26)
        default:
            ZStack {
                Circle().fill(palette.textTertiary.opacity(0.10))
                Image(systemName: "diamond")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }.frame(width: 26, height: 26)
        }
    }

    @ViewBuilder
    private func trailingTag(_ r: TierRung_397) -> some View {
        switch r.state {
        case .achieved:
            Text("ACHIEVED")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Brand.success)
        case .next:
            Text(r.trailing)
                .font(.system(size: 10, weight: .heavy)).monospacedDigit().tracking(0.3)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Brand.warning.opacity(0.16)))
        default:
            Text("LOCKED")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Benefits

    @ViewBuilder
    private var benefitsSection: some View {
        if !vm.benefits.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
            Text("YOUR \(vm.currentTier.uppercased()) BENEFITS")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(vm.benefits) { b in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(b.label)
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(b.value)
                            .font(.system(size: 15, weight: .bold)).monospacedDigit()
                            .foregroundStyle(b.highlight
                                ? AnyShapeStyle(LinearGradient.diagonal)
                                : AnyShapeStyle(palette.textPrimary))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s3)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
            }
            }
        }
    }

    // MARK: CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                showReachNext = true
            } label: {
                Text(vm.nextTier == "—" ? "How tiers work" : "Reach \(vm.nextTier)")
                    .font(EType.bodyStrong).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(vm.nextTier == "—" ? "How tiers work" : "How to reach \(vm.nextTier)")

            Button {
                showAllBenefits = true
            } label: {
                Text("All benefits")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all tier benefits")
        }
    }

    private var reachNextSheet: some View {
        NavigationStack {
            tierSheetScaffold(title: vm.nextTier == "—" ? "How Tiers Work" : "Reach \(vm.nextTier)") {
                VStack(alignment: .leading, spacing: Space.s3) {
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CURRENT")
                                .font(EType.micro).tracking(0.8)
                                .foregroundStyle(palette.textTertiary)
                            Text("\(vm.currentTier) · \(vm.points) composite")
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                            Text(vm.boostLabel)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    if let next = vm.rungs.first(where: { $0.state == .next }) {
                        LifecycleCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("NEXT RUNG")
                                    .font(EType.micro).tracking(0.8)
                                    .foregroundStyle(palette.textTertiary)
                                Text(next.name)
                                    .font(EType.bodyStrong)
                                    .foregroundStyle(palette.textPrimary)
                                Text(next.threshold)
                                    .font(EType.mono(.caption))
                                    .foregroundStyle(palette.textSecondary)
                                Text(vm.ptsToGo)
                                    .font(EType.caption)
                                    .foregroundStyle(Brand.warning)
                            }
                        }
                    }
                    if !vm.nextUnlockNote.isEmpty {
                        LifecycleCard {
                            Text(vm.nextUnlockNote)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var allBenefitsSheet: some View {
        NavigationStack {
            tierSheetScaffold(title: "\(vm.currentTier) Benefits") {
                VStack(alignment: .leading, spacing: Space.s2) {
                    if vm.benefits.isEmpty {
                        EusoEmptyState(
                            systemImage: "star.circle",
                            title: "No benefit rows available",
                            subtitle: loadError ?? "Benefits appear after your tier is computed."
                        )
                    } else {
                        ForEach(vm.benefits) { benefit in
                            LifecycleCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(benefit.label)
                                            .font(EType.micro).tracking(0.8)
                                            .foregroundStyle(palette.textTertiary)
                                        Text(benefit.value)
                                            .font(EType.bodyStrong)
                                            .foregroundStyle(benefit.highlight ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textPrimary))
                                    }
                                    Spacer()
                                    if benefit.highlight {
                                        Image(systemName: "star.fill").foregroundStyle(LinearGradient.diagonal)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func tierSheetScaffold<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(title)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                content()
            }
            .padding(18)
        }
        .background(palette.bgPrimary.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    showReachNext = false
                    showAllBenefits = false
                }
            }
        }
    }

    // MARK: - Network hydrate (LIVE — carrierTier.* bridges)

    private struct TierDefWire_397: Decodable {
        let id: String
        let name: String
        let minScore: Double
        let maxScore: Double
        let benefits: [String]
        let platformFeeDiscount: Double
        let priorityMatchBoost: Double
        let analyticsAccess: String?
        let loadAccessTier: String?
    }
    private struct PromotionWire_397: Decodable {
        let nextTier: String?
        let pointsNeeded: Double
        let suggestions: [String]
    }
    private struct TierResultWire_397: Decodable {
        let carrierId: Int
        let tier: String
        let tierDefinition: TierDefWire_397
        let compositeScore: Double
        let promotionPath: PromotionWire_397?
        let flags: [String]?
        let companyName: String?
        let dotNumber: String?
    }
    private struct BoostWire_397: Decodable {
        let tier: String
        let boost: Double
        let feeDiscount: Double
    }
    private struct CarrierIdInput_397: Encodable { let carrierId: Int }
    private struct TierInput_397: Encodable { let tier: String }

    private func reload() async {
        loading = true
        loadError = nil
        defer { loading = false }

        guard let cidString = session.user?.companyId, let cid = Int(cidString) else {
            vm = .empty
            loadError = "No company on this account - tiering needs a registered carrier company."
            return
        }

        do {
            async let resultTask: TierResultWire_397? = EusoTripAPI.shared.query(
                "carrierTier.getCarrierTier", input: CarrierIdInput_397(carrierId: cid))
            async let defsTask: [TierDefWire_397] = EusoTripAPI.shared.queryNoInput(
                "carrierTier.getTierDefinitions")

            let (result, defs) = try await (resultTask, defsTask)
            guard let result else {
                vm = .empty
                loadError = "Tier not computable yet - no company record found."
                return
            }

            let boost: BoostWire_397? = try? await EusoTripAPI.shared.query(
                "carrierTier.getDispatchBoost", input: TierInput_397(tier: result.tier))

            vm = buildVM_397(result: result, defs: defs, boost: boost)
        } catch {
            vm = .empty
            loadError = "Couldn't reach the tier service - retry."
        }
    }

    private func buildVM_397(result: TierResultWire_397,
                             defs: [TierDefWire_397],
                             boost: BoostWire_397?) -> CarrierTierVM_397 {
        // Server returns definitions sorted by minScore DESC already; keep order.
        let sorted = defs.sorted { $0.minScore > $1.minScore }
        let currentIdx = sorted.firstIndex { $0.id == result.tier }
        let nextDef = currentIdx.flatMap { $0 > 0 ? sorted[$0 - 1] : nil }

        let rungs: [TierRung_397] = sorted.enumerated().map { idx, def in
            let state: TierRungState_397
            let trailing: String
            if def.id == result.tier {
                state = .current; trailing = "CURRENT"
            } else if let ci = currentIdx, idx == ci - 1 {
                state = .next
                let pts = result.promotionPath.map { Int($0.pointsNeeded.rounded()) }
                trailing = pts.map { "+\($0) PTS" } ?? "NEXT"
            } else if let ci = currentIdx, idx > ci {
                state = .achieved; trailing = "ACHIEVED"
            } else {
                state = .locked; trailing = "LOCKED"
            }
            return TierRung_397(
                id: def.id,
                name: def.name,
                threshold: "\(Int(def.minScore))–\(Int(def.maxScore)) composite",
                state: state,
                trailing: trailing
            )
        }

        // Progress within the current band toward the next tier's floor.
        var progress = 0
        if let cur = currentIdx.map({ sorted[$0] }), let next = nextDef {
            let span = next.minScore - cur.minScore
            if span > 0 {
                progress = Int(((result.compositeScore - cur.minScore) / span * 100)
                    .rounded())
                progress = min(100, max(0, progress))
            }
        } else if currentIdx != nil {
            progress = 100   // already top tier
        }

        let def = result.tierDefinition
        let benefits: [TierBenefit_397] = [
            TierBenefit_397(label: "FEE DISCOUNT",
                            value: def.platformFeeDiscount > 0 ? "\(Int(def.platformFeeDiscount))%" : "0%",
                            highlight: def.platformFeeDiscount > 0),
            TierBenefit_397(label: "MATCH BOOST",
                            value: "+\(Int(boost?.boost ?? def.priorityMatchBoost))",
                            highlight: false),
            TierBenefit_397(label: "ANALYTICS",
                            value: (def.analyticsAccess ?? "—").capitalized,
                            highlight: false),
        ]

        let nextUnlock: String
        if let next = nextDef {
            let fee = next.platformFeeDiscount
            nextUnlock = "\(next.name) unlocks \(Int(fee))% fee discount · +\(Int(next.priorityMatchBoost)) dispatch boost"
        } else {
            nextUnlock = result.promotionPath?.suggestions.first ?? ""
        }

        return CarrierTierVM_397(
            currentTier: def.name,
            points: "\(Int(result.compositeScore.rounded()))",
            rankLine: result.companyName ?? result.dotNumber.map { "DOT \($0)" } ?? "—",
            boostLabel: "+\(Int(boost?.boost ?? def.priorityMatchBoost)) DISPATCH BOOST",
            progressPct: progress,
            nextTier: nextDef?.name ?? "—",
            ptsToGo: result.promotionPath.map { "\(Int($0.pointsNeeded.rounded())) pts to go" } ?? "top tier",
            rungs: rungs,
            benefits: benefits,
            nextUnlockNote: nextUnlock
        )
    }
}

// MARK: - Quarter label (derived from the real clock, not a hardcoded string)

private func currentQuarterLabel_397() -> String {
    let now = Date()
    let cal = Calendar.current
    let q = (cal.component(.month, from: now) - 1) / 3 + 1
    return "Q\(q) \(cal.component(.year, from: now))"
}

// MARK: - Honest empty envelope (every figure em-dash until a real hydrate)

private extension CarrierTierVM_397 {
    static let empty = CarrierTierVM_397(
        currentTier: "—", points: "—", rankLine: "—",
        boostLabel: "—", progressPct: 0, nextTier: "—",
        ptsToGo: "—",
        rungs: [],
        benefits: [],
        nextUnlockNote: ""
    )
}

// MARK: - Previews

#Preview("397 · Catalyst · Carrier Tier · Night") {
    CatalystCarrierTierScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("397 · Catalyst · Carrier Tier · Afternoon") {
    CatalystCarrierTierScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
