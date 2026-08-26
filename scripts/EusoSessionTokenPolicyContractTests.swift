import Foundation

private enum ContractFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ContractFailure.failed(message) }
}

private func jwt(expiration: TimeInterval) throws -> String {
    let payload = try JSONSerialization.data(withJSONObject: ["exp": expiration])
    let encoded = payload.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(encoded).signature"
}

@main
private struct EusoSessionTokenPolicyContractTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        let fresh = try jwt(expiration: now.addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970)
        try require(!EusoSessionTokenPolicy.shouldRenew(fresh, now: now),
                    "a freshly issued seven-day token must not renew immediately")

        let dayOld = try jwt(expiration: now.addingTimeInterval(6 * 24 * 60 * 60).timeIntervalSince1970)
        try require(EusoSessionTokenPolicy.shouldRenew(dayOld, now: now),
                    "a one-day-old access token must enter the renewal window")

        let expired = try jwt(expiration: now.addingTimeInterval(-1).timeIntervalSince1970)
        try require(EusoSessionTokenPolicy.shouldRenew(expired, now: now),
                    "an expired token must request authoritative renewal")
        try require(EusoSessionTokenPolicy.shouldRenew("opaque-credential", now: now),
                    "an unknown credential format must renew conservatively")

        var gate = EusoSessionReturnGate()
        try require(!gate.consumeTransition(isBackground: true, isActive: false),
                    "entering background must only arm the gate")
        try require(!gate.consumeTransition(isBackground: false, isActive: false),
                    "the intermediate inactive phase must preserve the gate")
        try require(gate.consumeTransition(isBackground: false, isActive: true),
                    "background -> inactive -> active must revalidate")
        try require(!gate.consumeTransition(isBackground: false, isActive: true),
                    "an active-only transition must not duplicate renewal")

        print("PASS: token renewal and foreground return contracts")
    }
}
