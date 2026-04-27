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
    static func data(for url: URL, session: URLSession = .shared) async throws -> Data {
        func attempt() async throws -> (Data, HTTPURLResponse) {
            let token = try await HereMapsConfig.requireBearerToken()
            var req = URLRequest(url: url)
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
            let body = String(data: data, encoding: .utf8) ?? ""
            throw HereMapsError.http(http.statusCode, body)
        }
        return data
    }
}
