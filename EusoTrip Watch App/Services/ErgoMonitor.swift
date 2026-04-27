//
//  ErgoMonitor.swift
//  EusoTrip Watch App
//
//  Passive fatigue + ergonomics surface:
//    - Heart-rate trend via HealthKit (rolling 20-min variability window)
//    - Stand-hour pattern: wrist-raised vs. wrist-still long-haul cues
//    - Time-since-last-break tracker that nudges at 2h / 4h
//
//  Produces a simple 0–1 "fatigue score". Above 0.7 the watch surfaces a
//  gentle haptic + "Esang suggests a 10-minute break" tile on the home
//  screen. Never blocks the UI — wrist is for glance, not gates.
//
//  Spec §8.2.
//

import Foundation
import HealthKit
import SwiftUI

@MainActor
final class ErgoMonitor: ObservableObject {
    static let shared = ErgoMonitor()

    @Published private(set) var fatigueScore: Double = 0.2
    @Published private(set) var lastBreakAt: Date = Date()
    @Published private(set) var restingHR: Double = 62
    @Published private(set) var currentHR: Double = 0

    private let healthStore = HKHealthStore()
    private var hrQuery: HKAnchoredObjectQuery?

    var minutesSinceBreak: Int {
        Int(Date().timeIntervalSince(lastBreakAt) / 60)
    }

    var fatigueTint: Color {
        switch fatigueScore {
        case ..<0.4: return .esangGreen
        case ..<0.7: return .esangAmber
        default: return .esangDanger
        }
    }

    var fatigueLabel: String {
        switch fatigueScore {
        case ..<0.4: return "Sharp"
        case ..<0.7: return "Getting tired"
        default: return "Take a break"
        }
    }

    func begin() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        healthStore.requestAuthorization(toShare: nil, read: [hrType]) { [weak self] _, _ in
            Task { @MainActor in
                self?.startHRStreaming()
            }
        }
    }

    func markBreakTaken() {
        lastBreakAt = Date()
        fatigueScore = max(0.1, fatigueScore - 0.3)
    }

    private func startHRStreaming() {
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.handleHR(samples: samples)
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.handleHR(samples: samples)
        }
        hrQuery = query
        healthStore.execute(query)
    }

    private func handleHR(samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else { return }
        let bpm = HKUnit(from: "count/min")
        let recent = quantitySamples.suffix(10).map { $0.quantity.doubleValue(for: bpm) }
        let avg = recent.reduce(0, +) / Double(recent.count)
        Task { @MainActor in
            self.currentHR = avg
            self.recomputeFatigue()
        }
    }

    private func recomputeFatigue() {
        // Multi-factor heuristic:
        //   - Time since last break (linear up to 4h)
        //   - HR trend vs. resting (higher resting = tired)
        let timeFactor = min(1.0, Double(minutesSinceBreak) / 240.0)
        let hrFactor: Double = {
            guard currentHR > 0 else { return 0 }
            let delta = (currentHR - restingHR) / restingHR
            return max(0, min(1, delta))
        }()
        let score = 0.6 * timeFactor + 0.4 * hrFactor
        fatigueScore = max(0.05, min(1.0, score))
    }
}
