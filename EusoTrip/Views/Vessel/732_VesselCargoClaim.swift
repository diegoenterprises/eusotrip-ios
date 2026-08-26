//
//  732_VesselCargoClaim.swift
//  EusoTrip
//
//  Purpose: inspect one vessel cargo claim as a booking-bound proof record,
//  retaining its original money, quantity, parties, evidence, and provenance.
//  Archetype: maritime claim dossier.
//

import SwiftUI

struct VesselCargoClaimScreen: View {
    let theme: Theme.Palette
    let claimId: String

    init(theme: Theme.Palette, claimId: String = "") {
        self.theme = theme
        self.claimId = claimId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselCargoClaimBody(claimId: claimId)
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                    NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)
                ],
                trailing: [
                    NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                    NavSlot(label: "Me", systemImage: "person", isCurrent: false)
                ],
                orbState: .idle
            )
        }
    }
}

private struct VesselCargoClaimBody: View {
    @Environment(\.palette) private var palette
    let claimId: String

    @State private var claim: FreightClaimsAPI.ClaimDetail?
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            FreightClaimSurfaceHeader(
                context: "Vessel cargo claim",
                title: "Maritime claim dossier",
                purpose: "Verify one vessel booking claim against its cargo context, counterparties, evidence, and acknowledged workflow."
            )

            if loading && claim == nil {
                ProgressView("Loading vessel claim")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let loadError {
                LifecycleCard(accentDanger: true) {
                    Text(loadError)
                        .font(.body)
                        .foregroundStyle(Brand.danger)
                }
            } else if let claim {
                bookingIdentity(claim)
                cargoContext(claim)
                if claim.type?.lowercased() == FreightClaimsAPI.ClaimType.shortage.rawValue {
                    shortageGap
                }
                counterpartyChain(claim)
                FreightClaimEvidenceRegister(evidence: claim.evidence)
                FreightClaimWorkflowRegister(workflow: claim.workflow)
                provenance(claim)
            } else {
                EusoEmptyState(
                    systemImage: "lifepreserver",
                    title: "No vessel cargo claims",
                    subtitle: "No claim tied to a vessel booking is available to this account."
                )
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private func bookingIdentity(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
        LifecycleCard {
            VStack(spacing: 0) {
                FreightClaimValueRow(label: "Claim", value: claim.claimNumber)
                Divider().opacity(0.25)
                FreightClaimValueRow(
                    label: "Vessel booking",
                    value: FreightClaimConsumerCanon.reference(for: claim, mode: .vessel)
                )
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Peril", value: FreightClaimConsumerCanon.label(claim.type))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Status", value: FreightClaimConsumerCanon.label(claim.status))
                Divider().opacity(0.25)
                FreightClaimValueRow(
                    label: "Claimed exposure",
                    value: FreightClaimConsumerCanon.financialContext(amount: claim.amount, currency: claim.currency)
                )
            }
        }
    }

    private func cargoContext(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Cargo and voyage context")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            LifecycleCard {
                VStack(spacing: 0) {
                    FreightClaimValueRow(label: "Load port", value: FreightClaimConsumerCanon.clean(claim.load.origin))
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Discharge", value: FreightClaimConsumerCanon.clean(claim.load.destination))
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Cargo", value: FreightClaimConsumerCanon.clean(claim.load.commodity))
                    Divider().opacity(0.25)
                    FreightClaimValueRow(
                        label: "Recorded quantity",
                        value: FreightClaimConsumerCanon.quantityContext(amount: claim.load.weight, unit: claim.load.weightUnit)
                    )
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Occurred", value: FreightClaimConsumerCanon.clean(claim.occurredAt))
                }
            }
        }
    }

    private var shortageGap: some View {
        LifecycleCard(accentDanger: true) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Label("Shortage quantities unavailable", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(Brand.danger)
                Text("The claim does not carry typed expected quantity, received quantity, and quantity unit evidence. Cargo weight and narrative text are not substituted for a shortage calculation.")
                    .font(.body)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func counterpartyChain(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Counterparty chain")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            LifecycleCard {
                VStack(spacing: 0) {
                    FreightClaimValueRow(label: "Claimant", value: FreightClaimConsumerCanon.clean(claim.claimant?.name))
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Respondent", value: FreightClaimConsumerCanon.clean(claim.respondent?.name))
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Ocean carrier", value: FreightClaimConsumerCanon.clean(claim.carrier?.name))
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Shipper", value: FreightClaimConsumerCanon.clean(claim.shipper?.name))
                }
            }
        }
    }

    private func provenance(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Record provenance")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            FreightClaimValueRow(label: "Filed", value: FreightClaimConsumerCanon.clean(claim.filedDate))
            FreightClaimValueRow(label: "Last updated", value: FreightClaimConsumerCanon.clean(claim.updatedAt))
            Text("Source: EusoTrip freight claims register")
                .font(.caption)
                .foregroundStyle(palette.textTertiary)
        }
    }

    @MainActor
    private func load() async {
        loading = claim == nil
        loadError = nil
        do {
            claim = try await FreightClaimConsumerCanon.detail(claimId: claimId, mode: .vessel)
        } catch {
            loadError = FreightClaimConsumerCanon.errorMessage(error)
        }
        loading = false
    }
}

#Preview("Vessel cargo claim") {
    VesselCargoClaimScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
