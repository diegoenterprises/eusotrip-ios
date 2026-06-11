//
//  SVGPathParserTotalityTests.swift
//  EusoTripTests — termination ("totality") regression tests for the
//  native SVG path tokenizer loop (Emergency I4, 2026-06-10).
//
//  Root cause pinned: a number following Z/z triggered the implicit-repeat
//  branch with a command that consumes ZERO tokens, so the loop index never
//  advanced — an infinite loop on the main thread and the exact watchdog
//  kill (0x8badf00d) mechanism on the rail/vessel render path. These tests
//  feed the parser every malformed-trailing-token shape and assert it
//  terminates promptly AND returns the parsed prefix, never hanging.
//
//  Every parse runs on a background queue behind an XCTestExpectation with
//  a hard timeout, so a totality regression FAILS the test in seconds
//  instead of hanging the suite forever.
//

import XCTest
import SwiftUI
@testable import EusoTrip

final class SVGPathParserTotalityTests: XCTestCase {

    /// Hard ceiling for any single parse. The corpus parses in single-digit
    /// milliseconds; 2s is three orders of magnitude of headroom, so a
    /// timeout here can only mean a non-terminating loop.
    private let parseTimeout: TimeInterval = 2.0

    /// Runs the parser off the test thread and fails (instead of hanging)
    /// if it doesn't come back inside `parseTimeout`.
    @discardableResult
    private func parseWithTimeout(_ d: String,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) -> Path? {
        let done = expectation(description: "parse terminates: \(d)")
        var result: Path?
        DispatchQueue.global(qos: .userInitiated).async {
            result = SVGPathParser.path(from: d)
            done.fulfill()
        }
        wait(for: [done], timeout: parseTimeout)
        XCTAssertNotNil(result,
                        "parser did not terminate for d=\"\(d)\"",
                        file: file, line: line)
        return result
    }

    // MARK: - The founder-freeze shape: number after closepath

    func test_numberAfterLowercaseClosepath_terminates() {
        // The exact plan-acceptance input. Pre-fix this loops forever.
        parseWithTimeout("M0 0 L5 5 z 5 10")
    }

    func test_numberAfterUppercaseClosepath_terminates() {
        parseWithTimeout("M0 0 L5 5 Z 5 10")
    }

    func test_numberAfterClosepath_returnsParsedPrefix() {
        // The malformed tail must be DROPPED, not rendered and not looped:
        // the result is identical to the same path without the junk tokens.
        let malformed = parseWithTimeout("M0 0 L5 5 z 5 10")
        let clean = parseWithTimeout("M0 0 L5 5 z")
        XCTAssertEqual(malformed?.description, clean?.description,
                       "malformed tail after z must yield exactly the parsed prefix")
        XCTAssertEqual(malformed?.boundingRect, CGRect(x: 0, y: 0, width: 5, height: 5))
    }

    func test_multipleSubpaths_junkAfterMiddleClosepath_terminates() {
        // Junk after a mid-path closepath terminates with the prefix — the
        // following (well-formed) subpath is unreachable by design: the
        // grammar is broken at that point and honest rendering stops there.
        let p = parseWithTimeout("M0 0 L5 5 z 7 M10 10 L20 20 z")
        XCTAssertEqual(p?.boundingRect, CGRect(x: 0, y: 0, width: 5, height: 5))
    }

    // MARK: - Every command followed by trailing numbers (plan acceptance)

    func test_everyCommand_withTrailingDanglingNumbers_terminates() {
        // For each command: a valid use, then a deliberately incomplete
        // trailing argument pack. None of these may hang; all must return
        // the parsed prefix.
        let cases: [String] = [
            "M0 0 5",                       // M then dangling x
            "m0 0 5",
            "M0 0 L5 5 7",                  // L missing y
            "M0 0 l5 5 7",
            "M0 0 H5 ",                     // H is total (1 token each) — junk-free repeat
            "M0 0 V5 7 8 9",                // V repeats fine; odd counts still terminate
            "M0 0 C1 1 2 2 3 3 4",          // C missing 5 of 6
            "M0 0 c1 1 2 2 3 3 4 4 5",
            "M0 0 C1 1 2 2 3 3 S4 4 5",     // S missing y
            "M0 0 Q1 1 2 2 3",              // Q missing 3 of 4
            "M0 0 Q1 1 2 2 T3",             // T missing y
            "M0 0 A5 5 0 0 1 10 10 5 5 0",  // A missing 4 of 7 on repeat
            "M0 0 Z5",                      // closepath glued to a number
            "M0 0 z-3.5",
            "M0 0 L5 5 z .5",
            "M0 0 L5 5 Z 1e3",
        ]
        for d in cases {
            parseWithTimeout(d)
        }
    }

    // MARK: - Degenerate inputs

    func test_emptyAndWhitespaceInput_terminates() {
        XCTAssertEqual(parseWithTimeout("")?.isEmpty, true)
        XCTAssertEqual(parseWithTimeout("   \n\t ")?.isEmpty, true)
    }

    func test_numbersWithNoLeadingCommand_terminates() {
        // lastCmd is the " " sentinel — must break immediately, not spin.
        XCTAssertEqual(parseWithTimeout("5 10 20 30")?.isEmpty, true)
    }

    func test_garbageInput_terminates() {
        parseWithTimeout("not a path at all")
        parseWithTimeout("zzzzzz")
        parseWithTimeout("Z Z Z 1 2 3")
        parseWithTimeout("....----")
    }

    // MARK: - Well-formed paths still parse (no regression from the guard)

    func test_wellFormedPath_unchanged() {
        let p = parseWithTimeout("M0 0 L10 0 L10 10 L0 10 Z")
        XCTAssertEqual(p?.boundingRect, CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    func test_implicitRepeat_afterMoveTo_stillWorks() {
        // Per spec: numbers after M repeat as L. The guard must not break
        // legal implicit repeats.
        let implicit = parseWithTimeout("M0 0 10 0 10 10")
        let explicit = parseWithTimeout("M0 0 L10 0 L10 10")
        XCTAssertEqual(implicit?.description, explicit?.description)
    }

    func test_implicitRepeat_relativeLineTo_stillWorks() {
        let implicit = parseWithTimeout("m0 0 5 5 5 5")
        let explicit = parseWithTimeout("m0 0 l5 5 l5 5")
        XCTAssertEqual(implicit?.description, explicit?.description)
    }

    func test_closepathFollowedByExplicitCommand_stillWorks() {
        // Z followed by an EXPLICIT command is legal and must keep parsing.
        let p = parseWithTimeout("M0 0 L5 5 Z M10 10 L20 20")
        XCTAssertEqual(p?.boundingRect, CGRect(x: 0, y: 0, width: 20, height: 20))
    }
}
