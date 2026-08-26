//
//  777_VesselTradeLaneDocumentsMXImport.swift
//  EusoTrip — Vessel Operator · Trade Lane Documents (MX Import).
//
//  Verbatim port of wireframe 777 (06 Vessel · Dark) — the COUNTRY-DONE
//  Mexican sibling that completes the visible tri-country doc proof. Purpose-
//  built around the Mexican despacho aduanero (Pedimento · VUCEM COVE ·
//  semáforo fiscal · NOM labeling review) over the REAL Aduana import doc set,
//  so the operator chases the NOM-050 labeling review — the PGA hold that
//  actually stops delivery — before the truck is tendered.
//
//  Endpoints (server/routers/vesselShipments.ts):
//    getCrossBorderVesselDocs (:3440 · vesselProcedure · {direction:'MX_import'}
//      → services/crossBorderVessel.getRequiredVesselDocs → the required Aduana
//      import doc names) — drives the checklist verbatim.
//  Honest gaps (surfaced to the-oath): per-doc attach + live modulación need a
//  selected booking (getVesselShipmentDetail :162); "Revisar NOM-050" has no
//  dedicated mutation — propose vessel.reviewNom({bookingId, nom:'NOM-050', url})
//  → documents row + blockchainAuditTrail + WS_CHANNELS.compliance.
//
//  Shared render path: VesselTradeLaneDocsBody(config: .mxImport) in
//  VesselTradeKit.swift — same endpoint, MX regime framing.
//

import SwiftUI

struct VesselTradeLaneDocumentsMXImportScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselTradeLaneDocsBody(config: .mxImport) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

#Preview("777 · Trade Lane Docs MX · Night") { VesselTradeLaneDocumentsMXImportScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("777 · Trade Lane Docs MX · Light") { VesselTradeLaneDocumentsMXImportScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
