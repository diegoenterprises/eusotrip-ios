//
//  NewsArticle.swift
//  EusoTrip — Codable mirror of `newsRouter` article shape
//
//  Authority: frontend/server/routers/news.ts (RSSArticle interface).
//  The server fans out to ~100 tier-1 RSS feeds across 11 categories
//  (trucking, government, hazmat, oil_gas, chemical, bulk, refrigerated,
//  logistics, supply_chain, marine, energy, equipment) and normalises
//  each feed item into this shape. `imageUrl` is best-effort scraped
//  from RSS enclosure / media:content / inline <img>; when absent the
//  native UI falls back to a gradient placeholder keyed on category.
//

import Foundation
import CryptoKit

/// One article from the unified driver-intel feed.
struct NewsArticle: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let link: String
    let publishedAt: String    // ISO-8601
    let source: String         // e.g. "FreightWaves"
    let sourceUrl: String?
    let category: String       // see NewsCategory raw values
    let imageUrl: String?

    /// Parsed publish date (epoch 0 fallback so we can still sort).
    var publishDate: Date {
        NewsArticle.iso.date(from: publishedAt)
            ?? Date(timeIntervalSince1970: 0)
    }

    /// Preferred AsyncImage URL.
    var imageURL: URL? {
        guard let imageUrl else { return nil }
        return URL(string: imageUrl)
    }

    /// Full-article link. RSS link fields can contain surrounding whitespace
    /// or an XML-escaped query separator, but the reader must never mount a
    /// relative, local, or executable URL as publisher content.
    var articleURL: URL? {
        let candidate = link
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
        guard
            !candidate.isEmpty,
            var components = URLComponents(string: candidate),
            let rawScheme = components.scheme,
            let host = components.host,
            !host.isEmpty,
            components.user == nil,
            components.password == nil
        else {
            return nil
        }

        let scheme = rawScheme.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        components.scheme = scheme
        return components.url
    }

    /// Typed category with a safe fallback.
    var typedCategory: NewsCategory {
        NewsCategory(rawValue: category) ?? .other
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Full-article translation contract

enum ArticleTranslationSegmentKind: String, Codable, Hashable, Sendable {
    case heading
    case paragraph
    case listItem
    case quote
    case caption
    case tableCell
    case imageAlt
}

struct ArticleTranslationSegment: Codable, Hashable, Sendable {
    let id: String
    let kind: ArticleTranslationSegmentKind
    let text: String
}

enum ArticleTranslationContractError: LocalizedError {
    case invalidDocument
    case articleTooLarge
    case responseMismatch
    case expiredCache

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "The publisher page did not expose a complete readable article."
        case .articleTooLarge:
            return "This article is too large to translate completely in one request."
        case .responseMismatch:
            return "The translation response did not match the current article."
        case .expiredCache:
            return "The cached translation has expired."
        }
    }
}

struct ArticleTranslationDocument: Codable, Hashable, Sendable {
    let canonicalURL: String
    let sourceLanguageHint: String?
    let segments: [ArticleTranslationSegment]
    let contentFingerprint: String

    private struct DOMDocument: Decodable {
        let canonicalURL: String?
        let sourceLanguage: String?
        let segments: [ArticleTranslationSegment]
    }

    init(javaScriptValue: Any, fallbackURL: URL) throws {
        guard JSONSerialization.isValidJSONObject(javaScriptValue) else {
            throw ArticleTranslationContractError.invalidDocument
        }
        let data = try JSONSerialization.data(withJSONObject: javaScriptValue)
        let wire = try JSONDecoder().decode(DOMDocument.self, from: data)
        try self.init(
            canonicalURL: Self.canonicalURL(wire.canonicalURL, fallback: fallbackURL),
            sourceLanguageHint: Self.validLanguageHint(wire.sourceLanguage),
            segments: wire.segments
        )
    }

    init(
        canonicalURL: String,
        sourceLanguageHint: String?,
        segments: [ArticleTranslationSegment]
    ) throws {
        guard let fallbackURL = URL(string: canonicalURL) else {
            throw ArticleTranslationContractError.invalidDocument
        }
        let normalizedCanonicalURL = try Self.canonicalURL(canonicalURL, fallback: fallbackURL)
        let cleaned = segments.compactMap { segment -> ArticleTranslationSegment? in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return ArticleTranslationSegment(id: segment.id, kind: segment.kind, text: text)
        }
        let ids = Set(cleaned.map(\.id))
        let characterCount = cleaned.reduce(0) { $0 + $1.text.count }
        guard !cleaned.isEmpty, ids.count == cleaned.count else {
            throw ArticleTranslationContractError.invalidDocument
        }
        guard cleaned.count <= 600, characterCount <= 160_000 else {
            throw ArticleTranslationContractError.articleTooLarge
        }

        self.canonicalURL = normalizedCanonicalURL
        self.sourceLanguageHint = Self.validLanguageHint(sourceLanguageHint)
        self.segments = cleaned
        self.contentFingerprint = Self.fingerprint(for: cleaned)
    }

    static func fingerprint(for segments: [ArticleTranslationSegment]) -> String {
        let material = (["article-translation-v1"] + segments.map { segment in
            [
                segment.id,
                segment.kind.rawValue,
                segment.text
                    .precomposedStringWithCanonicalMapping
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
            ].joined(separator: "\u{0000}")
        }).joined(separator: "\u{001E}")
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var cacheKey: String {
        "\(canonicalURL)\u{0000}\(contentFingerprint)"
    }

    private static func canonicalURL(_ candidate: String?, fallback: URL) throws -> String {
        let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = (raw?.isEmpty == false ? raw : nil) ?? fallback.absoluteString
        guard
            var components = URLComponents(string: selected),
            let scheme = components.scheme?.lowercased(),
            (scheme == "http" || scheme == "https"),
            let host = components.host,
            !host.isEmpty,
            components.user == nil,
            components.password == nil
        else {
            throw ArticleTranslationContractError.invalidDocument
        }
        components.scheme = scheme
        components.fragment = nil
        guard let normalized = components.url?.absoluteString else {
            throw ArticleTranslationContractError.invalidDocument
        }
        return normalized
    }

    private static func validLanguageHint(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...35).contains(trimmed.count) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        return trimmed.unicodeScalars.allSatisfy(allowed.contains) ? trimmed : nil
    }
}

struct ArticleTranslationRequest: Encodable, Sendable {
    let canonicalURL: String
    let contentFingerprint: String
    let targetLocale: String
    let sourceLanguageHint: String?
    let segments: [ArticleTranslationSegment]
    let forceRefresh: Bool

    init(document: ArticleTranslationDocument, targetLocale: String, forceRefresh: Bool) {
        canonicalURL = document.canonicalURL
        contentFingerprint = document.contentFingerprint
        self.targetLocale = targetLocale
        sourceLanguageHint = document.sourceLanguageHint
        segments = document.segments
        self.forceRefresh = forceRefresh
    }
}

enum ArticleTranslationStatus: String, Codable, Hashable, Sendable {
    case complete
    case partial
    case unavailable
    case notNeeded = "not_needed"
}

struct ArticleTranslatedSegment: Codable, Hashable, Sendable {
    let id: String
    let text: String
}

struct ArticleTranslationResponse: Codable, Hashable, Sendable {
    struct Provenance: Codable, Hashable, Sendable {
        let service: String
        let provider: String
        let models: [String]
        let machineTranslated: Bool
    }

    struct CacheMetadata: Codable, Hashable, Sendable {
        let status: String
        let generatedAt: String
        let expiresAt: String
        let freshnessSeconds: Int
    }

    let status: ArticleTranslationStatus
    let canonicalURL: String
    let contentFingerprint: String
    let sourceLanguage: String
    let sourceLanguageEvidence: String
    let targetLocale: String
    let segments: [ArticleTranslatedSegment]
    let requestedSegmentCount: Int
    let translatedSegmentCount: Int
    let missingSegmentIds: [String]
    let provenance: Provenance
    let cache: CacheMetadata
    let errorCode: String?

    func validated(
        for document: ArticleTranslationDocument,
        targetLocale: String
    ) throws -> ArticleTranslationResponse {
        let documentIDs = Set(document.segments.map(\.id))
        let translatedIDs = Set(segments.map(\.id))
        let expectedMissing = document.segments
            .filter { !translatedIDs.contains($0.id) }
            .map(\.id)

        guard
            canonicalURL == document.canonicalURL,
            contentFingerprint == document.contentFingerprint,
            self.targetLocale.caseInsensitiveCompare(targetLocale) == .orderedSame,
            requestedSegmentCount == document.segments.count,
            translatedSegmentCount == segments.count,
            translatedIDs.count == segments.count,
            translatedIDs.isSubset(of: documentIDs),
            segments.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
            ["hit", "miss"].contains(cache.status),
            cache.freshnessSeconds >= 0,
            ["document", "provider", "undetermined"].contains(sourceLanguageEvidence),
            provenance.service == "ESANG",
            provenance.provider == "Google Gemini",
            cacheDatesAreOrdered
        else {
            throw ArticleTranslationContractError.responseMismatch
        }

        switch status {
        case .complete:
            guard translatedIDs == documentIDs,
                  missingSegmentIds.isEmpty,
                  !provenance.models.isEmpty,
                  provenance.machineTranslated else {
                throw ArticleTranslationContractError.responseMismatch
            }
        case .partial:
            guard !segments.isEmpty,
                  segments.count < document.segments.count,
                  missingSegmentIds == expectedMissing,
                  !provenance.models.isEmpty,
                  provenance.machineTranslated else {
                throw ArticleTranslationContractError.responseMismatch
            }
        case .unavailable:
            guard segments.isEmpty,
                  missingSegmentIds == document.segments.map(\.id),
                  !provenance.machineTranslated else {
                throw ArticleTranslationContractError.responseMismatch
            }
        case .notNeeded:
            guard segments.isEmpty,
                  missingSegmentIds.isEmpty,
                  !provenance.models.isEmpty,
                  !provenance.machineTranslated else {
                throw ArticleTranslationContractError.responseMismatch
            }
        }
        return self
    }

    var generatedAtDate: Date? { Self.isoDate(cache.generatedAt) }
    var expiresAtDate: Date? { Self.isoDate(cache.expiresAt) }

    private var cacheDatesAreOrdered: Bool {
        guard let generatedAtDate, let expiresAtDate else { return false }
        return expiresAtDate > generatedAtDate
    }

    private static func isoDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

/// Categories mirrored from the server's category enum. Native label +
/// accent colour hint (resolved in the view layer) lets filter chips and
/// category badges stay in sync with `news-feed-section.html`.
enum NewsCategory: String, CaseIterable, Codable, Hashable {
    case all            // pseudo-category for filter chips
    case trucking
    case government
    case regulatory     // alias for government but separate chip per wireframe
    case hazmat
    case oil_gas
    case chemical
    case bulk
    case refrigerated
    case logistics
    case supply_chain
    case marine
    case energy
    case equipment
    case safety         // §395.8 warnings, DOT advisories cluster
    case technology     // AI / ELD / platform updates
    case market         // fuel + rate trends
    case terminal       // port/terminal operational advisories
    case other

    var displayName: String {
        switch self {
        case .all:          return "All"
        case .trucking:     return "Trucking"
        case .government:   return "Gov"
        case .regulatory:   return "Regulatory"
        case .hazmat:       return "Hazmat"
        case .oil_gas:      return "Oil & Gas"
        case .chemical:     return "Chemical"
        case .bulk:         return "Bulk"
        case .refrigerated: return "Reefer"
        case .logistics:    return "Logistics"
        case .supply_chain: return "Supply"
        case .marine:       return "Marine"
        case .energy:       return "Energy"
        case .equipment:    return "Equipment"
        case .safety:       return "Safety"
        case .technology:   return "Tech"
        case .market:       return "Market"
        case .terminal:     return "Terminal"
        case .other:        return "Other"
        }
    }
}

/// tRPC `news.getMorningBrief` response envelope — 8 articles per role
/// plus a short role-personalised lead summary.
struct NewsMorningBrief: Codable, Hashable {
    let role: String
    let articles: [NewsArticle]
    let generatedAt: String?
    let summary: String?
}

/// tRPC `news.cacheStatus` — cheap poll to decide whether to re-fetch.
struct NewsCacheStatus: Codable, Hashable {
    let generation: Int
    let lastUpdated: String?
    let articleCount: Int?
}

/// tRPC `news.getArticles` response envelope.
struct NewsArticlePage: Codable, Hashable {
    let articles: [NewsArticle]
    let total: Int
    let lastUpdated: String?
    let generation: Int?
}

/// tRPC `news.getBreakingNews` — clusters of 2h-old articles from 3+
/// sources. We collapse them to a single lead article + an "also
/// reported by" list for the UI.
struct NewsBreakingCluster: Codable, Hashable, Identifiable {
    let id: String
    let leadArticle: NewsArticle
    let relatedSources: [String]
    let clusterSize: Int
}

/// Driver-centric role set used to pick a default feed slice when the
/// user hasn't picked a filter. Mirrors the server's role enum values.
enum NewsFeedRole: String, Codable, Hashable {
    case driver            = "DRIVER"
    case dispatcher        = "DISPATCH"
    case broker            = "BROKER"
    case shipper           = "SHIPPER"
    case catalyst          = "CATALYST"
    case terminalManager   = "TERMINAL_MANAGER"
    case vesselShipper     = "VESSEL_SHIPPER"
    case vesselOperator    = "VESSEL_OPERATOR"
    case railShipper       = "RAIL_SHIPPER"
    case railCatalyst      = "RAIL_CATALYST"
    case complianceOfficer = "COMPLIANCE_OFFICER"
    case safetyManager     = "SAFETY_MANAGER"
    case admin             = "ADMIN"

    /// Categories the server prioritises for this role's morning brief.
    /// Used client-side as a secondary filter when the server endpoint
    /// is unavailable (offline fallback).
    var preferredCategories: [NewsCategory] {
        switch self {
        case .driver:
            return [.trucking, .government, .hazmat, .energy, .safety]
        case .dispatcher:
            return [.trucking, .logistics, .supply_chain]
        case .broker:
            return [.trucking, .logistics, .supply_chain, .marine, .market]
        case .shipper:
            return [.oil_gas, .trucking, .chemical, .bulk, .energy, .market]
        case .catalyst:
            return [.trucking, .logistics, .government, .hazmat, .bulk]
        case .terminalManager:
            return [.oil_gas, .chemical, .bulk, .hazmat, .energy, .terminal]
        case .vesselShipper, .vesselOperator:
            return [.marine, .oil_gas, .bulk, .energy]
        case .railShipper, .railCatalyst:
            return [.bulk, .chemical, .energy, .government]
        case .complianceOfficer, .safetyManager:
            return [.government, .regulatory, .safety, .hazmat, .trucking]
        case .admin:
            return NewsCategory.allCases.filter { $0 != .all && $0 != .other }
        }
    }
}
