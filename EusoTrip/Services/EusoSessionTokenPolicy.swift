//
//  EusoSessionTokenPolicy.swift
//  EusoTrip — deterministic session-renewal and scene-return policy.
//
//  The JWT payload is decoded only to schedule an authoritative server
//  renewal. It is never trusted as proof of identity, signature validity,
//  revocation state, account status, or permission.
//

import Foundation

enum EusoSessionTokenPolicy {
    /// The backend currently issues seven-day access JWTs. Renew after a
    /// token is one day old, leaving six full days of safety margin for an
    /// app that is opened intermittently. A shorter future server TTL also
    /// lands inside this window and renews immediately.
    static let renewalWindow: TimeInterval = 6 * 24 * 60 * 60

    /// Reads the unverified JWT `exp` claim for renewal scheduling only.
    /// Any malformed or non-JWT credential returns nil and is renewed
    /// conservatively through the real server contract.
    static func unverifiedExpiration(of token: String) -> Date? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let payload = decodeBase64URL(String(segments[1])),
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let rawExpiry = object["exp"]
        else { return nil }

        let seconds: TimeInterval?
        switch rawExpiry {
        case let value as NSNumber:
            seconds = value.doubleValue
        case let value as String:
            seconds = TimeInterval(value)
        default:
            seconds = nil
        }
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Unknown tokens renew; known tokens renew before their access window
    /// becomes narrow. The server still makes the authentication decision.
    static func shouldRenew(_ token: String, now: Date = Date()) -> Bool {
        guard let expiration = unverifiedExpiration(of: token) else { return true }
        return expiration.timeIntervalSince(now) <= renewalWindow
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        if padding > 0 {
            base64.append(String(repeating: "=", count: padding))
        }
        return Data(base64Encoded: base64)
    }
}

/// ScenePhase commonly returns from background as
/// `background -> inactive -> active`. Keeping an explicit marker avoids the
/// brittle `oldPhase == .background` comparison that misses that sequence.
struct EusoSessionReturnGate: Equatable {
    private(set) var hasEnteredBackground = false

    mutating func consumeTransition(isBackground: Bool, isActive: Bool) -> Bool {
        if isBackground {
            hasEnteredBackground = true
            return false
        }
        guard isActive, hasEnteredBackground else { return false }
        hasEnteredBackground = false
        return true
    }
}
