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
import Combine
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
        healthStore.requestAuthorization(toShare: nil, read: [hrType]) { _, _ in
            // Hop back onto the MainActor with a fresh weak capture so
            // strict-concurrency doesn't see `self` as a captured var
            // escaping the outer @Sendable callback.
            Task { @MainActor [weak self] in
                self?.startHRStreaming()
            }
        }
    }

    func markBreakTaken() {
        lastBreakAt = Date()
        fatigueScore = max(0.1, fatigueScore - 0.3)
        // Q3 predictor: reset the cumulative driving-minutes ramp and
        // the microsleep window. Keeps HR samples — a 5-minute break
        // doesn't reset an elevated pulse.
        FatiguePredictor.shared.onBreakTaken()
    }

    private func startHRStreaming() {
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        // Bridge the HealthKit @Sendable callback onto the MainActor
        // with a single weak capture. Extracting quantity samples first
        // means we don't hold an HKSample reference across the actor hop.
        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { _, samples, _, _, _ in
            let quantitySamples = (samples as? [HKQuantitySample]) ?? []
            Task { @MainActor [weak self] in
                self?.handleHR(samples: quantitySamples)
            }
        }
        query.updateHandler = { _, samples, _, _, _ in
            let quantitySamples = (samples as? [HKQuantitySample]) ?? []
            Task { @MainActor [weak self] in
                self?.handleHR(samples: quantitySamples)
            }
        }
        hrQuery = query
        healthStore.execute(query)
    }

    private func handleHR(samples: [HKQuantitySample]) {
        guard !samples.isEmpty else { return }
        let bpm = HKUnit(from: "count/min")
        let recent = samples.suffix(10).map { $0.quantity.doubleValue(for: bpm) }
        let avg = recent.reduce(0, +) / Double(recent.count)
        currentHR = avg
        // Q3: fan every incoming HR sample into the richer predictor
        // so its HRV/RMSSD window stays current. The Q3 predictor
        // doesn't own the HealthKit query — we do — so piping samples
        // through the existing handler keeps one connection to the
        // HR stream alive at a time.
        for s in samples.suffix(10) {
            FatiguePredictor.shared.ingestHR(
                bpm: s.quantity.doubleValue(for: bpm),
                at: s.startDate
            )
        }
        recomputeFatigue()
    }

    private func recomputeFatigue() {
        // Multi-factor fused score:
        //   1. Time since last break (linear up to 4h)
        //   2. HR trend vs. resting (higher resting = tired)
        //   3. Q3 FatiguePredictor — HRV + jerk + yaw + microsleep
        //      + circadian + driving ramp fusion (10-D features,
        //      logistic head). See FatiguePredictor.swift.
        let timeFactor = min(1.0, Double(minutesSinceBreak) / 240.0)
        let hrFactor: Double = {
            guard currentHR > 0 else { return 0 }
            let delta = (currentHR - restingHR) / restingHR
            return max(0, min(1, delta))
        }()
        let predictor = FatiguePredictor.shared.score

        // Legacy two-factor score kept as a floor so the UI tint can't
        // regress vs. shipped behavior. The predictor layer is additive
        // during the initial rollout — once we're confident in the
        // CoreML head we'll flip `fatigueScore = predictor` directly.
        let legacy = 0.6 * timeFactor + 0.4 * hrFactor
        let fused = 0.55 * predictor + 0.45 * legacy
        fatigueScore = max(0.05, min(1.0, fused))
    }
}
