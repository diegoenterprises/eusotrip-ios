//
//  NewsOGImageCache.swift
//  EusoTrip — client-side OG image fallback for the news feed.
//
//  The server's RSS scrape populates `NewsArticle.imageUrl` best-
//  effort from `<enclosure>` / `<media:content>` / inline `<img>`
//  tags. Some feeds (CDL Life, DAT, CCJ long-form posts) don't
//  expose those fields in their RSS — but the article's HTML HEAD
//  always carries an `<meta property="og:image">` or `<meta
//  name="twitter:image">`. This cache fills that gap at render
//  time so the driver sees a real article image on the list view
//  matching what they'd see on the detail reader.
//
//  Honest failure mode:
//    • The fetch is best-effort. If the article URL fails to load,
//      the HTML doesn't contain og:image, or the parse doesn't
//      find a URL, the view falls back to the category gradient.
//      We never fabricate a stand-in image.
//    • Results are cached in-memory per article URL + persisted to
//      UserDefaults-backed disk for 72 hours so a driver scrolling
//      back to yesterday's news doesn't re-download each HEAD.
//    • HEAD-only response would be ideal but many publishers serve
//      og:image only in the full HTML — we stream the first 64 KiB
//      of the HTML body, parse from that.
//

import Foundation

@MainActor
final class NewsOGImageCache: ObservableObject {
    static let shared = NewsOGImageCache()

    /// In-flight lookups — keyed by the article URL absolute string.
    /// Dedupes concurrent requests for the same URL (two rows of the
    /// same article rendered side-by-side).
    private var inflight: [String: Task<URL?, Never>] = [:]

    /// Resolved image URLs we've either fetched or failed on.
    /// Published so SwiftUI views re-render once a URL lands.
    @Published private(set) var resolved: [String: URL?] = [:]

    /// Persistent store — keeps the cache warm across app launches
    /// so the driver's news list doesn't flicker placeholders every
    /// morning. Expires entries older than 72h.
    private let defaults = UserDefaults.standard
    private let defaultsKey = "news.og-image-cache.v1"
    private let ttl: TimeInterval = 72 * 3600

    private init() {
        hydrateFromDisk()
    }

    /// Public entry — returns a cached URL synchronously if we have
    /// one, or kicks off an async fetch. View callers read `resolved`
    /// on re-render to pick up the newly-available URL.
    func image(for articleURL: URL) -> URL? {
        let key = articleURL.absoluteString
        if let existing = resolved[key] { return existing }
        if inflight[key] != nil { return nil }
        inflight[key] = Task { @MainActor [weak self] in
            let url = await Self.fetch(from: articleURL)
            guard let self else { return url }
            self.resolved[key] = url
            self.inflight.removeValue(forKey: key)
            self.persist()
            return url
        }
        return nil
    }

    // MARK: - Fetch

    /// Fetch the first 64 KiB of the article HTML and parse og:image.
    /// Returns nil when the page is unreachable or we can't find a
    /// meta tag — caller falls back to the category gradient.
    private static func fetch(from url: URL) async -> URL? {
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.httpMethod = "GET"
        // A realistic UA; many news sites 403 a default URLSession UA.
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode ?? 500 < 400 else { return nil }
            // Most publishers put og:image well within the first 64 KiB.
            let window = data.prefix(65_536)
            guard let html = String(data: window, encoding: .utf8)
                ?? String(data: window, encoding: .isoLatin1)
            else { return nil }
            return extractOGImage(from: html, baseURL: url)
        } catch {
            return nil
        }
    }

    /// Extract `<meta property="og:image">` (or twitter:image) from
    /// a chunk of HTML. Tolerant of single-quote / double-quote
    /// attribute styles and attribute ordering.
    static func extractOGImage(from html: String, baseURL: URL) -> URL? {
        // Try og:image first, then twitter:image, then og:image:url.
        let patterns = [
            #"<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']"#,
            #"<meta[^>]*name=["']twitter:image["'][^>]*content=["']([^"']+)["']"#,
            #"<meta[^>]*property=["']og:image:url["'][^>]*content=["']([^"']+)["']"#,
            // Attribute-order-reversed flavour (content before property).
            #"<meta[^>]*content=["']([^"']+)["'][^>]*property=["']og:image["']"#,
            #"<meta[^>]*content=["']([^"']+)["'][^>]*name=["']twitter:image["']"#,
        ]
        for pattern in patterns {
            guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = rx.firstMatch(in: html, options: [], range: range),
               match.numberOfRanges >= 2,
               let captured = Range(match.range(at: 1), in: html) {
                let raw = String(html[captured])
                    .replacingOccurrences(of: "&amp;", with: "&")
                if let direct = URL(string: raw) {
                    return direct.scheme != nil ? direct : URL(string: raw, relativeTo: baseURL)
                }
                if let relative = URL(string: raw, relativeTo: baseURL) {
                    return relative
                }
            }
        }
        return nil
    }

    // MARK: - Persistence

    private struct CacheEntry: Codable {
        let url: String?           // nil encodes a known-miss
        let fetchedAt: Date
    }

    private func persist() {
        let now = Date()
        var disk: [String: CacheEntry] = [:]
        for (k, v) in resolved {
            disk[k] = CacheEntry(url: v?.absoluteString, fetchedAt: now)
        }
        if let data = try? JSONEncoder().encode(disk) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    private func hydrateFromDisk() {
        guard let data = defaults.data(forKey: defaultsKey),
              let disk = try? JSONDecoder().decode([String: CacheEntry].self, from: data)
        else { return }
        let cutoff = Date().addingTimeInterval(-ttl)
        var out: [String: URL?] = [:]
        for (k, v) in disk where v.fetchedAt > cutoff {
            out[k] = v.url.flatMap(URL.init(string:))
        }
        resolved = out
    }
}
