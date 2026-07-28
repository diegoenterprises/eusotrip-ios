//
//  HereRateLimiter.swift
//  EusoTrip — client-side rate limiter + 429 backoff for every HERE
//  Platform REST request.
//
//  ROOT CAUSE (HERE team confirmed, 2026-06-02): the app bursts past
//  the BASIC-account requests-per-minute ceiling. A single map move
//  fans out the ~10 add-on calls (HereAddOns) plus tiles plus routing
//  at once; HERE answers HTTP 429; the client locked up. This gate
//  keeps sustained outbound rate UNDER a conservative ceiling and, on
//  a 429 burst, opens a short cooldown so EVERY caller backs off
//  instead of hammering — degrade, never crash.
//
//  Two mechanisms, both enforced through the single `acquire()` gate:
//
//   1. CONCURRENCY CAP — at most `maxConcurrent` HERE requests are
//      in flight at any instant. The fan-out can't fire 10 sockets
//      simultaneously; they queue and drain in paced order.
//
//   2. MIN-INTERVAL PACER — successive `acquire()` grants are spaced
//      by at least `minInterval` so the sustained request rate can't
//      exceed `60 / minInterval` per minute. On a 429 the pacer's
//      effective interval is multiplied by the live cooldown level so
//      the whole app slows down together until the burst clears.
//
//  DETERMINISM RULE (founder mandate): the limiter NEVER reads the
//  system clock (`Date`, `DispatchTime`, `ContinuousClock`, …) and
//  NEVER calls an RNG. All spacing and all backoff/jitter are a PURE
//  FUNCTION of integer counters (the pacer tick index and the retry
//  attempt index), realised only through relative `Task.sleep`
//  durations. This keeps the behaviour reproducible under test and
//  free of wall-clock skew. There is no busy-wait loop anywhere — a
//  waiting caller is parked on a suspended continuation and resumed
//  by the pacer; an idle limiter does no work.
//
//  ENTERPRISE MIGRATION: every tier has limits, so the gate stays on
//  forever — only the constants change. When HERE hands over the
//  enterprise endpoints/keys, raise `maxConcurrent` and lower
//  `minInterval` here (see `Limits`); nothing else needs to move.
//
//  Powered by ESANG AI™.
//

import Foundation

/// Global serialization point for all outbound HERE REST traffic.
///
/// Call `await HereRateLimiter.shared.acquire()` immediately before
/// each `URLSession` request to a HERE host; report any HTTP 429 back
/// via `note429(retryAfter:)` so the shared cooldown opens. Use the
/// `HereRateLimiter.run(_:)` wrapper to get acquire + 429 backoff +
/// 429 reporting in one call.
///
/// `actor`-isolated, so all mutable state is data-race-free. Every
/// stored value is a `Sendable` value type.
actor HereRateLimiter {

    static let shared = HereRateLimiter()

    // MARK: - Configurable limits (conservative BASIC-tier defaults)

    /// Tunable ceiling. Defaults are deliberately conservative for the
    /// BASIC HERE account that returns 429 today. Raise `maxConcurrent`
    /// and lower `minIntervalNanos` after the enterprise migration —
    /// every other tier still has limits, so the gate is never removed.
    struct Limits: Sendable {
        /// Maximum HERE requests in flight at any instant. The add-on
        /// fan-out (HereAddOns) is ~10 calls; capping at 3 turns that
        /// burst into a paced trickle instead of a simultaneous spike.
        var maxConcurrent: Int = 3

        /// Minimum spacing between successive `acquire()` grants, in
        /// nanoseconds. 220 ms ⇒ ≤ ~270 grants/min sustained — safely
        /// under a basic-tier per-minute ceiling once the concurrency
        /// cap and per-screen debounce (HereAddOns: 350 ms) are layered
        /// on top.
        var minIntervalNanos: UInt64 = 220_000_000

        /// How many retry attempts the 429 backoff makes before giving
        /// up and letting the caller serve last-good cached data. Small
        /// on purpose: we want to fail soft fast, not hold the UI.
        var maxBackoffRetries: Int = 3

        /// Base unit (nanoseconds) for the exponential 429 backoff when
        /// HERE sends no `Retry-After` header. attempt 0 → ~0.5 s,
        /// 1 → ~1.0 s, 2 → ~2.0 s (plus deterministic per-attempt
        /// jitter). Used only by the `run`/`backoffDelayNanos` helpers.
        var backoffBaseNanos: UInt64 = 500_000_000

        /// Upper clamp on any single backoff sleep so a hostile/huge
        /// `Retry-After` can't park a caller for minutes.
        var backoffCapNanos: UInt64 = 8_000_000_000

        /// How many extra pacer "ticks" of cooldown a single 429 buys.
        /// Each cooldown level multiplies the effective min-interval, so
        /// a burst of 429s makes the whole app progressively slower
        /// until the ticks drain. Bounded by `maxCooldownLevel`.
        var cooldownTicksPer429: Int = 4

        /// Ceiling on the cooldown level so a 429 storm can't widen the
        /// interval without bound (which would look like a freeze).
        var maxCooldownLevel: Int = 6

        static let basicTier = Limits()

        /// Enterprise profile (2026-06-09 migration): the account no
        /// longer has the basic RPM ceiling that froze the demo, so the
        /// pacer opens up — 8 concurrent, 60 ms spacing (≤ ~1000
        /// grants/min) — while every 429 defense (backoff, cooldown,
        /// circuit breaker) stays armed because enterprise tiers still
        /// have *some* ceiling and a regression here must degrade
        /// gracefully, never freeze.
        static let enterpriseTier: Limits = {
            var l = Limits()
            // HERE_ENTERPRISE_AUDIT (2026-06-14) action #2 — "biggest perf win":
            // the basic→enterprise migration removed the RPM ceiling that paced
            // the map; open the limiter to the contracted enterprise RPS. Was
            // 8 concurrent / 60 ms (still conservative); raised to 15 / 40 ms
            // (≈1,500 grants/min). The 429 backoff + cooldown stay armed — every
            // tier has *some* ceiling and a regression must degrade, never freeze.
            l.maxConcurrent = 15
            l.minIntervalNanos = 40_000_000
            return l
        }()
    }

    /// Live limits. Mutable (`configure(_:)`) so the ceiling can move
    /// at runtime; the default follows `HereMapsConfig.activeTier` so
    /// flipping the tier seam re-tunes the pacer with no second switch
    /// to forget.
    private var limits: Limits =
        HereMapsConfig.activeTier == .enterprise ? .enterpriseTier : .basicTier

    /// Swap in a new ceiling (e.g. after the enterprise migration hands
    /// over higher-tier keys). Safe to call any time; in-flight waiters
    /// pick up the new spacing on their next grant.
    func configure(_ newLimits: Limits) {
        self.limits = newLimits
    }

    // MARK: - Internal state (all integer counters — no clock, no RNG)

    /// Requests currently in flight (granted but not yet `release()`d).
    private var inFlight = 0

    /// Whether the serial pacer task is currently draining the queue.
    /// Exactly one pacer runs at a time; it self-terminates when the
    /// queue empties so an idle limiter spins no task.
    private var pacerRunning = false

    /// FIFO of suspended callers awaiting a grant. Parked continuations,
    /// never a spin loop.
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Remaining cooldown "ticks". Each is consumed by one pacer cycle
    /// and, while > 0, widens the effective inter-grant interval. Opened
    /// by `note429`. Decays by exactly one per pacer tick — a pure
    /// counter, no wall-clock timer.
    private var cooldownTicks = 0

    private init() {}

    // MARK: - Acquire / release

    /// Suspends until a request slot is free AND the min-interval since
    /// the previous grant (widened by any live cooldown) has elapsed.
    /// Every HERE outbound request MUST `await acquire()` first, then
    /// `release()` (or use `run(_:)`/`runData(...)`, which pair them).
    func acquire() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
            startPacerIfNeeded()
        }
    }

    /// Mark a previously-acquired slot as freed. Lets the pacer admit
    /// the next waiter (subject to the concurrency cap).
    func release() {
        if inFlight > 0 { inFlight -= 1 }
        startPacerIfNeeded()
    }

    /// Convenience: acquire, run `body`, and always release — even if
    /// `body` throws. The release happens on the limiter actor.
    func withSlot<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let result = try await body()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }

    // MARK: - 429 cooldown / circuit-breaker

    /// Report that HERE returned HTTP 429. Opens / extends a short,
    /// app-wide cooldown that widens the pacer's effective interval so
    /// every caller backs off together until the burst clears. The
    /// `retryAfter` value (seconds, from the response header) only
    /// influences the per-call backoff sleep — the cooldown LEVEL is a
    /// pure counter so the limiter never reads the clock.
    func note429(retryAfter: TimeInterval? = nil) {
        // A larger Retry-After buys a deeper cooldown, but the mapping
        // is a clamp on an integer counter — no timestamp is stored.
        let extra: Int
        if let ra = retryAfter, ra > 0 {
            // ~1 extra level per second HERE asks us to wait, clamped.
            extra = min(limits.maxCooldownLevel, max(1, Int(ra.rounded(.up))))
        } else {
            extra = 1
        }
        let ticks = limits.cooldownTicksPer429 * extra
        cooldownTicks = min(limits.maxCooldownLevel * limits.cooldownTicksPer429,
                            cooldownTicks + ticks)
        startPacerIfNeeded()
    }

    /// Current cooldown level (0…maxCooldownLevel) derived from the
    /// remaining ticks. Multiplies the base min-interval. Read by the
    /// pacer only.
    private var cooldownLevel: Int {
        guard limits.cooldownTicksPer429 > 0 else { return 0 }
        let level = (cooldownTicks + limits.cooldownTicksPer429 - 1) / limits.cooldownTicksPer429
        return min(limits.maxCooldownLevel, level)
    }

    // MARK: - The pacer

    /// Effective spacing for the NEXT grant: base interval scaled by the
    /// live cooldown level (1 + level). Pure function of counters.
    private var effectiveIntervalNanos: UInt64 {
        let multiplier = UInt64(1 + cooldownLevel)
        // Saturating multiply guard (interval * 7 max — never overflows
        // a UInt64 for any sane interval, but keep it defensive).
        let (scaled, overflow) = limits.minIntervalNanos.multipliedReportingOverflow(by: multiplier)
        return overflow ? limits.backoffCapNanos : scaled
    }

    /// Kick the serial pacer if there's work (waiters or cooldown) and
    /// it isn't already running. Exactly one pacer task exists at a
    /// time; it loops until the queue is empty and the cooldown has
    /// fully drained, then clears `pacerRunning` so an idle limiter
    /// holds no task.
    private func startPacerIfNeeded() {
        guard !pacerRunning else { return }
        guard !waiters.isEmpty || cooldownTicks > 0 else { return }
        pacerRunning = true
        Task { await self.runPacer() }
    }

    /// Serial drain loop. Admits at most `maxConcurrent` callers, then
    /// sleeps the effective interval before admitting the next — so
    /// successive grants are spaced and the in-flight count is capped.
    /// One `cooldownTicks` is consumed per cycle so the cooldown decays
    /// purely by counting cycles, not by reading a clock.
    private func runPacer() async {
        defer { pacerRunning = false }

        while !waiters.isEmpty || cooldownTicks > 0 {
            // Admit one waiter if a concurrency slot is free.
            if !waiters.isEmpty, inFlight < limits.maxConcurrent {
                let cont = waiters.removeFirst()
                inFlight += 1
                cont.resume()

                // Space the NEXT grant by the (cooldown-scaled) interval.
                // Relative sleep only — no wall-clock read. A cancelled
                // sleep just means we re-evaluate immediately on the next
                // loop turn; the actor state stays consistent.
                let nanos = effectiveIntervalNanos
                if cooldownTicks > 0 { cooldownTicks -= 1 }
                try? await Task.sleep(nanoseconds: nanos)
            } else if waiters.isEmpty, cooldownTicks > 0 {
                // No one waiting, but a cooldown is open: let it drain so
                // the level decays even with no traffic. Tick down by one
                // interval per cycle.
                let nanos = effectiveIntervalNanos
                cooldownTicks -= 1
                try? await Task.sleep(nanoseconds: nanos)
            } else {
                // Waiters exist but the concurrency cap is full. Park the
                // pacer one interval, then re-check — `release()` will
                // also re-kick us, so this is just a safety re-poll, not
                // a busy spin (it sleeps a full interval each turn).
                try? await Task.sleep(nanoseconds: limits.minIntervalNanos)
            }
        }
    }

    // MARK: - Backoff (pure function of the attempt counter)

    /// Deterministic backoff delay for retry `attempt` (0-based). When
    /// HERE sent a `Retry-After` (seconds) we honour it (clamped); else
    /// exponential `base * 2^attempt` plus a deterministic per-attempt
    /// jitter derived ONLY from `attempt` (no RNG, no clock). Result is
    /// clamped to `backoffCapNanos`.
    func backoffDelayNanos(attempt: Int, retryAfter: TimeInterval?) -> UInt64 {
        if let ra = retryAfter, ra > 0 {
            let nanos = UInt64((ra * 1_000_000_000).rounded(.up))
            return min(nanos, limits.backoffCapNanos)
        }
        return Self.backoffDelayNanos(attempt: attempt,
                                      base: limits.backoffBaseNanos,
                                      cap: limits.backoffCapNanos)
    }

    /// Pure, side-effect-free backoff math — usable without the actor
    /// (e.g. from a synchronous wrapper) and trivially testable. Jitter
    /// is a fixed fraction selected by `attempt` so the sequence is
    /// reproducible: attempt 0 → +0%, 1 → +12.5%, 2 → +25%, 3 → +37.5%,
    /// cycling. NO randomness, NO clock.
    nonisolated static func backoffDelayNanos(attempt: Int,
                                              base: UInt64,
                                              cap: UInt64) -> UInt64 {
        let a = max(0, attempt)
        // Exponential term: base * 2^a, guarded against shift overflow.
        let shift = min(a, 16)                       // 2^16 ≈ 65k× — plenty
        let expFactor = UInt64(1) << UInt64(shift)
        let (grown, overflow) = base.multipliedReportingOverflow(by: expFactor)
        let exp = overflow ? cap : grown
        // Deterministic jitter: + (attempt mod 4)/8 of the exp term.
        let jitterEighths = UInt64(a % 4)            // 0,1,2,3
        let jitter = exp / 8 * jitterEighths
        let (summed, sumOverflow) = exp.addingReportingOverflow(jitter)
        let total = sumOverflow ? cap : summed
        return min(total, cap)
    }

    /// Max retries the standard wrapper will make (read by callers that
    /// roll their own transport loop.
    var maxBackoffRetries: Int { limits.maxBackoffRetries }

    // MARK: - One-shot gated request with 429 backoff

    /// Run a single gated HERE request with full 429 handling:
    ///   • acquire a paced slot (released when `fetch` returns/throws),
    ///   • on `HereMapsError.http(429, …)` sleep the deterministic
    ///     backoff (honouring `Retry-After` when present), report the
    ///     429 to open the shared cooldown, and retry up to
    ///     `maxBackoffRetries`,
    ///   • after the retries are exhausted, rethrow so the CALLER can
    ///     serve last-good cached data.
    ///
    /// `fetch` must perform exactly one HTTP round-trip and surface a
    /// 429 as `HereMapsError.http(429, body)` (every HERE client in
    /// this folder already does). `retryAfterFor` lets the caller pass
    /// the parsed `Retry-After` header for the most recent 429; pass
    /// `nil` if unavailable.
    func runData(
        retryAfterFor: @Sendable (_ attempt: Int) -> TimeInterval? = { _ in nil },
        _ fetch: @Sendable () async throws -> Data
    ) async throws -> Data {
        var attempt = 0
        while true {
            await acquire()
            do {
                let data = try await fetch()
                release()
                return data
            } catch let HereMapsError.http(status, body) where status == 429 {
                release()
                let ra = retryAfterFor(attempt)
                note429(retryAfter: ra)
                if attempt >= limits.maxBackoffRetries {
                    // Out of retries — surface so the caller degrades.
                    throw HereMapsError.http(status, body)
                }
                let nanos = backoffDelayNanos(attempt: attempt, retryAfter: ra)
                try? await Task.sleep(nanoseconds: nanos)
                attempt += 1
                // loop → re-acquire (re-paced) and retry
            } catch {
                release()
                throw error
            }
        }
    }
}

// MARK: - Retry-After header parsing (no clock; delta-seconds only)

extension HereRateLimiter {
    /// Parse a `Retry-After` response header into seconds. Only the
    /// delta-seconds form (an integer count) is honoured — the
    /// HTTP-date form is intentionally ignored because resolving it
    /// requires reading the system clock, which the determinism rule
    /// forbids. A missing/non-numeric/HTTP-date header → `nil`, which
    /// falls through to the deterministic exponential backoff.
    nonisolated static func retryAfterSeconds(from response: URLResponse?) -> TimeInterval? {
        guard let http = response as? HTTPURLResponse else { return nil }
        guard let raw = http.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        // Delta-seconds form only (e.g. "Retry-After: 5").
        if let secs = TimeInterval(raw), secs >= 0 { return secs }
        return nil
    }
}
