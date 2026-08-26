//
//  801_VesselClaimsList.swift
//  EusoTrip
//
//  Purpose: let vessel operators scan claims by real booking reference,
//  maritime peril, lifecycle state, filing date, amount, and currency.
//  Archetype: booking claim register.
//

import SwiftUI

struct VesselClaimsListScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            VesselClaimsListBody()
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

private struct VesselClaimsListBody: View {
    @Environment(\.palette) private var palette
    @State private var claims: [FreightClaimsAPI.Claim] = []
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            FreightClaimSurfaceHeader(
                context: "Vessel claims",
                title: "Booking register",
                purpose: "Scan each maritime claim in the context of the single vessel booking that anchors it."
            )

            if loading && claims.isEmpty {
                ProgressView("Loading booking claims")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let loadError {
                LifecycleCard(accentDanger: true) {
                    Text(loadError).font(.body).foregroundStyle(Brand.danger)
                }
            } else if claims.isEmpty {
                EusoEmptyState(
                    systemImage: "list.bullet.rectangle.portrait",
                    title: "No vessel claims",
                    subtitle: "No claim tied to a vessel booking is available to this account."
                )
            } else {
                Text("\(claims.count) claim record\(claims.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                ForEach(claims) { claim in
                    bookingClaim(claim)
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private func bookingClaim(_ claim: FreightClaimsAPI.Claim) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(claim.claimNumber)
                            .font(.headline)
                            .foregroundStyle(palette.textPrimary)
                        Text(FreightClaimConsumerCanon.label(claim.type) ?? "Peril unavailable")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    Text(FreightClaimConsumerCanon.label(claim.status) ?? "Status unavailable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(claim.status == nil ? palette.textTertiary : Brand.info)
                }
                .frame(minHeight: 52)
                Divider().opacity(0.25)
                FreightClaimValueRow(
                    label: "Vessel booking",
                    value: FreightClaimConsumerCanon.reference(for: claim, mode: .vessel)
                )
                Divider().opacity(0.25)
                FreightClaimValueRow(
                    label: "Claimed exposure",
                    value: FreightClaimConsumerCanon.financialContext(amount: claim.amount, currency: claim.currency)
                )
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Filed", value: FreightClaimConsumerCanon.clean(claim.filedDate))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Claimant", value: FreightClaimConsumerCanon.clean(claim.claimantCompanyName))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Respondent", value: FreightClaimConsumerCanon.clean(claim.respondentCompanyName))
            }
        }
        .accessibilityElement(children: .contain)
    }

    @MainActor
    private func load() async {
        loading = claims.isEmpty
        loadError = nil
        do {
            claims = try await FreightClaimConsumerCanon.claims(mode: .vessel)
        } catch {
            loadError = FreightClaimConsumerCanon.errorMessage(error)
        }
        loading = false
    }
}

#Preview("Vessel claims list") {
    VesselClaimsListScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
