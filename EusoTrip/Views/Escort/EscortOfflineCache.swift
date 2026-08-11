//
//  EscortOfflineCache.swift
//  EusoTrip 2027 — Escort role · minimal READ_CACHED tier (Offline Mode Encyclopedia v2)
//
//  The phone app's Unified Outbox is Driver-only today; the Escort role has no queue
//  lanes yet (PLANNED). Until the outbox ports, Escort screens that declare
//  READ_CACHED(ttl) honor the honesty law with this shim: last-good JSON snapshot
//  on disk, an explicit staleness line, and a hard ttl beyond which the screen
//  must show its offline state rather than stale numbers presented as live.
//  Mutations on Escort screens stay ONLINE_ONLY until the outbox arrives —
//  never fake a queue.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import Foundation

/// Disk-backed last-good cache for Escort read models. One file per key under
/// Caches/escort-cache/. Values are Codable snapshots with a captured-at stamp.
struct EscortOfflineCache {

    struct Envelope<T: Codable>: Codable {
        let capturedAt: Date
        let value: T
    }

    static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("escort-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func store<T: Codable>(_ value: T, key: String) {
        let env = Envelope(capturedAt: Date(), value: value)
        guard let data = try? JSONEncoder().encode(env) else { return }
        try? data.write(to: directory.appendingPathComponent("\(key).json"), options: .atomic)
    }

    /// Returns the snapshot and its age if present and within ttl; nil otherwise.
    static func load<T: Codable>(_ type: T.Type, key: String, ttl: TimeInterval) -> (value: T, age: TimeInterval)? {
        let url = directory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url),
              let env = try? JSONDecoder().decode(Envelope<T>.self, from: data) else { return nil }
        let age = Date().timeIntervalSince(env.capturedAt)
        guard age <= ttl else { return nil }
        return (env.value, age)
    }

    /// Honesty-law staleness line: "cached · 4 min ago". Callers render this
    /// visibly whenever they are painting a snapshot instead of a live read.
    static func stalenessLine(age: TimeInterval) -> String {
        let mins = Int(age / 60)
        if mins < 1 { return "cached · just now" }
        if mins == 1 { return "cached · 1 min ago" }
        if mins < 60 { return "cached · \(mins) min ago" }
        let hrs = mins / 60
        return "cached · \(hrs) hr\(hrs == 1 ? "" : "s") ago"
    }
}
