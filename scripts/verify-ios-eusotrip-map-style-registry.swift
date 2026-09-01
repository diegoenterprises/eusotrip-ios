import Foundation

@main
enum VerifyIOSMapStyleRegistry {
    static func main() {
        let expected: [String: String] = [
            "truck.operational.light": "0e0daa28c29a30265110ad7d2118282bd8682749f731b7e353a15270b05be4e9",
            "truck.operational.dark": "0dcb8f283a5909e2adebd2efb0ae78bdce06bdce1e997e048afdf3942cbcbc5f",
            "truck.navigation.light": "1d2e00035d5cad84a98c01c46607a9ff7893b3dbf40b01566912f22a245c5049",
            "truck.navigation.dark": "c3eb666c3005fae5a993018711d7f17e913b6fda73feba1d4afb1b289ab9a7d0",
            "truck.terrain.light": "5f0750dcb9df68286061eda3717c91cff705393dc287373f6016a9fc0f606570",
            "truck.terrain.dark": "8310cd9650fd5ded478d691c6f04fcf6eda339a5491fa1ab7f0b993cc69d06a3",
            "rail.operational.light": "4ebe23dd22a07f70e5d8fb0e3e0a732301c964c2983cc9dfdb33703ce2d79c26",
            "rail.operational.dark": "3191c6fb622bc50d015c6d7e843852772ca02c5ecd8ed775e7bdb8573bb0755a",
            "rail.navigation.light": "814b865b89adb471d7d0d8a34ea84a83febb446821f1d3edddbe2ffa15514260",
            "rail.navigation.dark": "a1d76902ed27bc3b0c426497dcc6ec536c9f9bcb8daba7192bac0d6e1f0b377a",
            "rail.terrain.light": "0473802d19e61454e90eaf310669f6eb4522e51548f7a364de8bb0cce4e1582e",
            "rail.terrain.dark": "48dc593b66f8b766a4fcd3984e69ec9c1ba030d3fff37b9f812410aa4607c310",
            "vessel.operational.light": "0e0436786d01f57743a98791f345e7829279fb55c75e0e944aa876d0154a8b38",
            "vessel.operational.dark": "d0ce7eb53d2b4430597427037cc57fd0c448a26047d100815cb0e50c9650c8c2",
            "vessel.navigation.light": "532421f2e5d2e2944cc8b2242321b1d32a8a8bfd6874a76a2f903b9d7ef64ab9",
            "vessel.navigation.dark": "4208d28c989f7aa68f793cc88fbc87d89cd3824235d5600008e95044335290db",
            "vessel.terrain.light": "0d77a28db8884128b6d34835778538d9d7922bd684c63c695421de5e2af36ff5",
            "vessel.terrain.dark": "dbf03e0f1261e7fcad5ff9e6244971957a251a9fd6bd4f35bcd0ef8e8fad3e19",
        ]
        let catalog = EusoTripMapStyleRegistry.allStyles
        let actual = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0.artifactSHA256) })

        precondition(catalog.count == 18, "Expected exactly 18 product styles")
        precondition(Set(catalog.map(\.id)).count == 18, "Style keys must be unique")
        precondition(Set(catalog.map(\.artifactSHA256)).count == 18, "Hashes must be unique")
        precondition(actual == expected, "Native hashes drifted from generated manifest")
        precondition(catalog.allSatisfy {
            $0.styleOverrideCount == 282
                && $0.visualReviewState == .pending
                && !$0.isProductionEligible
                && $0.artifactPath.contains($0.artifactSHA256)
        }, "Artifact evidence or pending-review gate drifted")
        precondition(
            EusoTripMapIdentityContract.routeGradientStops == ["#1473FF", "#813FF5", "#BE01FF"],
            "Owned route direction drifted"
        )

        precondition(
            EusoTripMapStyleRegistry.resolve(
                context: .barge(activeVesselProduct: false),
                family: .operational,
                theme: .light
            ).unavailableReason == .bargeRequiresActiveVesselProduct,
            "Unconfirmed Barge must fail closed"
        )
        precondition(
            EusoTripMapStyleRegistry.resolve(
                context: .escort(activeRoadEscort: false),
                family: .operational,
                theme: .light
            ).unavailableReason == .escortRequiresActiveRoadProduct,
            "Unconfirmed Escort must fail closed"
        )
        precondition(
            EusoTripMapStyleRegistry.resolve(
                context: .intermodal(activeSegment: nil),
                family: .operational,
                theme: .light
            ).unavailableReason == .intermodalRequiresActiveSegment,
            "Intermodal without an active segment must fail closed"
        )
        precondition(
            EusoTripMapStyleRegistry.resolve(
                context: .unknown,
                family: .operational,
                theme: .light
            ).unavailableReason == .unknownTransportMode,
            "Unknown mode must fail closed"
        )

        var selection = EusoTripMapSelectionState(
            selectedFamily: .operational,
            theme: .dark
        )
        selection.beginActiveJob(
            id: "rail-job",
            transportMode: .rail,
            guidancePhase: .guiding
        )
        precondition(
            selection.selectedFamily == .operational
                && selection.recommendedFamily == .navigation,
            "Active work may recommend Navigation but must not overwrite the family choice"
        )
        selection.selectFamily(.terrain)
        precondition(
            selection.currentStyle?.id == "rail.terrain.dark"
                && selection.guidancePhase == .guiding,
            "Manual family selection must win without interrupting guidance"
        )

        print("PASS: 18 native map styles, exact hashes, pending review, fail-closed aliases, manual family precedence, owned route order")
    }
}
