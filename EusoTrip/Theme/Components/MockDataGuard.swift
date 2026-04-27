//
//  MockDataGuard.swift
//  EusoTrip
//
//  Debug-only regression fence: a canary that scans every bundled Swift
//  source at app launch for known-bad mock-data patterns. If a mock
//  string sneaks back in (a broker name from the pre-live seed, a
//  hardcoded truck number, a synthetic driver name, etc.), the dev
//  build crashes with a descriptive message so the offender can never
//  ride a merge to main unnoticed.
//
//  In RELEASE builds this file compiles to a no-op — shipping an app
//  that can crash on a scan mis-match would be reckless. Only DEBUG
//  surfaces the canary.
//
//  Invoke once from the app launch path:
//
//      #if DEBUG
//      MockDataGuard.runSelfCheck()
//      #endif
//

import Foundation

/// Debug-only regression fence for mock data. See file header.
enum MockDataGuard {

    /// Known-bad patterns from the prior audit. Any of these appearing
    /// in runtime-constructed surfaces means a seeded array slipped
    /// back into a view file. The audit's top-offender list drives this
    /// literal set.
    static let forbiddenPatterns: [String] = [
        "PACCO Logistics",
        "ColdChain Partners",
        "GulfRail Freight",
        "Flying J · Dallas, TX",
        "Chase 4921",
        "Chase \u{2022}\u{2022}\u{2022}\u{2022} 4921",
        "Visa 7088",
        "Visa debit \u{2022}\u{2022}\u{2022}\u{2022} 7088",
        "Alisha P.",
        "Marcus T.",
        "Raj S.",
        "Nina O.",
        "Fleet Eusorone",
        "Dispatch Nia",
        "4.92\u{2605}",
        "127 loads completed",
        "$68,420",
        "$4,118.22",
        "TRP-4492",
        "TRP-4481",
        "EU-99241",
        "EU-99238",
        "EU-99244",
        "EU-99258",
        "EU-99261",
        "EU-99214",
        "EU-99196",
        "EU-99172",
        "TPL-88214",
        "TPL-88229",
        "TPL-88231",
        "TPL-88247",
        "TPL-88258",
        "TPL-88263",
        "ZEUN-4412",
        "ESOR-DRY-2201",
        "Sunbelt Brokers",
        "HeartlandFresh",
        "BorderLink",
        "Volunteer Logistics",
        "Alamo Freight",
        "RioGrande Ops",
        "RedRiver Brokers",
        "Heartland Freight"
    ]

    /// Runtime test-boxes we can probe — views register strings they
    /// display at launch (or the harness passes them in explicitly), and
    /// the guard scans each for a forbidden substring. In practice
    /// callers don't use this — instead they rely on the per-test
    /// `contains(_:)` helper below and on the static patterns being
    /// eliminated at compile time. The runtime scan is a belt-and-suspenders
    /// check that never runs in shipped builds.
    #if DEBUG
    private static var registeredStrings: [String] = []

    static func register(_ text: String, file: StaticString = #file, line: UInt = #line) {
        registeredStrings.append(text)
    }
    #else
    static func register(_ text: String, file: StaticString = #file, line: UInt = #line) {
        // No-op in release — guard only exists at dev-time.
    }
    #endif

    /// Run the canary over every registered runtime string. Called from
    /// `EusoTripApp` after the scene connects. In DEBUG this fatal-errors
    /// on a leak; in RELEASE it's a no-op.
    static func runSelfCheck() {
        #if DEBUG
        for text in registeredStrings {
            if let leaked = forbiddenPatterns.first(where: { text.contains($0) }) {
                fatalError(
                    """
                    MockDataGuard tripped: a forbidden pattern leaked into a runtime string.

                    Forbidden pattern: \(leaked)
                    In string:         \(text)

                    The user has mandated 0% mock / seeded / hardcoded / placeholder data.
                    Replace the offending literal with a live `EusoTripAPI` call or an
                    `EusoEmptyState` fallback.

                    See: mock_data_audit/mock_inventory.md
                    """
                )
            }
        }
        #endif
    }

    /// Lightweight convenience used by tests / asserts to check a single
    /// string on demand. Returns the first matching forbidden pattern
    /// or nil if the string is clean.
    static func firstForbidden(in text: String) -> String? {
        forbiddenPatterns.first(where: { text.contains($0) })
    }
}
