//
//  660_RailClaimReport.swift
//  EusoTrip
//
//  Purpose: review one rail claim's exportable proof without generating a file
//  that changes its amount, currency, mode, party scope, or evidence record.
//  Archetype: read-only report proof sheet.
//

import SwiftUI

struct RailClaimReportScreen: View {
    let theme: Theme.Palette
    var claimId: String

    init(theme: Theme.Palette, claimId: String = "") {
        self.theme = theme
        self.claimId = claimId
    }

    var body: some View {
        Shell(theme: theme) {
            RailClaimReportBody(claimId: claimId)
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

private struct RailClaimReportBody: View {
    @Environment(\.palette) private var palette
    let claimId: String

    @State private var claim: FreightClaimsAPI.ClaimDetail?
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            FreightClaimSurfaceHeader(
                context: "Rail claim report",
                title: "Proof sheet",
                purpose: "Review the live claim record and its export readiness before sharing it with an insurer, customer, or regulator."
            )

            if loading && claim == nil {
                ProgressView("Loading claim report")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let loadError {
                LifecycleCard(accentDanger: true) {
                    Text(loadError).font(.body).foregroundStyle(Brand.danger)
                }
            } else if let claim {
                reportSummary(claim)
                proofInventory(claim)
                EusoEmptyState(
                    systemImage: "square.and.arrow.up.trianglebadge.exclamationmark",
                    title: "Download unavailable",
                    subtitle: "A rail claim file cannot yet be generated without risking loss of its typed currency and party scope. The live proof sheet remains available here."
                )
            } else {
                EusoEmptyState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "No rail claim report",
                    subtitle: "No claim tied to a rail shipment is available to this account."
                )
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private func reportSummary(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
        LifecycleCard {
            VStack(spacing: 0) {
                FreightClaimValueRow(label: "Claim", value: claim.claimNumber)
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Rail shipment", value: FreightClaimConsumerCanon.reference(for: claim, mode: .rail))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Status", value: FreightClaimConsumerCanon.label(claim.status))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Type", value: FreightClaimConsumerCanon.label(claim.type))
                Divider().opacity(0.25)
                FreightClaimValueRow(
                    label: "Claimed exposure",
                    value: FreightClaimConsumerCanon.financialContext(amount: claim.amount, currency: claim.currency)
                )
            }
        }
    }

    private func proofInventory(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Proof inventory")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.bottom, Space.s2)
                FreightClaimValueRow(label: "Evidence records", value: claim.evidence.count.formatted())
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Timeline events", value: claim.timeline.count.formatted())
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Notes", value: claim.notes.count.formatted())
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Last updated", value: FreightClaimConsumerCanon.clean(claim.updatedAt))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Decision", value: FreightClaimConsumerCanon.label(claim.decision?.type))
            }
        }
    }

    @MainActor
    private func load() async {
        loading = claim == nil
        loadError = nil
        do {
            claim = try await FreightClaimConsumerCanon.detail(claimId: claimId, mode: .rail)
        } catch {
            loadError = FreightClaimConsumerCanon.errorMessage(error)
        }
        loading = false
    }
}

#Preview("Rail claim report") {
    RailClaimReportScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
