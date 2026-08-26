//
//  EusoTripMapStyleRegistryTests.swift
//  EusoTripTests
//

import XCTest
@testable import EusoTrip

final class EusoTripMapStyleRegistryTests: XCTestCase {
    private let expectedHashes: [String: String] = [
        "truck.operational.light": "0e0daa28c29a30265110ad7d2118282bd8682749f731b7e353a15270b05be4e9",
        "truck.operational.dark": "9b52bc8de2fe119e056514a9f0afaf0c0a2ed1d5e2a308e1695b0770856fecea",
        "truck.navigation.light": "40ef31554a8cb3ce1fac629d4b702ca7389eb9196fb66aeab1de33d8a56d8ac8",
        "truck.navigation.dark": "fd81c9865eed863842edbfe404bc5c2dd117aef266be8b5cd336b03cf040a0d6",
        "truck.terrain.light": "5f0750dcb9df68286061eda3717c91cff705393dc287373f6016a9fc0f606570",
        "truck.terrain.dark": "3e7614e7143bd4f51a9f2d769a6e8591fcdf2eaaeb839bcce53bc4d4f9d2e0f2",
        "rail.operational.light": "4ebe23dd22a07f70e5d8fb0e3e0a732301c964c2983cc9dfdb33703ce2d79c26",
        "rail.operational.dark": "d5f03fc7ab472f7ae7946973381a93d17220be61d863a5f7ef4d06915851f867",
        "rail.navigation.light": "70c7de9d9ec419beb358b40c7ee8d291a22042347e6cb67bdb0ac19c4e538c1b",
        "rail.navigation.dark": "b469e284ac6ab1ea49cda65ca45397af33db35589ee294c3666dd6b880091752",
        "rail.terrain.light": "0473802d19e61454e90eaf310669f6eb4522e51548f7a364de8bb0cce4e1582e",
        "rail.terrain.dark": "7930864b029abbab9edfe9ac78f21cf72d3388fbfa5072d4913a0ca3377c352e",
        "vessel.operational.light": "0e0436786d01f57743a98791f345e7829279fb55c75e0e944aa876d0154a8b38",
        "vessel.operational.dark": "70082d699164833621d39346f299ce949cf54d7649cedd01233b112e3d8f1f8c",
        "vessel.navigation.light": "5d5f548168f116e4745b69818c5684cb3fe63206a71e634b21c26d35426273ab",
        "vessel.navigation.dark": "88aec437a5f9e76caf36a0cec84845aa2ed26083cf1beda94d38a442d1819780",
        "vessel.terrain.light": "0d77a28db8884128b6d34835778538d9d7922bd684c63c695421de5e2af36ff5",
        "vessel.terrain.dark": "f9725b6ac055a1a27ebb24c072db2aa0b228cd979ac9d7c5ad39173a37721aa9",
    ]

    func testCatalogIsExactEighteenOutcomeMatrix() {
        let styles = EusoTripMapStyleRegistry.allStyles

        XCTAssertEqual(styles.count, 18)
        XCTAssertEqual(Set(styles.map(\.id)).count, 18)
        XCTAssertEqual(Set(styles.map(\.artifactSHA256)).count, 18)

        for mode in EusoTripMapProductMode.allCases {
            for family in EusoTripMapFamily.allCases {
                for theme in EusoTripMapTheme.allCases {
                    XCTAssertEqual(
                        styles.filter { $0.mode == mode && $0.family == family && $0.theme == theme }.count,
                        1
                    )
                }
            }
        }
    }

    func testCatalogMatchesDeterministicWebArtifactHashesAndPaths() {
        let actual = Dictionary(
            uniqueKeysWithValues: EusoTripMapStyleRegistry.allStyles.map { ($0.id, $0.artifactSHA256) }
        )
        XCTAssertEqual(actual, expectedHashes)

        for style in EusoTripMapStyleRegistry.allStyles {
            XCTAssertEqual(style.artifactSHA256.count, 64)
            XCTAssertTrue(style.artifactPath.contains(style.artifactSHA256))
            XCTAssertTrue(style.artifactPath.hasSuffix(".tar.gz"))
            XCTAssertTrue(style.artifactPath.contains("eusotrip-\(style.mode.rawValue)-\(style.family.rawValue)-\(style.theme.rawValue)"))
            XCTAssertEqual(style.artifactVersion, style.family == .navigation ? "v2" : "v1")
            XCTAssertTrue(style.artifactPath.contains("-\(style.artifactVersion)-"))
        }
    }

    func testAllProductArtifactsRemainPendingUntilNativeScreenshotReview() {
        XCTAssertTrue(EusoTripMapStyleRegistry.allStyles.allSatisfy {
            $0.styleOverrideCount == 282
                && $0.paletteVersion == "eusorone.mode-map.v1"
                && $0.runtimeOverlayContractVersion == "eusorone.route-overlay.v2"
                && $0.visualReviewState == .pending
                && !$0.isProductionEligible
                && $0.visualReviewNote.contains("not visual approval")
        })
    }

    func testMatchingFallbackNeverUsesStockRoadNetworkForNavigationV2() {
        XCTAssertEqual(
            EusoTripMapStyleRegistry.style(mode: .truck, family: .operational, theme: .light)
                .hereDefaultStyleIdentity,
            "logistics.day"
        )
        XCTAssertEqual(
            EusoTripMapStyleRegistry.style(mode: .rail, family: .navigation, theme: .dark)
                .hereDefaultStyleIdentity,
            "logistics.night"
        )
        XCTAssertEqual(
            EusoTripMapStyleRegistry.style(mode: .vessel, family: .terrain, theme: .light)
                .hereDefaultStyleIdentity,
            "topo.day"
        )
        XCTAssertTrue(EusoTripMapStyleRegistry.allStyles
            .filter { $0.family == .navigation }
            .allSatisfy {
                $0.artifactVersion == "v2"
                    && $0.hereDefaultFallbackName.hasPrefix("Logistics ")
                    && !$0.hereDefaultStyleIdentity.hasPrefix("road.network.")
                    && !$0.artifactPath.contains("road-network")
            })
    }

    func testBargeRequiresActualActiveVesselProduct() {
        let unconfirmed = resolve(.barge(activeVesselProduct: false))
        XCTAssertNil(unconfirmed.descriptor)
        XCTAssertEqual(unconfirmed.unavailableReason, .bargeRequiresActiveVesselProduct)

        let confirmed = resolve(.barge(activeVesselProduct: true))
        XCTAssertEqual(confirmed.descriptor?.mode, .vessel)
    }

    func testEscortRequiresActualRoadEscortProduct() {
        let unconfirmed = resolve(.escort(activeRoadEscort: false))
        XCTAssertNil(unconfirmed.descriptor)
        XCTAssertEqual(unconfirmed.unavailableReason, .escortRequiresActiveRoadProduct)

        let confirmed = resolve(.escort(activeRoadEscort: true))
        XCTAssertEqual(confirmed.descriptor?.mode, .truck)
    }

    func testIntermodalAndUnknownFailClosedWithoutExplicitActiveSegment() {
        XCTAssertEqual(
            resolve(.intermodal(activeSegment: nil)).unavailableReason,
            .intermodalRequiresActiveSegment
        )
        XCTAssertEqual(resolve(.unknown).unavailableReason, .unknownTransportMode)

        for mode in EusoTripMapProductMode.allCases {
            XCTAssertEqual(resolve(.intermodal(activeSegment: mode)).descriptor?.mode, mode)
        }
    }

    func testRawModeAdapterDoesNotConfirmAliases() {
        XCTAssertEqual(resolve(.unconfirmed(.truck)).descriptor?.mode, .truck)
        XCTAssertEqual(resolve(.unconfirmed(.rail)).descriptor?.mode, .rail)
        XCTAssertEqual(resolve(.unconfirmed(.vessel)).descriptor?.mode, .vessel)
        XCTAssertEqual(
            resolve(.unconfirmed(.barge)).unavailableReason,
            .bargeRequiresActiveVesselProduct
        )
        XCTAssertEqual(
            resolve(.unconfirmed(.escort)).unavailableReason,
            .escortRequiresActiveRoadProduct
        )
        XCTAssertEqual(
            resolve(.unconfirmed(.intermodal)).unavailableReason,
            .intermodalRequiresActiveSegment
        )
    }

    func testUnknownSavedAssetFailsClosedInMatchingTheme() {
        let resolution = EusoTripMapStyleRegistry.resolveAsset(
            named: "retired-style",
            preferredTheme: .dark
        )

        XCTAssertEqual(resolution.unavailableReason, .unknownArtifactName)
        XCTAssertNil(resolution.descriptor)
        XCTAssertEqual(resolution.foundation.family, .operational)
        XCTAssertEqual(resolution.foundation.theme, .dark)
    }

    func testOwnedRouteGradientUsesExactRouteOrderStops() {
        XCTAssertEqual(
            EusoTripMapIdentityContract.routeGradientStops,
            ["#1473FF", "#813FF5", "#BE01FF"]
        )
        XCTAssertEqual(
            EusoTripMapIdentityContract.chromeGradientCSS,
            "linear-gradient(90deg, #1473FF 0%, #813FF5 52%, #BE01FF 100%)"
        )
        XCTAssertEqual(
            HereRouteVisualState.allCases.map(\.displayName),
            ["Planned", "Active", "Completed", "Rerouting", "Stale", "Hazard", "Off Route"]
        )
    }

    func testManualFamilyChoiceWinsAndNeverStopsGuidance() {
        var state = EusoTripMapSelectionState(selectedFamily: .operational, theme: .dark)
        state.beginActiveJob(
            id: "rail-job",
            transportMode: .rail,
            guidancePhase: .guiding
        )
        XCTAssertEqual(state.selectedFamily, .operational)
        XCTAssertEqual(state.recommendedFamily, .navigation)

        state.selectFamily(.terrain)

        XCTAssertEqual(state.currentStyle?.assetName, "EusoTrip Rail Terrain Dark v1")
        XCTAssertEqual(state.guidancePhase, .guiding)
        XCTAssertTrue(state.guidancePhase.isRouteGuidanceActive)
        XCTAssertTrue(state.hasManualFamilyChoiceDuringActiveJob)
    }

    func testSelectionStateKeepsAmbiguousModesUnavailableUntilSegmentEvidence() {
        var state = EusoTripMapSelectionState(theme: .light)
        state.beginActiveJob(
            id: "intermodal-job",
            transportMode: .intermodal,
            guidancePhase: .previewing
        )
        XCTAssertEqual(state.currentStyleResolution.unavailableReason, .intermodalRequiresActiveSegment)

        state.updateActiveProductSegment(.vessel)
        XCTAssertEqual(state.currentStyle?.mode, .vessel)

        state.endActiveJob()
        XCTAssertNil(state.currentStyle)
        XCTAssertNil(state.activeProductSegment)
        XCTAssertEqual(state.guidancePhase, .inactive)
    }

    func testEmptyJobAndStalePersistenceCannotRestoreGuidanceOrMode() throws {
        var state = EusoTripMapSelectionState(selectedFamily: .terrain, theme: .light)
        state.beginActiveJob(
            id: "  \n",
            transportMode: .truck,
            guidancePhase: .guiding
        )
        XCTAssertFalse(state.hasActiveJob)
        XCTAssertNil(state.currentStyle)

        let decoded = try JSONDecoder().decode(
            EusoTripMapSelectionState.self,
            from: Data(
                """
                {
                  "selectedFamily": "terrain",
                  "theme": "dark",
                  "activeTransportMode": "truck",
                  "activeProductSegment": "truck",
                  "guidancePhase": "guiding"
                }
                """.utf8
            )
        )
        XCTAssertFalse(decoded.hasActiveJob)
        XCTAssertNil(decoded.activeTransportMode)
        XCTAssertNil(decoded.activeProductSegment)
        XCTAssertEqual(decoded.guidancePhase, .inactive)
        XCTAssertNil(decoded.currentStyle)
    }

    func testLiveOperationsAndModeMarkersCarryNonColorTruth() {
        let status = HereLiveOperationsStatus(
            availability: .stale,
            sourceLabel: "  AIS  ",
            freshnessLabel: "18 min old",
            detail: "  Authorized vessel position  ",
            observationCount: 1
        )
        let marker = HereMarker(
            at: .init(33.7, -118.2),
            kind: .vessel,
            label: "IMO 1234567",
            id: "1234567",
            observationState: .stale,
            sourceLabel: "AIS",
            accessibilityLabel: "Vessel IMO 1234567, stale AIS position"
        )

        XCTAssertEqual(status.sourceLabel, "AIS")
        XCTAssertEqual(status.detail, "Authorized vessel position")
        XCTAssertEqual(marker.kind, .vessel)
        XCTAssertEqual(marker.observationState, .stale)
        XCTAssertEqual(marker.accessibilityLabel, "Vessel IMO 1234567, stale AIS position")

        let unclassifiedRail = HereMarker(at: .init(41.8, -87.6), kind: .rail)
        XCTAssertEqual(
            unclassifiedRail.observationState,
            .degraded,
            "A live mode marker without caller freshness must not claim current"
        )
    }

    func testLegacyModeMarkerDecodeDoesNotInventCurrentFreshness() throws {
        let rail = try JSONDecoder().decode(
            HereMarker.self,
            from: Data(#"{"at":{"lat":41.8,"lng":-87.6},"kind":"rail"}"#.utf8)
        )
        let pickup = try JSONDecoder().decode(
            HereMarker.self,
            from: Data(#"{"at":{"lat":41.8,"lng":-87.6},"kind":"pickup"}"#.utf8)
        )

        XCTAssertEqual(rail.observationState, .degraded)
        XCTAssertEqual(pickup.observationState, .current)
    }

    private func resolve(_ context: EusoTripMapModeContext) -> EusoTripMapStyleResolution {
        EusoTripMapStyleRegistry.resolve(
            context: context,
            family: .operational,
            theme: .light
        )
    }
}
