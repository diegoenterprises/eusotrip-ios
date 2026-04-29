//
//  HereTrafficAnalyticsClient.swift
//  EusoTrip — REST client for HERE Traffic Analytics Speed Data.
//
//  Endpoint (enterprise product):
//      GET https://traffic.hereapi.com/traffic/6.3/flow.json
//      (historical speed profile aggregated per-link per-hour)
//
//  Note: HERE retired the legacy *.ls.hereapi.com host family.
//  `1.base.maps.ls.hereapi.com` already returns 410 Gone on the web,
//  and the rest of the family will follow. Updated 2026-04-29 to
//  use the modern `traffic.hereapi.com` host (no `.ls.` prefix).
//
//  Traffic Analytics surfaces historical and typical speed patterns
//  that feed lane-level ETA refinement. Unlike `HereTrafficClient`
//  (live flow / incidents), this client answers "what's the typical
//  speed on I-80 between MM220 and MM240 on a Thursday at 17:00?"
//
//  The endpoint is part of HERE's Traffic Analytics SDK tier; if the
//  tenant's API key does not include Analytics access, calls return
//  403 and `HereBearerFetch` throws `HereMapsError.http(403, …)` —
//  callers should catch + fall back to `HereTrafficClient.flow` for
//  a live-only sample.
//
//  Required params:
//      bbox=<minLng>,<minLat>,<maxLng>,<maxLat>   (screen viewport)
//      responseAttributes=sh,fc    (shape + functional class)
//
//  Optional:
//      speedWindow=<ISO duration>   (aggregation window)
//      time=<ISO 8601 reference time>
//
//  Auth: Bearer via HereBearerFetch.
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

/// Historical / typical speed sample on a link. All fields optional
/// because HERE's analytics payload varies by request scope; we
/// keep the envelope lean and leave richer fields to specialist
/// ETA refiners that decode this directly.
struct HereAnalyticsFlowItem: Decodable, Identifiable, Hashable {
    var id: String { "\(linkId ?? "")-\(timestamp ?? "")" }
    let linkId: String?
    let timestamp: String?
    /// Historical typical speed (mph or km/h depending on locale).
    let typicalSpeed: Double?
    /// Sample speed at the requested `time` (for a planning query).
    let speed: Double?
    /// 0 (free flow) → 10 (closed) analogous to the live jam factor.
    let jamFactor: Double?
    let freeFlow: Double?
    let length: Double?
    let functionalClass: Int?
    let shape: [HerePoint]?
}

struct HereAnalyticsFlowResponse: Decodable {
    let items: [HereAnalyticsFlowItem]?
}

final class HereTrafficAnalyticsClient {
    static let shared = HereTrafficAnalyticsClient()

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Typical-speed flow inside a bounding box, optionally at a
    /// specific reference time (ISO 8601). Default returns the
    /// current-hour aggregate for the box.
    func typicalFlow(
        bbox: (minLng: Double, minLat: Double, maxLng: Double, maxLat: Double),
        time: Date? = nil
    ) async throws -> [HereAnalyticsFlowItem] {
        var comps = URLComponents(string: "https://traffic.hereapi.com/traffic/6.3/flow.json")!
        var items: [URLQueryItem] = [
            URLQueryItem(
                name: "bbox",
                value: "\(bbox.minLng),\(bbox.minLat),\(bbox.maxLng),\(bbox.maxLat)"
            ),
            URLQueryItem(name: "responseAttributes", value: "sh,fc"),
        ]
        if let t = time {
            let iso = ISO8601DateFormatter()
            items.append(URLQueryItem(name: "time", value: iso.string(from: t)))
        }
        comps.queryItems = items
        guard let url = comps.url else { throw HereMapsError.badURL }

        let data = try await HereBearerFetch.data(for: url, session: session)
        do {
            return try decoder.decode(HereAnalyticsFlowResponse.self, from: data).items ?? []
        } catch {
            throw HereMapsError.decoding(String(describing: error))
        }
    }
}
