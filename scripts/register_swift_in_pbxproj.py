#!/usr/bin/env python3
"""
Register unregistered Swift files in EusoTrip.xcodeproj/project.pbxproj.

Run: python3 scripts/register_swift_in_pbxproj.py

Adds each file via the SOURCE_ROOT path pattern (`name = X.swift;
path = EusoTrip/...; sourceTree = SOURCE_ROOT;`) so the registration
doesn't depend on PBXGroup nesting.

Sentinel-guarded — each entry checks that the UUID isn't already in
the file before inserting. Re-runnable.
"""

import os
import re
import sys

PBXPROJ = "/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip.xcodeproj/project.pbxproj"

# (uuid_build, uuid_ref, basename, relative path from SOURCE_ROOT)
ENTRIES = [
    ("TLEX2026060300000011A1", "TLEX2026060300000012A1",
     "TransportLexicon.swift", "EusoTrip/Models/Multimodal/TransportLexicon.swift"),
    ("CHKT2026060300000011A1", "CHKT2026060300000012A1",
     "ESangChatKit.swift", "EusoTrip/Views/Components/Chat/ESangChatKit.swift"),
    ("VD042026060300000011A1", "VD042026060300000012A1",
     "004_VesselDemurrageDetention.swift", "EusoTrip/Views/Vessel/004_VesselDemurrageDetention.swift"),
    ("RS082026060300000011A1", "RS082026060300000012A1",
     "008_RailShipperTenderWorkflow.swift", "EusoTrip/Views/Rail/008_RailShipperTenderWorkflow.swift"),
    ("DP022026060300000011A1", "DP022026060300000012A1",
     "402_DispatcherProfile.swift", "EusoTrip/Views/Dispatch/402_DispatcherProfile.swift"),
    ("EQRC2026060300000011A1", "EQRC2026060300000012A1",
     "EquipmentRequirementsCatalog.swift", "EusoTrip/Models/EquipmentRequirementsCatalog.swift"),
    ("BR4B2026060200000011A1", "BR4B2026060200000012A1",
     "404B_BrokerMe.swift",     "EusoTrip/Views/Broker/404B_BrokerMe.swift"),
    ("ES6M2026060200000011A1", "ES6M2026060200000012A1",
     "620_EscortMeHome.swift",  "EusoTrip/Views/Escort/620_EscortMeHome.swift"),
    ("TM7M2026060200000011A1", "TM7M2026060200000012A1",
     "703_TerminalMe.swift",    "EusoTrip/Views/Terminal/703_TerminalMe.swift"),
    ("AD8M2026060200000011A1", "AD8M2026060200000012A1",
     "804_AdminMe.swift",       "EusoTrip/Views/Admin/804_AdminMe.swift"),
    ("CP9M2026060200000011A1", "CP9M2026060200000012A1",
     "903_ComplianceMe.swift",  "EusoTrip/Views/Compliance/903_ComplianceMe.swift"),
    ("MMCO2026051700000011A1", "MMCO2026051700000012A1",
     "MultiModalCore.swift",   "EusoTrip/Models/Multimodal/MultiModalCore.swift"),
    ("RLLN2026051700000011A1", "RLLN2026051700000012A1",
     "RailLane.swift",          "EusoTrip/Models/RailLane.swift"),
    ("EWST2026051700000011A1", "EWST2026051700000012A1",
     "EusoWalletStore.swift",   "EusoTrip/ViewModels/EusoWalletStore.swift"),
    ("EWAP2026051700000011A1", "EWAP2026051700000012A1",
     "EusoWalletApplePayProvider.swift",
     "EusoTrip/Services/EusoWalletApplePayProvider.swift"),
    ("RIRG2026051700000011A1", "RIRG2026051700000012A1",
     "RoleIntegrationRegistry.swift",
     "EusoTrip/Services/RoleIntegrationRegistry.swift"),
    ("PRIM2026051700000011A1", "PRIM2026051700000012A1",
     "Primitives.swift",        "EusoTrip/Views/Primitives/Primitives.swift"),
    ("QRIV2026051800000011A1", "QRIV2026051800000012A1",
     "QRImageView.swift",       "EusoTrip/Views/Components/QRImageView.swift"),
    ("CSCD2026051800000011A1", "CSCD2026051800000012A1",
     "CredentialScanCard.swift",
     "EusoTrip/Views/Components/CredentialScanCard.swift"),
    ("VINS2026051800000011A1", "VINS2026051800000012A1",
     "VINScannerSheet.swift",
     "EusoTrip/Views/Components/VINScannerSheet.swift"),
    ("FBRS2026051800000011A1", "FBRS2026051800000012A1",
     "FleetBulkRegisterStep.swift",
     "EusoTrip/Views/Onboarding/FleetBulkRegisterStep.swift"),
    ("DIBS2026051800000011A1", "DIBS2026051800000012A1",
     "DriverInviteBulkStep.swift",
     "EusoTrip/Views/Onboarding/DriverInviteBulkStep.swift"),
    ("FLCD2026051800000011A1", "FLCD2026051800000012A1",
     "FMCSALookupCard.swift",
     "EusoTrip/Views/Components/FMCSALookupCard.swift"),
    ("AAPR2026051900000011A1", "AAPR2026051900000012A1",
     "AppleAuthProvider.swift",
     "EusoTrip/Services/AppleAuthProvider.swift"),
    ("AABT2026051900000011A1", "AABT2026051900000012A1",
     "AppleAuthButtons.swift",
     "EusoTrip/Views/Auth/AppleAuthButtons.swift"),
    ("PKMV2026051900000011A1", "PKMV2026051900000012A1",
     "PasskeysManagementView.swift",
     "EusoTrip/Views/Auth/PasskeysManagementView.swift"),
    ("RCI62026060200000011A1", "RCI62026060200000012A1",
     "606_RailCargoInsurance.swift",
     "EusoTrip/Views/Rail/606_RailCargoInsurance.swift"),
    ("R6562026060200000011A1", "R6562026060200000012A1",
     "656_RailClaimPayments.swift",
     "EusoTrip/Views/Rail/656_RailClaimPayments.swift"),
    ("R6692026060200000011A1", "R6692026060200000012A1",
     "669_RailOverchargeRecovery.swift",
     "EusoTrip/Views/Rail/669_RailOverchargeRecovery.swift"),
    ("R6702026060200000011A1", "R6702026060200000012A1",
     "670_RailShortageClaims.swift",
     "EusoTrip/Views/Rail/670_RailShortageClaims.swift"),
    ("R6712026060200000011A1", "R6712026060200000012A1",
     "671_RailClaimTemplates.swift",
     "EusoTrip/Views/Rail/671_RailClaimTemplates.swift"),
    ("R6732026060200000011A1", "R6732026060200000012A1",
     "673_RailIntermodalDashboard.swift",
     "EusoTrip/Views/Rail/673_RailIntermodalDashboard.swift"),
    ("R6392026060200000011A1", "R6392026060200000012A1",
     "639_RailYardDirectory.swift",
     "EusoTrip/Views/Rail/639_RailYardDirectory.swift"),
    ("R6722026060200000011A1", "R6722026060200000012A1",
     "672_RailLayoverTracking.swift",
     "EusoTrip/Views/Rail/672_RailLayoverTracking.swift"),
    ("VDL72026060200000011A1", "VDL72026060200000012A1",
     "757_VesselDetentionLetters.swift",
     "EusoTrip/Views/Vessel/757_VesselDetentionLetters.swift"),
    ("VDC82026060200000011A1", "VDC82026060200000012A1",
     "815_VesselDemurrageChargeApproval.swift",
     "EusoTrip/Views/Vessel/815_VesselDemurrageChargeApproval.swift"),
    ("V6692026060200000011A1", "V6692026060200000012A1",
     "669_VesselBookingAmendment.swift",
     "EusoTrip/Views/Vessel/669_VesselBookingAmendment.swift"),
    ("V7062026060200000011A1", "V7062026060200000012A1",
     "706_VesselRebookingSuggestions.swift",
     "EusoTrip/Views/Vessel/706_VesselRebookingSuggestions.swift"),
    ("V7372026060200000011A1", "V7372026060200000012A1",
     "737_VesselDrayageOrders.swift",
     "EusoTrip/Views/Vessel/737_VesselDrayageOrders.swift"),
    ("V7722026060200000011A1", "V7722026060200000012A1",
     "772_VesselDemurrageAnalytics.swift",
     "EusoTrip/Views/Vessel/772_VesselDemurrageAnalytics.swift"),
    ("V7922026060200000011A1", "V7922026060200000012A1",
     "792_VesselDemurrageCalculator.swift",
     "EusoTrip/Views/Vessel/792_VesselDemurrageCalculator.swift"),
    ("V7092026060200000011A1", "V7092026060200000012A1",
     "709_VesselBidBoard.swift",
     "EusoTrip/Views/Vessel/709_VesselBidBoard.swift"),
    ("V8002026060200000011A1", "V8002026060200000012A1",
     "800_VesselClaimsDashboard.swift",
     "EusoTrip/Views/Vessel/800_VesselClaimsDashboard.swift"),
    ("V8012026060200000011A1", "V8012026060200000012A1",
     "801_VesselClaimsList.swift",
     "EusoTrip/Views/Vessel/801_VesselClaimsList.swift"),
    ("V8082026060200000011A1", "V8082026060200000012A1",
     "808_VesselClaimWorkflow.swift",
     "EusoTrip/Views/Vessel/808_VesselClaimWorkflow.swift"),
    ("V7322026060200000011A1", "V7322026060200000012A1",
     "732_VesselCargoClaim.swift",
     "EusoTrip/Views/Vessel/732_VesselCargoClaim.swift"),
    ("V0062026060200000011A1", "V0062026060200000012A1",
     "006_VesselCustomsISF.swift",
     "EusoTrip/Views/Vessel/006_VesselCustomsISF.swift"),
    ("V8142026060200000011A1", "V8142026060200000012A1",
     "814_VesselCustomsEntryFiling.swift",
     "EusoTrip/Views/Vessel/814_VesselCustomsEntryFiling.swift"),
    ("V7892026060200000011A1", "V7892026060200000012A1",
     "789_VesselCustomsStatusUpdate.swift",
     "EusoTrip/Views/Vessel/789_VesselCustomsStatusUpdate.swift"),
    ("V7702026060200000011A1", "V7702026060200000012A1",
     "770_VesselETAPrediction.swift",
     "EusoTrip/Views/Vessel/770_VesselETAPrediction.swift"),
    ("V7822026060200000011A1", "V7822026060200000012A1",
     "782_VesselDwellAnalysis.swift",
     "EusoTrip/Views/Vessel/782_VesselDwellAnalysis.swift"),
    ("V8162026060200000011A1", "V8162026060200000012A1",
     "816_VesselTopShippers.swift",
     "EusoTrip/Views/Vessel/816_VesselTopShippers.swift"),
    ("C3732026060200000011A1", "C3732026060200000012A1",
     "373_CatalystAwardedCelM04.swift",
     "EusoTrip/Views/Catalyst/373_CatalystAwardedCelM04.swift"),
    ("C3742026060200000011A1", "C3742026060200000012A1",
     "374_CatalystPickupOnSiteEchoCelM04.swift",
     "EusoTrip/Views/Catalyst/374_CatalystPickupOnSiteEchoCelM04.swift"),
    ("C3752026060200000011A1", "C3752026060200000012A1",
     "375_CatalystInTransitFleetTrackCelM04.swift",
     "EusoTrip/Views/Catalyst/375_CatalystInTransitFleetTrackCelM04.swift"),
    ("C3762026060200000011A1", "C3762026060200000012A1",
     "376_CatalystAtDeliveryFleetTrackCelM04.swift",
     "EusoTrip/Views/Catalyst/376_CatalystAtDeliveryFleetTrackCelM04.swift"),
    ("V8202026060200000011A1", "V8202026060200000012A1",
     "820_VesselReeferPreCool.swift",
     "EusoTrip/Views/Vessel/820_VesselReeferPreCool.swift"),
    ("V8212026060200000011A1", "V8212026060200000012A1",
     "821_VesselReeferAlertConsole.swift",
     "EusoTrip/Views/Vessel/821_VesselReeferAlertConsole.swift"),
    ("V7352026060200000011A1", "V7352026060200000012A1",
     "735_VesselDemurrageAlerts.swift",
     "EusoTrip/Views/Vessel/735_VesselDemurrageAlerts.swift"),
    ("V6892026060200000011A1", "V6892026060200000012A1",
     "689_VesselNetworkDisruption.swift",
     "EusoTrip/Views/Vessel/689_VesselNetworkDisruption.swift"),
    ("V8022026060200000011A1", "V8022026060200000012A1",
     "802_VesselClaimPayments.swift",
     "EusoTrip/Views/Vessel/802_VesselClaimPayments.swift"),
    ("V8042026060200000011A1", "V8042026060200000012A1",
     "804_VesselOverchargeRecovery.swift",
     "EusoTrip/Views/Vessel/804_VesselOverchargeRecovery.swift"),
    ("V8052026060200000011A1", "V8052026060200000012A1",
     "805_VesselLossPrevention.swift",
     "EusoTrip/Views/Vessel/805_VesselLossPrevention.swift"),
    ("V8092026060200000011A1", "V8092026060200000012A1",
     "809_VesselDisputeResolution.swift",
     "EusoTrip/Views/Vessel/809_VesselDisputeResolution.swift"),
    ("V6602026060200000011A1", "V6602026060200000012A1",
     "660_VesselLivePosition.swift",
     "EusoTrip/Views/Vessel/660_VesselLivePosition.swift"),
    ("V6612026060200000011A1", "V6612026060200000012A1",
     "661_VesselPortCalls.swift",
     "EusoTrip/Views/Vessel/661_VesselPortCalls.swift"),
    ("V6742026060200000011A1", "V6742026060200000012A1",
     "674_VesselCostBreakdown.swift",
     "EusoTrip/Views/Vessel/674_VesselCostBreakdown.swift"),
    ("V6962026060200000011A1", "V6962026060200000012A1",
     "696_VesselSettlementBatch.swift",
     "EusoTrip/Views/Vessel/696_VesselSettlementBatch.swift"),
    ("V7842026060200000011A1", "V7842026060200000012A1",
     "784_VesselDetentionTracking.swift",
     "EusoTrip/Views/Vessel/784_VesselDetentionTracking.swift"),
    ("V8102026060200000011A1", "V8102026060200000012A1",
     "810_VesselDisputeMediation.swift",
     "EusoTrip/Views/Vessel/810_VesselDisputeMediation.swift"),
    ("V8112026060200000011A1", "V8112026060200000012A1",
     "811_VesselClaimsAnalytics.swift",
     "EusoTrip/Views/Vessel/811_VesselClaimsAnalytics.swift"),
    ("V8122026060200000011A1", "V8122026060200000012A1",
     "812_VesselClaimTemplates.swift",
     "EusoTrip/Views/Vessel/812_VesselClaimTemplates.swift"),
    ("V6702026060200000011A1", "V6702026060200000012A1",
     "670_VesselBunkerPrices.swift",
     "EusoTrip/Views/Vessel/670_VesselBunkerPrices.swift"),
    ("V7082026060200000011A1", "V7082026060200000012A1",
     "708_VesselShipmentCO2.swift",
     "EusoTrip/Views/Vessel/708_VesselShipmentCO2.swift"),
]


def main():
    with open(PBXPROJ, "r", encoding="utf-8") as fh:
        src = fh.read()

    edited = 0
    for uuid_b, uuid_r, basename, relpath in ENTRIES:
        if uuid_b in src:
            print(f"[skip] {basename} — UUID already present")
            continue

        # 1. Add PBXBuildFile entry — anchor on LoadModeBadge build line.
        anchor_build = (
            "\t\tLMBD2026051700000011A1 /* LoadModeBadge.swift in Sources */ = "
            "{isa = PBXBuildFile; fileRef = LMBD2026051700000012A1 /* LoadModeBadge.swift */; };"
        )
        new_build = (
            f"\t\t{uuid_b} /* {basename} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {uuid_r} /* {basename} */; }};"
        )
        if anchor_build not in src:
            print(f"[ERR ] {basename}: build-anchor not found, abort")
            return 1
        src = src.replace(anchor_build, anchor_build + "\n" + new_build, 1)

        # 2. Add PBXFileReference entry — SOURCE_ROOT path pattern.
        anchor_ref = (
            "\t\tLMBD2026051700000012A1 /* LoadModeBadge.swift */ = "
            "{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            "path = LoadModeBadge.swift; sourceTree = \"<group>\"; };"
        )
        new_ref = (
            f"\t\t{uuid_r} /* {basename} */ = "
            f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            f"name = {basename}; path = {relpath}; sourceTree = SOURCE_ROOT; }};"
        )
        if anchor_ref not in src:
            print(f"[ERR ] {basename}: ref-anchor not found, abort")
            return 1
        src = src.replace(anchor_ref, anchor_ref + "\n" + new_ref, 1)

        # 3. Add to Sources build phase — anchor on LoadModeBadge sources line.
        anchor_sources = (
            "\t\t\t\tLMBD2026051700000011A1 /* LoadModeBadge.swift in Sources */,"
        )
        new_sources = f"\t\t\t\t{uuid_b} /* {basename} in Sources */,"
        if anchor_sources not in src:
            print(f"[ERR ] {basename}: sources-anchor not found, abort")
            return 1
        src = src.replace(anchor_sources, anchor_sources + "\n" + new_sources, 1)

        # 4. Add to a Group (use the same Components group as LoadModeBadge
        # for the SOURCE_ROOT pattern, since `name = ...` displays
        # correctly anywhere; group membership is just for the navigator).
        anchor_group = (
            "\t\t\t\tLMBD2026051700000012A1 /* LoadModeBadge.swift */,"
        )
        new_group = f"\t\t\t\t{uuid_r} /* {basename} */,"
        if anchor_group not in src:
            print(f"[ERR ] {basename}: group-anchor not found, abort")
            return 1
        src = src.replace(anchor_group, anchor_group + "\n" + new_group, 1)

        edited += 1
        print(f"[done] {basename}")

    with open(PBXPROJ, "w", encoding="utf-8") as fh:
        fh.write(src)
    print(f"\nRegistered {edited} files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
