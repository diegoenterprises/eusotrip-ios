//
//  653_RailClaimsList.swift
//  EusoTrip
//
//  Purpose: scan the tenant-visible rail claim queue while retaining each
//  claim's shipment anchor, status, filed date, amount, and currency.
//  Archetype: claim queue.
//

import SwiftUI

struct RailClaimsListScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            RailClaimsListBody()
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

private struct RailClaimsListBody: View {
    @Environment(\.palette) private var palette
    @State private var claims: [FreightClaimsAPI.Claim] = []
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            FreightClaimSurfaceHeader(
                context: "Rail claims",
                title: "Claim queue",
                purpose: "Scan rail claims by their real shipment reference and financial context without merging unknown states into the working queue."
            )

            if loading && claims.isEmpty {
                ProgressView("Loading claim queue")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let loadError {
                LifecycleCard(accentDanger: true) {
                    Text(loadError)
                        .font(.body)
                        .foregroundStyle(Brand.danger)
                }
            } else if claims.isEmpty {
                EusoEmptyState(
                    systemImage: "list.bullet.rectangle",
                    title: "No rail claims",
                    subtitle: "No claim tied to a rail shipment is available to this account."
                )
            } else {
                Text("\(claims.count) claim records")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                ForEach(claims) { claim in
                    claimRow(claim)
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private func claimRow(_ claim: FreightClaimsAPI.Claim) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text(claim.claimNumber)
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(FreightClaimConsumerCanon.label(claim.status) ?? "Status unavailable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(claim.status == nil ? palette.textTertiary : Brand.info)
                }
                .frame(minHeight: 44)
                Divider().opacity(0.25)
                FreightClaimValueRow(
                    label: "Rail shipment",
                    value: FreightClaimConsumerCanon.reference(for: claim, mode: .rail)
                )
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Type", value: FreightClaimConsumerCanon.label(claim.type))
                Divider().opacity(0.25)
                FreightClaimValueRow(
                    label: "Claimed exposure",
                    value: FreightClaimConsumerCanon.financialContext(amount: claim.amount, currency: claim.currency)
                )
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Filed", value: FreightClaimConsumerCanon.clean(claim.filedDate))
            }
        }
        .accessibilityElement(children: .contain)
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

#Preview("Rail claims list") {
    RailClaimsListScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
