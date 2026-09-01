import XCTest
@testable import EusoTrip

final class HereNavigationVoicePolicyTests: XCTestCase {
    func testProductionInitializerNormalizesApprovedLocale() throws {
        let policy = try HereNavigationVoicePolicy(
            requiredLocaleIdentifier: "en-us"
        )

        XCTAssertEqual(
            policy,
            .required(localeIdentifier: "en-US")
        )
    }

    func testProductionInitializerRejectsUnprovedLocale() {
        XCTAssertThrowsError(
            try HereNavigationVoicePolicy(
                requiredLocaleIdentifier: "es-MX"
            )
        )
    }
}
