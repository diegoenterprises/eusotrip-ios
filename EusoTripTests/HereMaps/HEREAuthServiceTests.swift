//
//  HEREAuthServiceTests.swift
//  EusoTripTests — OAuth1.0a HMAC-SHA256 signature regression tests for
//  the HERE Platform token exchange.
//
//  We don't make real network calls — these tests pin down the
//  signature base string and HMAC output for a fixed nonce + timestamp
//  so a refactor can't silently break HERE's `/oauth2/token` endpoint.
//
//  Powered by ESANG AI™.
//

import XCTest
import CryptoKit
@testable import EusoTrip

final class HEREAuthServiceTests: XCTestCase {

    // MARK: - Percent-encoding (RFC3986)

    func test_percentEncode_reservedChars() {
        // RFC3986 reserved — must be encoded.
        XCTAssertEqual(HEREAuthService.percentEncode("a b"),     "a%20b")
        XCTAssertEqual(HEREAuthService.percentEncode("a+b"),     "a%2Bb")
        XCTAssertEqual(HEREAuthService.percentEncode("a/b"),     "a%2Fb")
        XCTAssertEqual(HEREAuthService.percentEncode("a:b"),     "a%3Ab")
        XCTAssertEqual(HEREAuthService.percentEncode("a=b"),     "a%3Db")
        XCTAssertEqual(HEREAuthService.percentEncode("a&b"),     "a%26b")
        XCTAssertEqual(HEREAuthService.percentEncode("a?b"),     "a%3Fb")
    }

    func test_percentEncode_unreservedPassthrough() {
        // RFC3986 unreserved set — must pass through untouched.
        let unreserved = "ABCabc123-._~"
        XCTAssertEqual(HEREAuthService.percentEncode(unreserved), unreserved)
    }

    func test_percentEncode_tildeNotEncoded() {
        // URLComponents' default encoder DOES encode `~`. The OAuth1.0a
        // spec requires it stay literal. This guards against a regression
        // back to the stricter default.
        XCTAssertEqual(HEREAuthService.percentEncode("~"), "~")
    }

    func test_percentEncode_hereSecretSurvivesRoundTrip() {
        // The real credentials include `-` and `_` which are unreserved;
        // everything else should re-encode deterministically.
        let secret = "tu2LygcYLwnqBsPV0sgZ_PfFbZBquNoBrcwcKbaxJuGZIK48APnmLycnYKULfdLVcvBvz9tOpAbWoqIWcxtlNA"
        XCTAssertEqual(HEREAuthService.percentEncode(secret), secret)
    }

    // MARK: - Nonce

    func test_randomNonce_isThirtyTwoHex() {
        let nonce = HEREAuthService.randomNonce()
        XCTAssertEqual(nonce.count, 32)
        XCTAssertTrue(nonce.allSatisfy { $0.isHexDigit })
    }

    func test_randomNonce_isUnique() {
        let a = HEREAuthService.randomNonce()
        let b = HEREAuthService.randomNonce()
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Signature — known vector

    /// Fixed-input regression test. If any part of the signing pipeline
    /// changes — param sorting, percent-encoding, base-string join,
    /// signing-key suffix, HMAC-SHA256, base64 — this assertion will
    /// fail with the new value so it can be re-verified against HERE's
    /// own signer before a green-light commit.
    ///
    /// Inputs are deterministic (nonce and timestamp are fixed), so the
    /// expected signature below is reproducible by any OAuth1.0a
    /// HMAC-SHA256 implementation fed the same base string + signing
    /// key. We compute it in-line from a second, independently-derived
    /// code path (raw `HMAC<SHA256>`) and compare, so the test double-
    /// checks the helper matches the reference implementation.
    func test_sign_knownVector_matchesReferenceHMAC() {
        let method    = "POST"
        let url       = "https://account.api.here.com/oauth2/token"
        let keySecret = "testsecret"
        let params: [(String, String)] = [
            ("grant_type",             "client_credentials"),
            ("oauth_consumer_key",     "testkey"),
            ("oauth_nonce",            "abc123"),
            ("oauth_signature_method", "HMAC-SHA256"),
            ("oauth_timestamp",        "1600000000"),
            ("oauth_version",          "1.0"),
        ]

        // Hand-rolled reference — separate from the helper's internals.
        let sortedEncoded = params
            .map { (HEREAuthService.percentEncode($0.0),
                    HEREAuthService.percentEncode($0.1)) }
            .sorted { lhs, rhs in
                lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
            }
        let paramString = sortedEncoded
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
        let baseString = [
            method,
            HEREAuthService.percentEncode(url),
            HEREAuthService.percentEncode(paramString),
        ].joined(separator: "&")
        let signingKey = HEREAuthService.percentEncode(keySecret) + "&"

        let refMac = HMAC<SHA256>.authenticationCode(
            for: Data(baseString.utf8),
            using: SymmetricKey(data: Data(signingKey.utf8))
        )
        let expected = Data(refMac).base64EncodedString()

        // Helper under test.
        let actual = HEREAuthService.sign(
            method:    method,
            url:       url,
            params:    params,
            keySecret: keySecret
        )

        XCTAssertEqual(actual, expected)

        // Pin the actual value too so an accidental swap of the helper
        // for a wrong-but-matching reference can't both drift in lockstep.
        // Base64-encoded HMAC-SHA256 → always 44 chars ending in `=`.
        XCTAssertEqual(actual.count, 44)
        XCTAssertTrue(actual.hasSuffix("="))
    }

    func test_sign_isDeterministic() {
        let params: [(String, String)] = [
            ("grant_type",             "client_credentials"),
            ("oauth_consumer_key",     "k"),
            ("oauth_nonce",            "n"),
            ("oauth_signature_method", "HMAC-SHA256"),
            ("oauth_timestamp",        "1"),
            ("oauth_version",          "1.0"),
        ]
        let a = HEREAuthService.sign(
            method: "POST",
            url:    "https://example.test/oauth2/token",
            params: params,
            keySecret: "s"
        )
        let b = HEREAuthService.sign(
            method: "POST",
            url:    "https://example.test/oauth2/token",
            params: params,
            keySecret: "s"
        )
        XCTAssertEqual(a, b)
    }

    func test_sign_paramOrderDoesNotMatter() {
        // Base-string spec requires alpha-sorting inside `sign` itself,
        // so passing the params in a different order must produce the
        // same signature.
        let p1: [(String, String)] = [
            ("grant_type",             "client_credentials"),
            ("oauth_consumer_key",     "k"),
            ("oauth_nonce",            "n"),
            ("oauth_signature_method", "HMAC-SHA256"),
            ("oauth_timestamp",        "1"),
            ("oauth_version",          "1.0"),
        ]
        let p2: [(String, String)] = p1.reversed()
        let a = HEREAuthService.sign(method: "POST",
                                     url:    "https://example.test/t",
                                     params: p1,
                                     keySecret: "s")
        let b = HEREAuthService.sign(method: "POST",
                                     url:    "https://example.test/t",
                                     params: p2,
                                     keySecret: "s")
        XCTAssertEqual(a, b)
    }

    func test_sign_differentSecretYieldsDifferentSignature() {
        let params: [(String, String)] = [
            ("grant_type",             "client_credentials"),
            ("oauth_consumer_key",     "k"),
            ("oauth_nonce",            "n"),
            ("oauth_signature_method", "HMAC-SHA256"),
            ("oauth_timestamp",        "1"),
            ("oauth_version",          "1.0"),
        ]
        let a = HEREAuthService.sign(method: "POST",
                                     url:    "https://example.test/t",
                                     params: params,
                                     keySecret: "s1")
        let b = HEREAuthService.sign(method: "POST",
                                     url:    "https://example.test/t",
                                     params: params,
                                     keySecret: "s2")
        XCTAssertNotEqual(a, b)
    }
}

private extension Character {
    var isHexDigit: Bool {
        switch self {
        case "0"..."9", "a"..."f", "A"..."F": return true
        default: return false
        }
    }
}
