//
//  776_VesselTradeLaneDocumentsCAImport.swift
//  EusoTrip — Vessel Operator · Trade Lane Documents (CA Import).
//
//  Verbatim port of wireframe 776 (06 Vessel · Dark) — the COUNTRY-DONE
//  Canadian sibling of the US trade-docs screen. Purpose-built around the
//  CANADIAN clearance process: a CBSA release-readiness hero (the canonical
//  ACI eManifest → risk cleared → Release Prior to Arrival → Form B3 stepper)
//  over the REAL CBSA import doc set, so the operator files Form B3 inside the
//  5-day post-release window before it triggers a penalty.
//
//  Endpoints (server/routers/vesselShipments.ts):
//    getCrossBorderVesselDocs (:3440 · vesselProcedure · {direction:'CA_import'}
//      → services/crossBorderVessel.getRequiredVesselDocs → the required CBSA
//      import doc names) — drives the checklist verbatim.
//  Honest gaps (surfaced to the-oath): (1) per-doc attach state + the live
//  release-stage status need a selected booking (getVesselShipmentDetail :162);
//  the required-doc endpoint returns names only, so docs render as REQUIRED and
//  the stepper is labeled the CBSA process. (2) "File Form B3" has no dedicated
//  mutation — propose vessel.fileFormB3({bookingId, docType:'B3', url}) →
//  documents row + blockchainAuditTrail + WS_CHANNELS.compliance.
//

import SwiftUI

struct VesselTradeLaneDocumentsCAImportScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselTradeLaneDocsBody(config: .caImport) } nav: {
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

#Preview("776 · Trade Lane Docs CA · Night") { VesselTradeLaneDocumentsCAImportScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("776 · Trade Lane Docs CA · Light") { VesselTradeLaneDocumentsCAImportScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
