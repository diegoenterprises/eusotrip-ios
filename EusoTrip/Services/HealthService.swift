//
//  HealthService.swift
//  EusoTrip — Apple Health recovery metrics for screen 162 Driver Wellness & Fatigue.
//
//  Architecture:
//    The PHONE reads Apple-Watch-synced metrics directly from the SHARED
//    HealthKit store — there is NO custom watch channel. The Pulse Watch app
//    records nothing here; watchOS surfaces its samples into the system Health
//    store, the phone's HealthKit reads them. This service is the phone-side
//    reader.
//
//  Pipeline:
//    HKHealthStore (read auth: sleepAnalysis · restingHeartRate · HRV SDNN)
//      → most-recent MAIN sleep session (sum of 'asleep*' samples over ~36h)
//      → latest restingHeartRate (within ~7d, bpm)
//      → latest hrvSdnn (within ~7d, ms)
//      → HealthSnapshot (all metrics OPTIONAL — partial grants are honest)
//
//  Modeled on WeatherService.swift:
//    • `static let shared` singleton
//    • best-effort device-data source — returns nil rather than throwing
//    • @MainActor ObservableObject
//    • exposes `authorizationStatus` so the screen can render a
//      "Connect Apple Health" CTA (notDetermined → request; denied → Settings)
//
//  Requires:
//    • App-ID HealthKit capability (enabled by the founder 2026-06-20).
//    • com.apple.developer.healthkit entitlement (EusoTrip.entitlements).
//    • NSHealthShareUsageDescription in Info.plist (we only READ).
//
//  ZERO FABRICATION (0% mock doctrine): every metric stays nil when HealthKit
//  is unavailable, authorization wasn't granted, or no sample exists in the
//  window. A driver with no data scores EXACTLY as today (no bump). We NEVER
//  default a metric to 0 — a missing sample is honestly nil, not a fabricated
//  reading.
//

import Foundation
import HealthKit

// MARK: - Snapshot

/// A best-effort recovery snapshot read from the shared HealthKit store. Every
/// metric is OPTIONAL: a partial HealthKit grant (e.g. the driver allowed RHR
/// but not sleep) yields a snapshot with only the granted metrics populated —
/// the rest stay nil and render an honest em-dash. NEVER fabricated.
struct HealthSnapshot {
    /// Hours of the most-recent main sleep session (sum of 'asleep*' samples
    /// over the last ~36h). nil when sleep was not authorized / no session.
    let sleepHours: Double?
    /// Latest resting heart rate in whole bpm (within ~7d). DISPLAY/context
    /// only — does NOT bump the fatigue score. nil when none.
    let restingHeartRate: Int?
    /// Latest heart-rate variability (SDNN) in milliseconds (within ~7d).
    /// DISPLAY/context only — does NOT bump the fatigue score. nil when none.
    let hrvMs: Double?
    /// The freshest sample timestamp across the populated metrics, for the
    /// "as of" provenance line. nil when no metric was read.
    let asOf: Date?

    /// True when at least one metric came back real. The screen only fires the
    /// best-effort server submit + folds the sleep bump when this is true.
    var hasAnyData: Bool {
        sleepHours != nil || restingHeartRate != nil || hrvMs != nil
    }

    /// The SLEEP-driven fatigue bump — IDENTICAL to the server contract and the
    /// client fold: < 5h → +20, [5, 6) → +8, else 0. HRV + resting heart rate
    /// are context only and never bump. Guarded by the nil-check so a driver
    /// with no sleep data contributes exactly 0 (no fabrication). This mirrors
    /// `WeatherImpact162.bump` as the health analogue.
    var sleepBump: Int {
        guard let h = sleepHours else { return 0 }
        if h < 5 { return 20 }
        if h < 6 { return 8 }
        return 0
    }
}

// MARK: - Service

@MainActor
final class HealthService: NSObject, ObservableObject {

    static let shared = HealthService()

    private let store = HKHealthStore()

    override init() {
        super.init()
    }

    // MARK: - Read types

    /// The three READ types we request. All optional at runtime — a partial
    /// grant simply means the corresponding query returns nothing and the
    /// metric stays nil. We request READ only (no share/update), so
    /// NSHealthUpdateUsageDescription is not needed.
    private var sleepType: HKCategoryType? {
        HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
    }
    private var restingHRType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .restingHeartRate)
    }
    private var hrvType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
    }

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        if let sleepType { set.insert(sleepType) }
        if let restingHRType { set.insert(restingHRType) }
        if let hrvType { set.insert(hrvType) }
        return set
    }

    // MARK: - Exposed status (so the screen can show a "Connect Apple Health" CTA)

    /// Whether HealthKit data is available on this device at all (false on
    /// iPad, in some Simulators). When false the screen never offers the CTA.
    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// The current authorization status for SLEEP — the metric that actually
    /// drives the fatigue bump — so the screen can distinguish "never asked"
    /// (.notDetermined → fire `requestAuthorization()`) from "user said no"
    /// (.sharingDenied → deep-link to Settings) from "granted"
    /// (.sharingAuthorized).
    ///
    /// NOTE on HealthKit privacy: for READ authorization Apple deliberately
    /// reports `.sharingDenied` even when the user HAS granted read access
    /// (so apps can't probe what the user declined). We therefore treat
    /// `.notDetermined` as "show Connect CTA / request", and only ever read
    /// data through `fetchRecovery()` which returns honest nils. The CTA copy
    /// stays truthful either way — it never claims a grant we don't have.
    var authorizationStatus: HKAuthorizationStatus {
        guard isHealthDataAvailable, let sleepType else { return .notDetermined }
        return store.authorizationStatus(for: sleepType)
    }

    // MARK: - Authorization

    /// Fire the HealthKit "Allow EusoTrip to read…" sheet for the three read
    /// types. Returns true when the request completed without error (NOT a
    /// guarantee of grant — HealthKit hides read grants for privacy; the real
    /// signal is whether `fetchRecovery()` returns data). Returns false when
    /// HealthKit is unavailable or the request errored. Best-effort, never
    /// throws to the caller.
    func requestAuthorization() async -> Bool {
        guard isHealthDataAvailable, !readTypes.isEmpty else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            print("[HealthService] requestAuthorization failed — \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Public read

    /// Read a best-effort recovery snapshot from the shared HealthKit store.
    /// Returns nil when HealthKit is unavailable. Otherwise returns a snapshot
    /// whose metrics are each independently nil-or-real: a partial grant or a
    /// metric with no samples in its window contributes nil, never a fabricated
    /// value. When NO metric came back at all, returns nil so the caller's
    /// `hasAnyData` gate stays simple (and the screen shows the Connect CTA /
    /// honest "Health off").
    ///
    /// This is the analogue of `WeatherService.fetchCurrent()` — same shape,
    /// same honesty contract.
    func fetchRecovery() async -> HealthSnapshot? {
        guard isHealthDataAvailable else { return nil }

        // Three independent reads run concurrently. Each is best-effort and
        // resolves to nil on any failure / no-sample — exactly mirroring the
        // weather chain's "miss → nil, never fabricate" rule.
        async let sleep = fetchMainSleepHours()
        async let rhr = fetchLatestRestingHeartRate()
        async let hrv = fetchLatestHRV()

        let (sleepResult, rhrResult, hrvResult) = await (sleep, rhr, hrv)

        let sleepHours = sleepResult?.hours
        let restingHeartRate = rhrResult?.bpm
        let hrvMs = hrvResult?.ms

        // No metric at all → honest nil (never an empty fabricated shell).
        if sleepHours == nil && restingHeartRate == nil && hrvMs == nil {
            return nil
        }

        // Freshest timestamp across whatever populated, for the "as of" line.
        let asOf: Date? = [sleepResult?.asOf, rhrResult?.asOf, hrvResult?.asOf]
            .compactMap { $0 }
            .max()

        return HealthSnapshot(
            sleepHours: sleepHours,
            restingHeartRate: restingHeartRate,
            hrvMs: hrvMs,
            asOf: asOf
        )
    }

    // MARK: - Sleep (most recent main session)

    /// Sum the 'asleep*' category samples of the MOST RECENT main sleep session
    /// over the last ~36h, in hours. Returns nil when sleep isn't authorized or
    /// no asleep samples exist in the window — never a fabricated 0.
    ///
    /// Strategy: pull all sleepAnalysis samples in the last 36h, keep only the
    /// "asleep" values (Core/Deep/REM on iOS 16+, plus the legacy unspecified
    /// `.asleep`), then collapse them into ONE session by clustering samples
    /// whose gaps are < ~3h apart and taking the most-recent cluster. The
    /// session hours are the union of the clustered asleep intervals (so
    /// overlapping/abutting stage samples don't double-count).
    private func fetchMainSleepHours() async -> (hours: Double, asOf: Date)? {
        guard let sleepType else { return nil }

        let end = Date()
        let start = end.addingTimeInterval(-36 * 3600)
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictEndDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error {
                    print("[HealthService] sleep query failed — \(error.localizedDescription)")
                    cont.resume(returning: [])
                    return
                }
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        guard !samples.isEmpty else { return nil }

        // Keep only 'asleep*' values. iOS 16 split asleep into Core/Deep/REM;
        // older payloads use `.asleep` (unspecified). `.inBed` and `.awake`
        // are excluded so time-in-bed never inflates the figure.
        let asleepValues: Set<Int> = {
            var v: Set<Int> = [HKCategoryValueSleepAnalysis.asleep.rawValue]
            if #available(iOS 16.0, *) {
                v.insert(HKCategoryValueSleepAnalysis.asleepCore.rawValue)
                v.insert(HKCategoryValueSleepAnalysis.asleepDeep.rawValue)
                v.insert(HKCategoryValueSleepAnalysis.asleepREM.rawValue)
                v.insert(HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue)
            }
            return v
        }()

        // Sorted ascending by start so we can cluster into sessions.
        let asleep = samples
            .filter { asleepValues.contains($0.value) }
            .sorted { $0.startDate < $1.startDate }
        guard !asleep.isEmpty else { return nil }

        // Cluster into sessions: a gap > 3h between consecutive asleep samples
        // starts a new session. We want the MOST RECENT session, so we take the
        // last cluster.
        let sessionGap: TimeInterval = 3 * 3600
        var sessions: [[HKCategorySample]] = []
        var current: [HKCategorySample] = []
        var lastEnd: Date?
        for s in asleep {
            if let prevEnd = lastEnd, s.startDate.timeIntervalSince(prevEnd) > sessionGap {
                sessions.append(current)
                current = []
            }
            current.append(s)
            lastEnd = max(lastEnd ?? s.endDate, s.endDate)
        }
        if !current.isEmpty { sessions.append(current) }
        guard let mainSession = sessions.last, !mainSession.isEmpty else { return nil }

        // Union the asleep intervals of the main session so overlapping stage
        // samples (Core vs Deep covering the same minute) don't double-count.
        let intervals = mainSession
            .map { (start: $0.startDate, end: $0.endDate) }
            .sorted { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = []
        for iv in intervals {
            if var last = merged.last, iv.start <= last.end {
                last.end = max(last.end, iv.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(iv)
            }
        }
        let totalSeconds = merged.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        guard totalSeconds > 0 else { return nil }

        let hours = totalSeconds / 3600.0
        let asOf = mainSession.map(\.endDate).max() ?? end
        return (hours: hours, asOf: asOf)
    }

    // MARK: - Resting heart rate (latest, ~7d)

    /// The latest restingHeartRate sample within the last ~7 days, in whole
    /// bpm. Returns nil when not authorized or no sample exists — never 0.
    private func fetchLatestRestingHeartRate() async -> (bpm: Int, asOf: Date)? {
        guard let restingHRType else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        guard let s = await fetchLatestQuantitySample(type: restingHRType, daysBack: 7) else {
            return nil
        }
        let value = s.quantity.doubleValue(for: unit)
        guard value > 0 else { return nil }
        return (bpm: Int(value.rounded()), asOf: s.endDate)
    }

    // MARK: - HRV SDNN (latest, ~7d)

    /// The latest heart-rate-variability SDNN sample within the last ~7 days,
    /// in milliseconds. Returns nil when not authorized or no sample exists —
    /// never 0.
    private func fetchLatestHRV() async -> (ms: Double, asOf: Date)? {
        guard let hrvType else { return nil }
        let unit = HKUnit.secondUnit(with: .milli)
        guard let s = await fetchLatestQuantitySample(type: hrvType, daysBack: 7) else {
            return nil
        }
        let value = s.quantity.doubleValue(for: unit)
        guard value > 0 else { return nil }
        return (ms: value, asOf: s.endDate)
    }

    // MARK: - Shared quantity fetch

    /// Most-recent single sample of `type` within `daysBack` days. Returns nil
    /// on any failure / no sample. Best-effort, never throws.
    private func fetchLatestQuantitySample(
        type: HKQuantityType,
        daysBack: Int
    ) async -> HKQuantitySample? {
        let end = Date()
        let start = end.addingTimeInterval(-Double(daysBack) * 86_400)
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictEndDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error {
                    print("[HealthService] \(type.identifier) query failed — \(error.localizedDescription)")
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: (results as? [HKQuantitySample])?.first)
            }
            store.execute(q)
        }
    }
}
