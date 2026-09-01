//
//  813_VesselClaimReport.swift
//  EusoTrip
//
//  Purpose: inspect the documentary basis for one vessel claim before an
//  insurer, counterparty, or authority receives an exported report.
//  Archetype: maritime documentary proof sheet.
//

import SwiftUI

struct VesselClaimReportScreen: View {
    let theme: Theme.Palette
    var claimId: String

    init(theme: Theme.Palette, claimId: String = "") {
        self.theme = theme
        self.claimId = claimId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselClaimReportBody(claimId: claimId)
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

private struct VesselClaimReportBody: View {
    @Environment(\.palette) private var palette
    let claimId: String

    @State private var claim: FreightClaimsAPI.ClaimDetail?
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            FreightClaimSurfaceHeader(
                context: "Vessel claim report",
                title: "Documentary proof sheet",
                purpose: "Verify the booking anchor, parties, financial context, evidence, and recorded outcome before any claim report leaves EusoTrip."
            )

            if loading && claim == nil {
                ProgressView("Loading documentary proof")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let loadError {
                LifecycleCard(accentDanger: true) {
                    Text(loadError).font(.body).foregroundStyle(Brand.danger)
                }
            } else if let claim {
                claimBasis(claim)
                documentaryInventory(claim)
                partyBasis(claim)
                EusoEmptyState(
                    systemImage: "square.and.arrow.up.trianglebadge.exclamationmark",
                    title: "Download unavailable",
                    subtitle: "A vessel claim file cannot yet be generated without risking loss of typed currency, booking, or party context. The live proof sheet remains available here."
                )
            } else {
                EusoEmptyState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "No vessel claim report",
                    subtitle: "No claim tied to a vessel booking is available to this account."
                )
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private func claimBasis(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
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

    private func documentaryInventory(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Documentary inventory")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            LifecycleCard {
                VStack(spacing: 0) {
                    FreightClaimValueRow(label: "Evidence records", value: claim.evidence.count.formatted())
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Timeline events", value: claim.timeline.count.formatted())
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Notes", value: claim.notes.count.formatted())
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Filed", value: FreightClaimConsumerCanon.clean(claim.filedDate))
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Last updated", value: FreightClaimConsumerCanon.clean(claim.updatedAt))
                }
            }
        }
    }

    private func partyBasis(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
        LifecycleCard {
            VStack(spacing: 0) {
                FreightClaimValueRow(label: "Claimant", value: FreightClaimConsumerCanon.clean(claim.claimant?.name))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Respondent", value: FreightClaimConsumerCanon.clean(claim.respondent?.name))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Decision", value: FreightClaimConsumerCanon.label(claim.decision?.type))
                Divider().opacity(0.25)
                FreightClaimValueRow(
                    label: "Decision amount",
                    value: claim.decision.flatMap {
                        FreightClaimConsumerCanon.financialContext(amount: $0.amount, currency: claim.currency)
                    }
                )
            }
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

#Preview("Vessel claim report") {
    VesselClaimReportScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
