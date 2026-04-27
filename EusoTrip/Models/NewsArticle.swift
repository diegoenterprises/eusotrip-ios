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

    /// Full-article link.
    var articleURL: URL? { URL(string: link) }

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
