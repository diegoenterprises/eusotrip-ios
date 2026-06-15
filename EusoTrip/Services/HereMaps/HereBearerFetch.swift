//
//  HereBearerFetch.swift
//  EusoTrip — Shared Bearer-authenticated fetch helper for HERE
//  Platform REST clients.
//
//  Every REST client in this folder (Fuel Prices, Weather, Parking,
//  EV Charging, Safety Cameras, Road Alerts, Real-Time Traffic,
//  Traffic Analytics Speed Data, etc.) uses the exact same auth
//  recipe:
//
//      1. Mint an OAuth2 client-credentials Bearer token via
//         `HereMapsConfig.requireBearerToken()` (which in turn
//         hits HEREAuthService for a cached/refreshed token).
//      2. Attach as `Authorization: Bearer <token>`.
//      3. On HTTP 401 — the only retriable case — invalidate the
//         cached token and retry exactly once before surfacing
//         `HereMapsError.http`.
//
//  Centralising the recipe here (instead of duplicating 15 lines
//  per client) keeps every HERE client on the same auth path so
//  a future change to token minting / retry policy touches one
//  file. Routing + Geocoding still ship their own local copy for
//  back-compat; new clients all call through here.
//
//  Powered by ESANG AI™.
//

import Foundation

enum HereBearerFetch {

    /// GET `url` with an OAuth2 Bearer token attached. On HTTP 401
    /// the cached token is invalidated and the fetch is retried
    /// exactly once. Non-2xx responses after retry surface as
    /// `HereMapsError.http(statusCode, body)`.
    ///
    /// RATE-LIMIT GATE (2026-06-02, HERE-confirmed 429 root cause):
    /// every round-trip is paced through `HereRateLimiter.shared`, and
    /// an HTTP 429 triggers the shared deterministic backoff + cooldown
    /// before a small number of retries. After the backoff budget is
    /// spent the 429 surfaces so the caller can serve last-good cached
    /// data instead of hammering HERE. This is the primary chokepoint:
    /// the bulk of the add-on fan-out (EV / weather / parking / traffic
    /// / safety cameras) flows through here, so gating it here paces
    /// most of the app's HERE traffic in one place.
    static func data(for url: URL, session: URLSession = .shared) async throws -> Data {
        // Per-attempt Retry-After captured from the most recent 429 so
        // the limiter's backoff can honour HERE's requested wait. Boxed
        // in an actor-isolated closure capture isn't needed — the
        // limiter calls `retryAfterFor` synchronously on its own actor
        // between awaits, so a simple reference type guarded by the
        // single-flight nature of `runData` is safe.
        let lastRetryAfter = RetryAfterBox()

        return try await HereRateLimiter.shared.runData(
            retryAfterFor: { _ in lastRetryAfter.seconds }
        ) {
            func attempt() async throws -> (Data, HTTPURLResponse) {
                let token = try await HereMapsConfig.requireBearerToken()
                var req = URLRequest(url: url)
                req.timeoutInterval = 20  // app-wide no-lingering-load bound
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    throw HereMapsError.providerError("No HTTP response")
                }
                return (data, http)
            }

            var (data, http) = try await attempt()
            if http.statusCode == 401 {
                await HEREAuthService.shared.invalidate()
                (data, http) = try await attempt()
            }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 429 {
                    lastRetryAfter.seconds = HereRateLimiter.retryAfterSeconds(from: http)
                }
                let body = String(data: data, encoding: .utf8) ?? ""
                throw HereMapsError.http(http.statusCode, body)
            }
            return data
        }
    }
}

/// Tiny reference box used to carry the most recent 429 `Retry-After`
/// out of a single gated fetch attempt and into the limiter's backoff
/// hook. Confined to one `runData` call (which serializes its own
/// retries), so no cross-task contention; `@unchecked Sendable` is the
/// honest annotation for that confinement.
private final class RetryAfterBox: @unchecked Sendable {
    var seconds: TimeInterval?
}
