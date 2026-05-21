//
//  PremiumTierView.swift
//  AI Ultra SaaS upsell tier — IO 2026 P0-12.
//
//  Two roles in one view:
//    1. Paywall — shown to FREE / PRO / ENTERPRISE users. Lists
//       the Ultra-only features (Gemini fee-breakdown explainer,
//       deep market intel, compliance watchdog, priority support)
//       with an Upgrade CTA.
//    2. Fee Insights card — shown to ULTRA users. Pulls
//       `eusoWalletPremium.explainFeeBreakdown` with the canonical
//       FeeBreakdown (from FeeMultiplierEngine), surfaces the
//       Gemini-generated per-multiplier explanation.
//
//  Cost guardrail: this UI never calls Gemini when the user is
//  not Ultra — the server short-circuits non-Ultra requests with
//  `paywall: true` before any Gemini quota is consumed.
//
//  Drop into: EusoTrip/Views/Wallet/PremiumTierView.swift
//

import SwiftUI

public struct PremiumTierView: View {
    /// Optional FeeBreakdown — when non-nil and the user is Ultra,
    /// the view renders the Gemini explanation card. When nil, the
    /// Ultra view shows a "Pull from a load to see your breakdown"
    /// placeholder.
    let breakdown: FeeBreakdown?
    let vertical: Vertical?
    let trailer: TrailerCode?

    @State private var tier: String = "FREE"
    @State private var isUltra: Bool = false
    @State private var features: TierFeatures = TierFeatures()
    @State private var isLoadingTier: Bool = false

    @State private var explanations: FeeExplanationBundle? = nil
    @State private var explainError: String? = nil
    @State private var isExplaining: Bool = false

    @State private var upgradeInFlight: Bool = false
    @State private var upgradeError: String? = nil

    public init(
        breakdown: FeeBreakdown? = nil,
        vertical: Vertical? = nil,
        trailer: TrailerCode? = nil
    ) {
        self.breakdown = breakdown
        self.vertical = vertical
        self.trailer = trailer
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if isLoadingTier {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading tier…").foregroundStyle(.secondary)
                    }
                } else if isUltra {
                    ultraBlock
                } else {
                    paywallBlock
                }
            }
            .padding(16)
        }
        .navigationTitle("EusoWallet · AI Ultra")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshTier() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Text("AI ULTRA")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                tierBadge
            }
            Text(isUltra ? "Your AI Ultra benefits" : "Unlock Gemini-powered insights")
                .font(.title3.bold())
        }
    }

    private var tierBadge: some View {
        let colors: [Color] = isUltra ? [.yellow, .orange] : [.gray, .gray]
        return Text(tier.uppercased())
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), in: Capsule())
    }

    // MARK: - Paywall

    private var paywallBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow(icon: "sparkles", title: "Gemini fee-breakdown explainer",
                       body: "Per-multiplier reasoning on every load's effective rate. See exactly why your base × country × vertical × hazmat lands where it does.")
            featureRow(icon: "chart.line.uptrend.xyaxis", title: "Deep market intel",
                       body: "Lane-level rate forecasts + cycle dampener context for every quote.")
            featureRow(icon: "shield.checkered", title: "Compliance watchdog",
                       body: "Multi-trailer segregation checks, USMCA cert auto-draft, ERG follow-ups across your active book.")
            featureRow(icon: "phone.bubble.fill", title: "Priority human support",
                       body: "Direct line to the ESang ops desk for routing, customs, and HOS escalations.")

            if let err = upgradeError {
                Text(err).font(.callout).foregroundStyle(.red)
            }

            Button {
                Task { await upgrade() }
            } label: {
                HStack {
                    if upgradeInFlight {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "crown.fill")
                    }
                    Text("Upgrade to AI Ultra").font(.body.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient(
                    colors: [.yellow, .orange],
                    startPoint: .leading, endPoint: .trailing
                ))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(upgradeInFlight)

            Text("Billing through EusoWallet · cancel anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func featureRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(LinearGradient(
                    colors: [.yellow, .orange],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.bold())
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Ultra (in-tier)

    private var ultraBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            unlockedStrip
            if let breakdown {
                feeExplainerCard(breakdown: breakdown)
            } else {
                emptyFeeBreakdown
            }
        }
    }

    private var unlockedStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text("AI Ultra unlocked.")
                .font(.callout.bold())
            Spacer(minLength: 0)
            Button("Manage") { Task { await downgrade() } }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyFeeBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Fee insights").font(.callout.bold())
            }
            Text("Open a load detail to see the per-multiplier Gemini explanation here.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func feeExplainerCard(breakdown: FeeBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(LinearGradient(
                    colors: [.cyan, .green],
                    startPoint: .leading, endPoint: .trailing
                ))
                Text("Fee insights").font(.callout.bold())
                Spacer(minLength: 0)
                if isExplaining {
                    ProgressView().controlSize(.small)
                }
            }
            if let headline = explanations?.headline {
                Text(headline)
                    .font(.body.weight(.semibold))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(
                        colors: [.cyan.opacity(0.12), .green.opacity(0.08)],
                        startPoint: .leading, endPoint: .trailing
                    ), in: RoundedRectangle(cornerRadius: 10))
            }
            if let err = explainError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            ForEach(explanationRows(), id: \.label) { row in
                multiplierRow(row)
            }
            HStack(spacing: 8) {
                Button {
                    Task { await loadExplanation(breakdown) }
                } label: {
                    Label("Refresh insights", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.tint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isExplaining)
            }
        }
        .padding(14)
        .background(.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .task(id: breakdown) {
            await loadExplanation(breakdown)
        }
    }

    @ViewBuilder
    private func multiplierRow(_ row: MultiplierRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(row.value)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .frame(width: 56, alignment: .leading)
                .foregroundStyle(row.numericValue > 1.0001 ? Color.orange
                              : row.numericValue < 0.9999 ? Color.green
                              : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(row.explanation)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private struct MultiplierRow {
        let label: String
        let value: String
        let numericValue: Double
        let explanation: String
    }

    private func explanationRows() -> [MultiplierRow] {
        guard let breakdown, let e = explanations else { return [] }
        func decFmt(_ d: Decimal) -> String {
            "\((d as NSDecimalNumber).doubleValue)x"
        }
        func decNum(_ d: Decimal) -> Double { (d as NSDecimalNumber).doubleValue }
        return [
            MultiplierRow(label: "BASE",           value: decFmt(breakdown.base),          numericValue: decNum(breakdown.base),          explanation: e.base ?? "—"),
            MultiplierRow(label: "COUNTRY",        value: decFmt(breakdown.country),       numericValue: decNum(breakdown.country),       explanation: e.country ?? "—"),
            MultiplierRow(label: "VERTICAL",       value: decFmt(breakdown.vertical),      numericValue: decNum(breakdown.vertical),      explanation: e.vertical ?? "—"),
            MultiplierRow(label: "PRODUCT",        value: decFmt(breakdown.product),       numericValue: decNum(breakdown.product),       explanation: e.product ?? "—"),
            MultiplierRow(label: "HAZMAT",         value: decFmt(breakdown.hazmat),        numericValue: decNum(breakdown.hazmat),        explanation: e.hazmat ?? "—"),
            MultiplierRow(label: "DISTANCE",       value: decFmt(breakdown.distance),      numericValue: decNum(breakdown.distance),      explanation: e.distance ?? "—"),
            MultiplierRow(label: "CYCLE DAMPENER", value: decFmt(breakdown.cycleDampener), numericValue: decNum(breakdown.cycleDampener), explanation: e.cycleDampener ?? "—"),
        ]
    }

    // MARK: - Network

    @MainActor
    private func refreshTier() async {
        isLoadingTier = true
        defer { isLoadingTier = false }
        struct Out: Decodable {
            let tier: String
            let isUltra: Bool
            let features: TierFeatures
        }
        do {
            let reply: Out = try await EusoTripAPI.shared.query(
                "eusoWalletPremium.getMyTier", input: EmptyInput()
            )
            tier = reply.tier
            isUltra = reply.isUltra
            features = reply.features
        } catch {
            // Quiet fail — default FREE tier; paywall renders.
        }
    }

    @MainActor
    private func upgrade() async {
        upgradeInFlight = true
        upgradeError = nil
        defer { upgradeInFlight = false }
        // In production this is wired into Stripe Checkout. For the
        // P0-12 ship this calls the server-side `setMyTier` which the
        // founder + QA + Stripe webhook all share.
        struct In: Encodable { let tier: String }
        struct Out: Decodable { let success: Bool; let tier: String }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "eusoWalletPremium.setMyTier",
                input: In(tier: "ULTRA")
            )
            await refreshTier()
        } catch {
            upgradeError = "Couldn't upgrade: \((error as NSError).localizedDescription)"
        }
    }

    @MainActor
    private func downgrade() async {
        struct In: Encodable { let tier: String }
        struct Out: Decodable { let success: Bool; let tier: String }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "eusoWalletPremium.setMyTier",
                input: In(tier: "FREE")
            )
            await refreshTier()
        } catch { /* quiet */ }
    }

    @MainActor
    private func loadExplanation(_ breakdown: FeeBreakdown) async {
        isExplaining = true
        explainError = nil
        defer { isExplaining = false }
        struct BreakdownWire: Encodable {
            let base: String
            let country: String
            let vertical: String
            let product: String
            let hazmat: String
            let distance: String
            let cycleDampener: String
            let effective: String
        }
        struct In: Encodable {
            let breakdown: BreakdownWire
            let vertical: String?
            let trailer: String?
        }
        struct Out: Decodable {
            let paywall: Bool
            let tier: String
            let modelUsed: String?
            let explanations: FeeExplanationBundle?
            let message: String?
        }
        let payload = In(
            breakdown: BreakdownWire(
                base:          (breakdown.base as NSDecimalNumber).stringValue,
                country:       (breakdown.country as NSDecimalNumber).stringValue,
                vertical:      (breakdown.vertical as NSDecimalNumber).stringValue,
                product:       (breakdown.product as NSDecimalNumber).stringValue,
                hazmat:        (breakdown.hazmat as NSDecimalNumber).stringValue,
                distance:      (breakdown.distance as NSDecimalNumber).stringValue,
                cycleDampener: (breakdown.cycleDampener as NSDecimalNumber).stringValue,
                effective:     (breakdown.effective as NSDecimalNumber).stringValue
            ),
            vertical: vertical?.rawValue,
            trailer:  trailer?.rawValue
        )
        do {
            let reply: Out = try await EusoTripAPI.shared.mutation(
                "eusoWalletPremium.explainFeeBreakdown",
                input: payload
            )
            if reply.paywall {
                explainError = reply.message ?? "Upgrade to AI Ultra to unlock."
                await refreshTier()   // sync local state
            } else {
                explanations = reply.explanations
            }
        } catch {
            explainError = "Couldn't reach Gemini: \((error as NSError).localizedDescription)"
        }
    }
}

// MARK: - Wire types

public struct TierFeatures: Codable, Hashable, Sendable {
    public var feeBreakdownExplainer: Bool = false
    public var prioritySupport: Bool = false
    public var marketIntelDeepDive: Bool = false
    public var complianceWatchdog: Bool = false
}

public struct FeeExplanationBundle: Codable, Hashable, Sendable {
    public let headline: String?
    public let base: String?
    public let country: String?
    public let vertical: String?
    public let product: String?
    public let hazmat: String?
    public let distance: String?
    public let cycleDampener: String?
}

private struct EmptyInput: Encodable, Sendable {}

// MARK: - Previews

#Preview("Premium Tier · Paywall · Dark") {
    NavigationStack { PremiumTierView() }
        .preferredColorScheme(.dark)
}

#Preview("Premium Tier · Paywall · Light") {
    NavigationStack { PremiumTierView() }
        .preferredColorScheme(.light)
}
