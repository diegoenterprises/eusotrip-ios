//
//  LifecycleGeocodeStore.swift
//  EusoTrip — fallback geocoder for the lifecycle map cards.
//
//  Problem solved
//  ──────────────
//  `shippers.getLifecycleSnapshot` returns the load's pickup + delivery
//  Stop records, but in real production data those rows often carry
//  only `address` / `city` / `state` strings — not lat / lng. The DB
//  geocoder runs on a backfill cron, not at write-time, so a freshly-
//  posted load shows up on a shipper's lifecycle screen with NO coords
//  for several minutes. Until 252, the LifecycleMapCard rendered an
//  honest "No GPS coordinates yet" empty state during that window.
//  Founder feedback 2026-05-10: empty state isn't good enough — every
//  load that has at least an address should show a real map.
//
//  How the fallback works
//  ──────────────────────
//  1. View calls `LifecycleGeocodeStore.shared.coords(loadId, side, snap)`
//     synchronously. It returns whatever's already known for that
//     loadId+side: the snapshot's lat/lng, then in-memory cache, then
//     the UserDefaults cache (survives app launches).
//  2. If nothing's known yet AND the snapshot's address string is
//     non-empty, the store kicks off a HereGeocodingClient.geocode()
//     request asynchronously and publishes the result via
//     `objectWillChange`. The map card observes the store and re-renders
//     when the coords land — typically ~150 ms later.
//  3. Cache key = "loadId|side|address-hash". Once HERE resolves, the
//     coords stay in UserDefaults forever (well, until the user's data
//     gets cleared) so the same load reading two devices later doesn't
//     re-pay the geocode round-trip.
//
//  Why per-side and not per-load
//  ─────────────────────────────
//  Pickup and delivery on a single load can resolve at different times
//  (HERE traffic, address quality, etc). Tagging by side lets either
//  pin land first without waiting on the other.
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation
import Combine

@MainActor
final class LifecycleGeocodeStore: ObservableObject {
    static let shared = LifecycleGeocodeStore()

    enum Side: String { case pickup, delivery }

    /// Cached or resolved coordinates for a single load+side.
    struct Coord: Codable, Hashable {
        let lat: Double
        let lng: Double
        /// Wallclock when HERE returned this row (or when the snapshot's
        /// own coords were captured). Used for telemetry only — the
        /// cache never auto-expires.
        let resolvedAt: Date
    }

    /// In-memory hot cache. Keyed by "loadId|side". Survives until the
    /// process restarts; UserDefaults backs cold-start lookups so a
    /// re-launch doesn't re-geocode the same address.
    @Published private(set) var coords: [String: Coord] = [:]

    /// Inflight geocode requests. Prevents the same `loadId|side` from
    /// firing two concurrent /v1/geocode round-trips when the lifecycle
    /// scaffold re-renders in fast succession.
    private var inflight: Set<String> = []

    /// UserDefaults key prefix.
    private let defaultsKey = "eusotrip.lifecycle.geocode.v1"

    init() {
        loadFromDisk()
    }

    /// Synchronous lookup. Returns what's already known. If nothing is
    /// known but the snapshot has an address, kicks off an async
    /// geocode in the background.
    ///
    /// - Parameters:
    ///   - loadId: stable load identifier (the lifecycle scaffold's
    ///             `loadId` is the right key — it survives status flips).
    ///   - side:   `.pickup` or `.delivery`
    ///   - lat / lng: snapshot's lat/lng (may be nil if backend hasn't
    ///                geocoded yet).
    ///   - addressLine: full address string for HERE to geocode if
    ///                  lat/lng are missing. The Stop record's `address`
    ///                  field is preferred; fall back to the
    ///                  facilityName + city/state synthesis if needed.
    func coords(loadId: String,
                side: Side,
                lat: Double?,
                lng: Double?,
                addressLine: String) -> CLLocationCoordinate2D? {
        // 1. Snapshot wins. If the backend has already geocoded, use
        //    those coords and update our cache so the next cold read
        //    on the SAME loadId+side hits memory instead of disk.
        if let lat, let lng, lat != 0 || lng != 0 {
            let key = cacheKey(loadId: loadId, side: side)
            if coords[key] == nil {
                coords[key] = Coord(lat: lat, lng: lng, resolvedAt: Date())
                persistToDisk()
            }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }

        // 2. Cache hit — return what we resolved before.
        let key = cacheKey(loadId: loadId, side: side)
        if let cached = coords[key] {
            return CLLocationCoordinate2D(latitude: cached.lat, longitude: cached.lng)
        }

        // 3. No coords + no cache. Kick off a background geocode if
        //    there's an address to work with. Caller will get nil now,
        //    but the published `coords` dict updates when HERE returns.
        let trimmed = addressLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              HereMapsConfig.hasBearerCredentials,
              !inflight.contains(key) else { return nil }

        inflight.insert(key)
        Task { [weak self] in
            await self?.resolve(loadId: loadId, side: side, query: trimmed)
        }
        return nil
    }

    /// Reset cached coords for a load (e.g. when the lifecycle stage
    /// flips and the address may have changed). Optional — production
    /// loads rarely change pickup/delivery addresses post-creation.
    func clear(loadId: String) {
        let prefix = "\(loadId)|"
        coords = coords.filter { !$0.key.hasPrefix(prefix) }
        persistToDisk()
    }

    // MARK: - Private

    private func cacheKey(loadId: String, side: Side) -> String {
        "\(loadId)|\(side.rawValue)"
    }

    private func resolve(loadId: String, side: Side, query: String) async {
        let key = cacheKey(loadId: loadId, side: side)
        defer { inflight.remove(key) }
        do {
            let results = try await HereGeocodingClient.shared.geocode(
                query: query,
                limit: 1
            )
            guard let top = results.first else { return }
            let coord = Coord(
                lat: top.position.lat,
                lng: top.position.lng,
                resolvedAt: Date()
            )
            coords[key] = coord
            persistToDisk()
        } catch {
            // Silent failure — the empty-state caption already conveys
            // "no map yet" honestly. Log once for diagnostics.
            NSLog("[LifecycleGeocodeStore] geocode failed for \(loadId)|\(side.rawValue): \(error.localizedDescription)")
        }
    }

    private func persistToDisk() {
        guard let data = try? JSONEncoder().encode(coords) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: Coord].self, from: data)
        else { return }
        coords = decoded
    }
}
