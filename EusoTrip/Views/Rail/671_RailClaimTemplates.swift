//
//  671_RailClaimTemplates.swift
//  EusoTrip
//
//  Purpose: prevent a rail claim from starting from a generic or unversioned
//  form that cannot preserve shipment-specific evidence.
//  Archetype: capability availability notice.
//

import SwiftUI

struct RailClaimTemplatesScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            RailClaimTemplatesBody()
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

private struct RailClaimTemplatesBody: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            FreightClaimSurfaceHeader(
                context: "Rail claim templates",
                title: "Filing forms",
                purpose: "Use only versioned rail forms whose fields and evidence requirements are tied to the shipment being claimed."
            )

            EusoEmptyState(
                systemImage: "doc.badge.ellipsis",
                title: "Rail templates unavailable",
                subtitle: "No mode-specific, versioned rail claim template source is available. A generic form is not shown because it cannot preserve rail shipment and evidence context."
            )

            LifecycleCard(accentDanger: true) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Shortage filing remains blocked")
                        .font(.headline)
                        .foregroundStyle(Brand.danger)
                    Text("Expected quantity, received quantity, and quantity unit must be typed claim fields before a shortage template can be used safely.")
                        .font(.body)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
    }
}

#Preview("Rail claim templates") {
    RailClaimTemplatesScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
