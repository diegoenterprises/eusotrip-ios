//
//  652_RailClaimsDashboard.swift
//  EusoTrip
//
//  Purpose: show the complete tenant-visible rail claim register without
//  combining currencies or turning unknown status and amount into zero.
//  Archetype: operational claims ledger.
//

import SwiftUI

struct RailClaimsDashboardScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            RailClaimsDashboardBody()
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                    NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)
                ],
                trailing: [
                    NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                    NavSlot(label: "Me", systemImage: "person", isCurrent: false)
                ],
                orbState: .idle
            )
        }
    }
}

private struct RailClaimCurrencyExposure: Identifiable {
    let currency: String
    let amount: Double
    var id: String { currency }
}

private struct RailClaimTypeCount: Identifiable {
    let type: String
    let count: Int
    var id: String { type }
}

private struct RailClaimsDashboardBody: View {
    @Environment(\.palette) private var palette
    @State private var claims: [FreightClaimsAPI.Claim] = []
    @State private var loading = true
    @State private var loadError: String?

    private let terminalStatuses: Set<String> = ["settled", "paid", "closed", "denied"]
    private let reviewStatuses: Set<String> = ["under_review", "investigating", "pending_evidence", "appealed", "arbitration"]

    private var activeCount: Int {
        claims.filter { claim in
            guard let status = FreightClaimConsumerCanon.clean(claim.status)?.lowercased() else { return false }
            return !terminalStatuses.contains(status)
        }.count
    }

    private var reviewCount: Int {
        claims.filter { claim in
            guard let status = FreightClaimConsumerCanon.clean(claim.status)?.lowercased() else { return false }
            return reviewStatuses.contains(status)
        }.count
    }

    private var unknownStatusCount: Int {
        claims.filter { FreightClaimConsumerCanon.clean($0.status) == nil }.count
    }

    private var incompleteFinancialCount: Int {
        claims.filter { $0.amount == nil || $0.currency == nil }.count
    }

    private var exposureByCurrency: [RailClaimCurrencyExposure] {
        var totals: [String: Double] = [:]
        for claim in claims {
            guard let amount = claim.amount, let currency = claim.currency else { continue }
            totals[currency.rawValue, default: 0] += amount
        }
        return totals
            .map { RailClaimCurrencyExposure(currency: $0.key, amount: $0.value) }
            .sorted { $0.currency < $1.currency }
    }

    private var typeCounts: [RailClaimTypeCount] {
        var counts: [String: Int] = [:]
        for claim in claims {
            let label = FreightClaimConsumerCanon.label(claim.type) ?? "Type unavailable"
            counts[label, default: 0] += 1
        }
        return counts
            .map { RailClaimTypeCount(type: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.type < rhs.type : lhs.count > rhs.count
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            FreightClaimSurfaceHeader(
                context: "Rail claims",
                title: "Claims ledger",
                purpose: "Review every rail claim visible to this account, separated by lifecycle state, claim type, and original currency."
            )

            if loading && claims.isEmpty {
                ProgressView("Loading rail claims")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let loadError {
                LifecycleCard(accentDanger: true) {
                    Text(loadError)
                        .font(.body)
                        .foregroundStyle(Brand.danger)
                }
            } else if claims.isEmpty {
                EusoEmptyState(
                    systemImage: "rectangle.stack.badge.minus",
                    title: "No rail claims",
                    subtitle: "No claim tied to a rail shipment is available to this account."
                )
            } else {
                lifecycleSummary
                exposureRegister
                typeRegister
                recentRegister
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var lifecycleSummary: some View {
        LifecycleCard {
            VStack(spacing: 0) {
                FreightClaimValueRow(label: "Rail claims", value: claims.count.formatted())
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Active", value: activeCount.formatted())
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "In review", value: reviewCount.formatted())
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Status unavailable", value: unknownStatusCount.formatted())
            }
        }
    }

    private var exposureRegister: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Exposure by currency")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.bottom, Space.s2)
                if exposureByCurrency.isEmpty {
                    Text("No claim has complete amount and currency context.")
                        .font(.body)
                        .foregroundStyle(palette.textSecondary)
                        .frame(minHeight: 44)
                } else {
                    ForEach(Array(exposureByCurrency.enumerated()), id: \.element.id) { index, exposure in
                        if index > 0 { Divider().opacity(0.25) }
                        FreightClaimValueRow(
                            label: exposure.currency,
                            value: exposure.amount.formatted(.number.precision(.fractionLength(2)))
                        )
                    }
                }
                if incompleteFinancialCount > 0 {
                    Divider().opacity(0.25)
                    FreightClaimValueRow(
                        label: "Financial context incomplete",
                        value: incompleteFinancialCount.formatted()
                    )
                }
            }
        }
    }

    private var typeRegister: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Claims by type")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            ForEach(typeCounts) { item in
                LifecycleCard {
                    FreightClaimValueRow(label: item.type, value: item.count.formatted())
                }
            }
        }
    }

    private var recentRegister: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Recent rail claims")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            ForEach(claims.prefix(5)) { claim in
                LifecycleCard {
                    VStack(spacing: 0) {
                        FreightClaimValueRow(label: "Claim", value: claim.claimNumber)
                        Divider().opacity(0.25)
                        FreightClaimValueRow(
                            label: "Rail shipment",
                            value: FreightClaimConsumerCanon.reference(for: claim, mode: .rail)
                        )
                        Divider().opacity(0.25)
                        FreightClaimValueRow(label: "Status", value: FreightClaimConsumerCanon.label(claim.status))
                    }
                }
            }
        }
    }

    @MainActor
    private func load() async {
        loading = claims.isEmpty
        loadError = nil
        do {
            claims = try await FreightClaimConsumerCanon.claims(mode: .rail)
        } catch {
            loadError = FreightClaimConsumerCanon.errorMessage(error)
        }
        loading = false
    }
}

#Preview("Rail claims dashboard") {
    RailClaimsDashboardScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
