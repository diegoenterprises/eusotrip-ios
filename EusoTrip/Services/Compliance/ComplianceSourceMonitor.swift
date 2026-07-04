//
//  ComplianceSourceMonitor.swift
//  EusoTrip
//
//  Deterministic regulatory-source registry for compliance intelligence.
//  This is intentionally a source watchlist, not a pretend crawler: live
//  refresh belongs on the backend/job lane, while iOS consumes the same
//  authority/cadence map to explain which sources govern a shipment.
//

import Foundation

public enum ComplianceCountryScope: String, CaseIterable, Codable, Hashable, Sendable {
    case usa
    case canada
    case mexico
    case europe
    case unitedKingdom
    case global

    public var label: String {
        switch self {
        case .usa: return "USA"
        case .canada: return "Canada"
        case .mexico: return "Mexico"
        case .europe: return "Europe"
        case .unitedKingdom: return "United Kingdom"
        case .global: return "Global"
        }
    }
}

public struct ComplianceSourceWatch: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let authority: String
    public let sourceURL: URL
    public let cadence: String
    public let countries: [ComplianceCountryScope]
    public let modes: [TransportMode]
    public let keywords: [String]

    public init(
        id: String,
        title: String,
        authority: String,
        sourceURL: URL,
        cadence: String,
        countries: [ComplianceCountryScope],
        modes: [TransportMode],
        keywords: [String]
    ) {
        self.id = id
        self.title = title
        self.authority = authority
        self.sourceURL = sourceURL
        self.cadence = cadence
        self.countries = countries
        self.modes = modes
        self.keywords = keywords
    }

    public func applies(mode: TransportMode, countries targetCountries: [ComplianceCountryScope]) -> Bool {
        modes.contains(mode) && countries.contains { sourceCountry in
            sourceCountry == .global || targetCountries.contains(sourceCountry)
        }
    }

    public func matches(any searchTerms: [String]) -> Bool {
        let normalized = searchTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return true }
        let haystack = ([title, authority] + keywords).joined(separator: " ").lowercased()
        return normalized.contains { haystack.contains($0) }
    }
}

public enum ComplianceSourceMonitor {
    public static let watchedSources: [ComplianceSourceWatch] = [
        .init(
            id: "phmsa-interpretations-hmr",
            title: "PHMSA hazmat interpretations",
            authority: "PHMSA",
            sourceURL: URL(string: "https://www.phmsa.dot.gov/regulations/title49/b/2/1")!,
            cadence: "daily docket/interpretation review",
            countries: [.usa],
            modes: [.truck, .rail, .vessel, .barge],
            keywords: ["hazmat", "interpretation", "cargo tank", "mc-331", "leakage test"]
        ),
        .init(
            id: "ecfr-hmr-171-180",
            title: "Hazardous Materials Regulations",
            authority: "eCFR Title 49 Parts 171-180",
            sourceURL: URL(string: "https://www.ecfr.gov/current/title-49/subtitle-B/chapter-I/subchapter-C")!,
            cadence: "daily eCFR amendment watch",
            countries: [.usa],
            modes: [.truck, .rail, .vessel, .barge],
            keywords: ["49 cfr", "172", "173", "174", "176", "177", "178", "180", "mc-331"]
        ),
        .init(
            id: "fmcsa-regs-guidance",
            title: "Motor Carrier Safety Regulations",
            authority: "FMCSA",
            sourceURL: URL(string: "https://www.fmcsa.dot.gov/regulations")!,
            cadence: "daily guidance/rulemaking watch",
            countries: [.usa],
            modes: [.truck],
            keywords: ["fmcsa", "hos", "eld", "dvir", "cargo securement", "driver qualification"]
        ),
        .init(
            id: "fra-hazmat-rail",
            title: "Rail hazmat routing and safety",
            authority: "FRA / 49 CFR 172, 174, 232",
            sourceURL: URL(string: "https://railroads.dot.gov/elibrary-search")!,
            cadence: "weekly safety bulletin/rule watch",
            countries: [.usa],
            modes: [.rail],
            keywords: ["fra", "rail", "hazmat", "route analysis", "brake inspection"]
        ),
        .init(
            id: "uscg-dangerous-cargo",
            title: "Marine dangerous cargo and vessel inspection",
            authority: "USCG / eCFR Title 33 and 46",
            sourceURL: URL(string: "https://www.ecfr.gov/current/title-46")!,
            cadence: "weekly CFR and MSIB watch",
            countries: [.usa],
            modes: [.vessel, .barge],
            keywords: ["uscg", "dangerous cargo", "certificate of inspection", "subchapter o", "navigation safety"]
        ),
        .init(
            id: "transport-canada-tdg",
            title: "Transportation of Dangerous Goods",
            authority: "Transport Canada TDG",
            sourceURL: URL(string: "https://tc.canada.ca/en/dangerous-goods")!,
            cadence: "weekly TDG bulletin/regulation watch",
            countries: [.canada],
            modes: [.truck, .rail, .vessel],
            keywords: ["tdg", "dangerous goods", "erap", "canada", "placards"]
        ),
        .init(
            id: "sict-nom-dangerous-goods",
            title: "Dangerous goods transport NOMs",
            authority: "SICT / SCT Mexico",
            sourceURL: URL(string: "https://www.sct.gob.mx/transporte-y-medicina-preventiva/autotransporte-federal/normatividad/")!,
            cadence: "weekly NOM and circular watch",
            countries: [.mexico],
            modes: [.truck, .rail],
            keywords: ["nom-002-sct", "nom-020-sct", "mexico", "hazmat", "dangerous goods"]
        ),
        .init(
            id: "imo-imdg-solas",
            title: "IMDG Code and SOLAS cargo obligations",
            authority: "IMO",
            sourceURL: URL(string: "https://www.imo.org/en/OurWork/Safety/Pages/DangerousGoods-default.aspx")!,
            cadence: "weekly IMO circular/code watch",
            countries: [.global],
            modes: [.vessel],
            keywords: ["imdg", "solas", "vgm", "dangerous goods", "stowage", "segregation"]
        ),
        .init(
            id: "unece-adr-road",
            title: "ADR dangerous goods by road",
            authority: "UNECE",
            sourceURL: URL(string: "https://unece.org/transport/dangerous-goods/adr-2025-files")!,
            cadence: "weekly ADR amendment watch",
            countries: [.europe, .unitedKingdom],
            modes: [.truck],
            keywords: ["adr", "dangerous goods", "road", "europe", "segregation"]
        ),
        .init(
            id: "tanktransport-mc331-2026",
            title: "MC-331 cargo tank compliance watch",
            authority: "Tank Transport / PHMSA interpretation watch",
            sourceURL: URL(string: "https://tanktransport.com/2026/05/cargo-tank-compliance-mc-331/")!,
            cadence: "industry-watch follow-up to official PHMSA interpretations",
            countries: [.usa],
            modes: [.truck],
            keywords: ["mc-331", "lpg", "cargo tank", "covering", "leakage test", "bubble fluid"]
        )
    ]

    public static func sources(
        for mode: TransportMode,
        countries: [ComplianceCountryScope],
        keywords: [String] = []
    ) -> [ComplianceSourceWatch] {
        let resolvedCountries = countries.isEmpty ? [.usa] : countries
        return watchedSources.filter {
            $0.applies(mode: mode, countries: resolvedCountries) && $0.matches(any: keywords)
        }
    }
}
