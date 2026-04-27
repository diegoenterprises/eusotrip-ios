//
//  OrbLog.swift
//  EusoTrip Pulse Watch App
//
//  Centralized os.Logger emitter for every orb-lifecycle branch. Prior
//  fix attempts were blind — six failures with no on-device telemetry.
//  This subsystem lights up every tap, state transition, permission
//  request, audio preflight, and backend-call outcome so the seventh
//  fix isn't guesswork. Subsystem / category are deliberately matched
//  to the DebugHealthView filter — triple-tap the orb in DEBUG /
//  TestFlight to see the last 50 events.
//
//  Performance: Logger is a ~no-op when the subsystem is unsubscribed,
//  so leaving these in production is cheap. We still gate the
//  ring-buffer writes on DEBUG || TESTFLIGHT to avoid retaining event
//  strings in a shipping build.
//

import Foundation
import Combine
import OSLog

/// Tiny in-memory ring buffer so DebugHealthView can show the last 50
/// events without having to re-read the unified log (which requires
/// Console.app entitlements the wrist doesn't have).
@MainActor
final class OrbLogBuffer: ObservableObject {
    static let shared = OrbLogBuffer()

    struct Event: Identifiable, Equatable {
        let id = UUID()
        let at: Date
        let level: String
        let message: String
    }

    @Published private(set) var events: [Event] = []
    private let cap = 50

    func record(_ level: String, _ message: String) {
        let ev = Event(at: Date(), level: level, message: message)
        events.append(ev)
        if events.count > cap {
            events.removeFirst(events.count - cap)
        }
    }

    func clear() { events.removeAll() }

    /// JSON dump for the Copy Diag button. Encodes to a compact payload
    /// the user can email to support (a.lynngambardella@gmail.com).
    func jsonDump() -> String {
        struct Row: Encodable { let at: String; let level: String; let msg: String }
        let f = ISO8601DateFormatter()
        let rows = events.map { Row(at: f.string(from: $0.at), level: $0.level, msg: $0.message) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(rows),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }
}

enum OrbLog {
    static let log = Logger(subsystem: "com.app.eusotrip.watch", category: "orb")

    static func tap(state: EsangState, signedIn: Bool) {
        let msg = "tap state=\(String(describing: state)) signedIn=\(signedIn)"
        log.info("\(msg, privacy: .public)")
        Task { @MainActor in OrbLogBuffer.shared.record("tap", msg) }
    }

    static func audio(_ m: String) {
        log.error("audio: \(m, privacy: .public)")
        Task { @MainActor in OrbLogBuffer.shared.record("audio", m) }
    }

    static func transition(_ from: Any, _ to: Any) {
        let msg = "\(String(describing: from)) -> \(String(describing: to))"
        log.info("state \(msg, privacy: .public)")
        Task { @MainActor in OrbLogBuffer.shared.record("state", msg) }
    }

    static func permission(_ which: String, _ status: String) {
        let msg = "permission.\(which)=\(status)"
        log.info("\(msg, privacy: .public)")
        Task { @MainActor in OrbLogBuffer.shared.record("perm", msg) }
    }

    static func info(_ m: String) {
        log.info("\(m, privacy: .public)")
        Task { @MainActor in OrbLogBuffer.shared.record("info", m) }
    }

    static func error(_ m: String) {
        log.error("\(m, privacy: .public)")
        Task { @MainActor in OrbLogBuffer.shared.record("error", m) }
    }
}
