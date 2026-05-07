//
//  HereTileOverlay.swift
//  EusoTrip — MKTileOverlay that pulls raster tiles from HERE Maps Tile API v3
//
//  Usage:
//    let overlay = HereTileOverlay(style: .dark)         // or .light
//    mapView.addOverlay(overlay, level: .aboveLabels)    // replaces Apple basemap
//
//  URL template (v3):
//    https://maps.hereapi.com/v3/base/mc/{z}/{x}/{y}/{size}/png?style=explore.day&ppi=400
//
//  Auth: `Authorization: Bearer <token>` header. Because MKTileOverlay's
//  `url(forTilePath:)` is URL-only (no header hook), we override
//  `loadTile(at:result:)` so the Bearer header can attach to the request.
//
//  Dark vs light comes from the `style=` query param:
//    - explore.night  → HERE's dark vector style
//    - explore.day    → HERE's light vector style
//
//  HERE PPI levels: 72, 100, 200, 250, 320, 400, 500.
//  400 ppi + tile size 512 is retina-friendly on iPhone.
//
//  Docs: https://developer.here.com/documentation/maps-api-for-javascript/dev_guide/topics/map-tile-service.html
//
//  Powered by ESANG AI™.
//

import Foundation
import MapKit

final class HereTileOverlay: MKTileOverlay {

    let style: HereTileStyle

    /// Session used for tile fetches. Defaults to `.shared` so tiles
    /// participate in the common URLCache — HERE tile URLs are keyed by
    /// `{z}/{x}/{y}` and do NOT include the Bearer token in the URL, so
    /// cache hits survive token refreshes.
    private let session: URLSession

    init(style: HereTileStyle, session: URLSession = .shared) {
        self.style = style
        self.session = session
        // HERE is a raster-tile replacement; the URL template is unused
        // because we override `loadTile(at:result:)` below, but the
        // parent class requires one in the initializer.
        super.init(urlTemplate: nil)

        // tileSize is the on-screen LOGICAL POINT size of each tile. The
        // standard Web-Mercator tile grid expects 256 pt — anything larger
        // forces MapKit to request fewer, lower-zoom tiles, which is why
        // labels rendered enormous and the basemap looked coarse pre-fix.
        // The PNG itself comes back from HERE at `style.sizePx` px (512)
        // → MKTileOverlayRenderer downsamples to 256 pt = retina-crisp on
        // 2x and 3x devices.
        self.tileSize = CGSize(width: 256, height: 256)
        self.maximumZ = 20
        self.minimumZ = 0
        // Replace Apple's basemap entirely — important for cohesive dark/light palette.
        self.canReplaceMapContent = true
    }

    /// Build the tile URL (no auth in the query string — Bearer token
    /// rides on the request header in `loadTile`). Still overridden so
    /// the parent class has a sensible URL for logging / debugging.
    ///
    /// Verified URL grammar (live-probed against `maps.hereapi.com`
    /// 2026-05-04):
    ///   `/v3/base/mc/{z}/{x}/{y}/png?style=explore.day&size=512&ppi=400`
    /// `size` and `ppi` are query parameters — putting `size` in the path
    /// (the previous shape) returns HTTP 404 with code `E622000`
    /// "requested path is not supported", which is why the HERE basemap
    /// never rendered on iOS until this build. The `style` value
    /// `explore.day` is the only style our HERE plan tier serves over
    /// raster — every `*.night` style 403s on the same tier.
    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host   = HereMapsConfig.tileBaseHost
        comps.path   = "\(HereMapsConfig.tileBasePath)/\(path.z)/\(path.x)/\(path.y)/png"
        comps.queryItems = [
            URLQueryItem(name: "style", value: style.rawValue),
            URLQueryItem(name: "size",  value: String(style.sizePx)),
            URLQueryItem(name: "ppi",   value: String(style.ppi)),
            URLQueryItem(name: "lang",  value: style.labelLanguage),
        ]
        // Force-unwrap is safe: every component above is literal or an integer.
        return comps.url!
    }

    /// Async fetch with `Authorization: Bearer <token>` header. Invoked
    /// by MapKit for every visible tile. A single 401 retry covers the
    /// "token revoked mid-session" case; any further error surfaces
    /// through the MapKit callback and MKTileOverlayRenderer will draw
    /// nothing for that tile (the brand basemap shows through).
    override func loadTile(at path: MKTileOverlayPath,
                           result: @escaping (Data?, Error?) -> Void) {
        let url = self.url(forTilePath: path)

        // If OAuth credentials aren't wired yet (dev build without
        // xcconfig), short-circuit to a transparent PNG so the map
        // doesn't log a network error on every pan.
        guard HereMapsConfig.hasBearerCredentials else {
            // Log once per process so we know why the basemap is blank
            // (founder report 2026-05-05: "map in driver load details
            // still isn't showing"). The cause is invariably an
            // un-populated EusoTrip.xcconfig — the keys are
            // git-ignored, so a fresh clone / CI build / new dev
            // device has the placeholders the plistString() guard
            // rejects. Posting `eusoHereCredsMissing` lets the
            // surface render an inline banner so the gap is visible
            // without trawling Console.app.
            Self.logMissingCredsOnce()
            result(Self.transparentPNG, nil)
            return
        }

        Task { [session] in
            func attempt() async throws -> (Data, HTTPURLResponse) {
                let token = try await HereMapsConfig.requireBearerToken()
                var req = URLRequest(url: url)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    throw HereMapsError.providerError("No HTTP response for tile")
                }
                return (data, http)
            }

            do {
                var (data, http) = try await attempt()
                if http.statusCode == 401 {
                    await HEREAuthService.shared.invalidate()
                    (data, http) = try await attempt()
                }
                guard (200..<300).contains(http.statusCode) else {
                    result(nil, HereMapsError.http(http.statusCode, "tile fetch"))
                    return
                }
                result(data, nil)
            } catch {
                result(nil, error)
            }
        }
    }

    /// 1×1 transparent PNG — returned when HERE credentials are missing
    /// so MapKit has something to draw instead of the default beige.
    private static let transparentPNG: Data = {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mMAAQAABQABDQottAAAAABJRU5ErkJggg=="
        return Data(base64Encoded: base64) ?? Data()
    }()

    /// One-shot console + Notification post when HERE creds are missing.
    /// Guarded with a static flag so panning the map doesn't spam the
    /// log with the same line for every tile.
    private static var didLogMissingCreds = false
    private static let missingCredsLock = NSLock()
    private static func logMissingCredsOnce() {
        missingCredsLock.lock()
        defer { missingCredsLock.unlock() }
        guard !didLogMissingCreds else { return }
        didLogMissingCreds = true
        NSLog("[HereTileOverlay] HERE OAuth creds missing — basemap blank. Populate HERE_ACCESS_KEY_ID / HERE_ACCESS_KEY_SECRET / HERE_TOKEN_ENDPOINT_URL in EusoTrip.xcconfig.")
        NotificationCenter.default.post(
            name: Notification.Name("eusoHereCredsMissing"),
            object: nil
        )
    }
}
