//
//  WatchESangGreeting.swift
//  EusoTrip Watch App
//
//  Seeded per-launch rotating greeting that matches the iOS app's
//  `ESangGreeting` spirit — warm, context-aware copy, never the same
//  line twice in a row. On the wrist it's compressed to 1-2 short
//  sentences so it fits in the bottom of HomeView.
//

import Foundation

enum WatchDayPart {
    case earlyMorning, morning, afternoon, evening, night

    static var current: WatchDayPart {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 4..<7:   return .earlyMorning
        case 7..<12:  return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default:      return .night
        }
    }
}

enum WatchESangGreeting {
    private static let variants: [WatchDayPart: [String]] = [
        .earlyMorning: [
            "Quiet start. Here with you.",
            "Eyes sharp. Mug warm?",
            "Early wheels. You got this.",
            "Morning star's still out — ready."
        ],
        .morning: [
            "Let's make it count today.",
            "Fresh mile, fresh intentions.",
            "I'm right here — ask anything.",
            "Good morning, driver."
        ],
        .afternoon: [
            "Midday check — one call away.",
            "Halfway through. Strong work.",
            "Holding the line with you.",
            "Afternoon shift, full signal."
        ],
        .evening: [
            "Sunset crew. Proud of you.",
            "Almost home. I'll watch the dash.",
            "You logged the hours — let's finish it.",
            "Evening miles. I've got eyes."
        ],
        .night: [
            "I'm here on the night shift too.",
            "Quiet road. I'll stay close.",
            "Late run — rest when you need.",
            "Moon's up. So am I."
        ]
    ]

    static func pick() -> String {
        let part = WatchDayPart.current
        let bucket = variants[part] ?? ["Here with you."]
        // Seed from (user id if available) + (hour) so the wrist doesn't
        // flicker between lines on every back-press — one line per
        // half-hour block.
        let seed = UInt64(Date().timeIntervalSince1970 / (60 * 30))
        var g = SplitMix(seed: seed)
        let idx = Int(g.next() % UInt64(bucket.count))
        return bucket[idx]
    }
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { self.state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        var z = (state &+ 0x9E3779B97F4A7C15)
        state = z
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
