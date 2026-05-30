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
//  WIRING STATUS: the `carrierTier` tRPC router has no Swift client on
//  EusoTripAPI yet (grep confirms only a `carrierTier: String?` field on
//  RFP bid/scorecard structs — not this surface). Per house doctrine the
//  representative seed figures are kept verbatim (0% mock — seeds
//  overwritten on hydrate) and one `// WIRE:` marker is left per missing
//  procedure. When the client lands, reload() fans the five calls in and
//  hydrates over the seeds via @State.
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
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}

private func catalystNavTrailing_397() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: true)]
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

    // Representative seed mirrors the SVG verbatim. Overwritten on hydrate
    // once the carrierTier Swift client lands (see WIRE markers in reload()).
    @State private var vm: CarrierTierVM_397 = .seed
    @State private var loading: Bool = false
    @State private var loadError: String? = nil

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
                Text(vm.nextUnlockNote)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s7)
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await reload() }
        }
    }

    // MARK: TopBar (inlined — eyebrow / period / back / title)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ CATALYST · NETWORK TIER")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("Q2 2026")
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
                    Text("CURRENT TIER · AURORA NETWORK")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    HStack(spacing: 10) {
                        medal(size: 28)
                        Text(vm.currentTier)
                            .font(.system(size: 30, weight: .bold)).tracking(-0.4)
                            .foregroundStyle(palette.textPrimary)
                    }
                    (Text(vm.points).fontWeight(.bold).foregroundColor(palette.textPrimary)
                        + Text(" network points · \(vm.rankLine)"))
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

    private var benefitsSection: some View {
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

    // MARK: CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                NotificationCenter.default.post(
                    name: .eusoCatalystTierReachNext_397, object: nil,
                    userInfo: ["source": "397_CatalystCarrierTier", "target": vm.nextTier])
            } label: {
                Text("Reach \(vm.nextTier)")
                    .font(EType.bodyStrong).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("How to reach \(vm.nextTier)")

            Button {
                NotificationCenter.default.post(
                    name: .eusoCatalystTierAllBenefits_397, object: nil,
                    userInfo: ["source": "397_CatalystCarrierTier"])
            } label: {
                Text("All benefits")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all tier benefits")
        }
    }

    // MARK: - Network hydrate

    private func reload() async {
        loading = true
        loadError = nil
        // The carrierTier tRPC router has no Swift client on EusoTripAPI yet
        // (grep: only a `carrierTier: String?` field on RFP bid/scorecard
        // structs exists, not this surface). When the client lands, fan the
        // five calls in and hydrate `vm` over the seeds. Until then the
        // representative seed (mirrors the SVG verbatim) stands.
        //
        // WIRE: carrierTier.getCarrierTier      (carrierTier.ts:27)   → hero tier + points + ring
        // WIRE: carrierTier.getDispatchBoost    (carrierTier.ts:219)  → boost multiplier
        // WIRE: carrierTier.getTierDefinitions  (carrierTier.ts:135)  → ladder rungs + thresholds
        // WIRE: carrierTier.getTierBenefits     (carrierTier.ts:141)  → active-tier benefit tiles
        // WIRE: carrierTier.getTierDistribution (carrierTier.ts:390)  → peer rank context
        loading = false
    }
}

// MARK: - Notifications (CTA routing)

extension Notification.Name {
    static let eusoCatalystTierReachNext_397   = Notification.Name("eusoCatalystTierReachNext_397")
    static let eusoCatalystTierAllBenefits_397 = Notification.Name("eusoCatalystTierAllBenefits_397")
}

// MARK: - Seed fixture (mirrors the SVG verbatim — 0% mock, overwritten on hydrate)

private extension CarrierTierVM_397 {
    static let seed = CarrierTierVM_397(
        currentTier: "Gold", points: "1,840", rankLine: "rank 38 of 412",
        boostLabel: "1.18× DISPATCH BOOST", progressPct: 72, nextTier: "Platinum",
        ptsToGo: "160 pts to go",
        rungs: [
            TierRung_397(id: "diamond",  name: "Diamond",  threshold: "3,000 pts · OTR ≥ 99% · CSA clean",      state: .locked,   trailing: "LOCKED"),
            TierRung_397(id: "platinum", name: "Platinum", threshold: "2,000 pts · OTR ≥ 97% · 1.32× boost",    state: .next,     trailing: "+160 PTS"),
            TierRung_397(id: "gold",     name: "Gold",     threshold: "1,500 pts · OTR ≥ 95% · 1.18× boost",    state: .current,  trailing: "CURRENT"),
            TierRung_397(id: "silver",   name: "Silver",   threshold: "800 pts · OTR ≥ 92% · cleared Mar 2026", state: .achieved, trailing: "ACHIEVED"),
            TierRung_397(id: "bronze",   name: "Bronze",   threshold: "entry · onboarded Nov 2025",             state: .achieved, trailing: "ACHIEVED"),
        ],
        benefits: [
            TierBenefit_397(label: "QUICK-PAY",    value: "Net-5",    highlight: false),
            TierBenefit_397(label: "PLATFORM FEE", value: "4.2%",     highlight: true),
            TierBenefit_397(label: "TENDER",       value: "Priority", highlight: false),
        ],
        nextUnlockNote: "Platinum unlocks net-3 pay · 3.6% fee · 1.32× boost"
    )
}

// MARK: - Previews

#Preview("397 · Catalyst · Carrier Tier · Night") {
    CatalystCarrierTierScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("397 · Catalyst · Carrier Tier · Afternoon") {
    CatalystCarrierTierScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
