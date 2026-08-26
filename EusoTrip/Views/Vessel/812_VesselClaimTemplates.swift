//
//  812_VesselClaimTemplates.swift
//  EusoTrip
//
//  Purpose: prevent vessel claims from starting from generic, unversioned
//  forms that cannot preserve booking, cargo, regime, and evidence context.
//  Archetype: maritime form availability notice.
//

import SwiftUI

struct VesselClaimTemplatesScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            VesselClaimTemplatesBody()
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

private struct VesselClaimTemplatesBody: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            FreightClaimSurfaceHeader(
                context: "Vessel claim templates",
                title: "Maritime forms",
                purpose: "Start only from a versioned form whose booking, cargo, documentary, and jurisdictional requirements are explicit."
            )

            EusoEmptyState(
                systemImage: "doc.badge.ellipsis",
                title: "Vessel templates unavailable",
                subtitle: "No persisted, mode-specific vessel claim template source is available. Generic peril cards and regional overlays are withheld because they are not claim evidence."
            )

            LifecycleCard(accentDanger: true) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Shortage form unavailable")
                        .font(.headline)
                        .foregroundStyle(Brand.danger)
                    Text("A vessel shortage form requires typed expected quantity, received quantity, and quantity unit fields before it can support a defensible cargo calculation.")
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

#Preview("Vessel claim templates") {
    VesselClaimTemplatesScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
