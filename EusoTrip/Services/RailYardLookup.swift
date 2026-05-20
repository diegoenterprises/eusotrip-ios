//
//  RailYardLookup.swift
//  T-032 (2026-05-20) — Canonical rail yard directory keyed by Metro.
//
//  Audit finding (01_AUDIT_FINDINGS_SYNTHESIS.md §8):
//    "Rail yard lookup service missing (port equivalent for rail)"
//
//  Mirrors the `PortDirectory` pattern used for vessel mode: a static
//  directory of named rail yards per Metro from RailLane.swift, with
//  Class-I operator + yard type (interchange, hump, intermodal,
//  drayage, manifest, automotive) so the wizard's mode-switch
//  auto-snap (T-031) + intermodal leg builder can drop the user at
//  the canonical yard for the lane.
//
//  Surface mirrors PortDirectory:
//    yards(in metro:)          → all yards in a metro
//    primaryYard(in metro:)    → highest-priority yard for routing
//    yards(for railroad:)      → all yards a Class I serves
//    yard(matching name:)      → exact-name lookup (BIC-equivalent for rail)
//

import Foundation

/// One rail yard entry. Code = AAR reporting marks of the yard
/// operator + yard ID (e.g., "BNSF-CICERO", "UP-WESTON-MILE-244").
public struct RailYard: Codable, Hashable, Identifiable {
    public let id: String                // e.g., "BNSF-CICERO"
    public let name: String              // human-readable
    public let metro: Metro              // canonical Metro from RailLane.swift
    public let operatorRR: ClassIRailroad
    public let kind: RailYardKind
    public let serves: [ClassIRailroad]  // interchange partners
    /// True for the yard that's typically used when routing through
    /// this metro on a generic intermodal lane (used by
    /// `primaryYard(in:)`).
    public let isPrimary: Bool

    public init(
        id: String,
        name: String,
        metro: Metro,
        operatorRR: ClassIRailroad,
        kind: RailYardKind,
        serves: [ClassIRailroad] = [],
        isPrimary: Bool = false
    ) {
        self.id = id
        self.name = name
        self.metro = metro
        self.operatorRR = operatorRR
        self.kind = kind
        self.serves = serves
        self.isPrimary = isPrimary
    }
}

public enum RailYardKind: String, Codable, Hashable, CaseIterable {
    case intermodal     // container / TOFC / COFC
    case manifest       // mixed-freight classification
    case hump           // gravity-classification hump yard
    case interchange    // Class-I-to-Class-I handoff
    case drayage        // truck-rail ramp / drayage staging
    case automotive     // auto-rack handling
    case bulk           // unit trains (coal / grain / aggregates)
    case tank           // hazmat / liquid bulk staging

    public var displayName: String {
        switch self {
        case .intermodal:  return "Intermodal"
        case .manifest:    return "Manifest"
        case .hump:        return "Hump"
        case .interchange: return "Interchange"
        case .drayage:     return "Drayage Ramp"
        case .automotive:  return "Auto Rack"
        case .bulk:        return "Bulk / Unit Train"
        case .tank:        return "Tank / Hazmat"
        }
    }
}

public enum RailYardLookup {

    /// Canonical yard catalog. ~40 entries spanning the largest US
    /// intermodal + manifest yards plus the 4 Mexican border yards
    /// (Laredo / Eagle Pass / Nuevo Laredo / Ciudad Juárez) and the
    /// principal Canadian yards (Toronto / Vancouver) used by
    /// CPKC + CN. Add new entries here as the lane atlas grows;
    /// downstream consumers consume the canonical set automatically.
    public static let all: [RailYard] = [
        // ─── BNSF western network ─────────────────────────────
        .init(id: "BNSF-HOBART",     name: "Hobart Intermodal",        metro: .losAngeles,    operatorRR: .bnsf, kind: .intermodal, serves: [.bnsf], isPrimary: true),
        .init(id: "BNSF-COMMERCE",   name: "Commerce Eastern",         metro: .losAngeles,    operatorRR: .bnsf, kind: .automotive, serves: [.bnsf]),
        .init(id: "BNSF-SBD",        name: "San Bernardino IMF",       metro: .losAngeles,    operatorRR: .bnsf, kind: .intermodal, serves: [.bnsf]),
        .init(id: "BNSF-STOCKTON",   name: "Stockton Intermodal",      metro: .stockton,      operatorRR: .bnsf, kind: .intermodal, serves: [.bnsf, .up], isPrimary: true),
        .init(id: "BNSF-SEATTLE",    name: "Seattle Int. Gateway",     metro: .seattle,       operatorRR: .bnsf, kind: .intermodal, serves: [.bnsf], isPrimary: true),
        .init(id: "BNSF-TACOMA",     name: "South Seattle IMF",        metro: .tacoma,        operatorRR: .bnsf, kind: .intermodal, serves: [.bnsf], isPrimary: true),
        .init(id: "BNSF-CICERO",     name: "Cicero IMF",               metro: .chicago,       operatorRR: .bnsf, kind: .intermodal, serves: [.bnsf, .ns, .csx, .cn, .cpkc], isPrimary: true),
        .init(id: "BNSF-WILLOWSPRINGS", name: "Willow Springs IMF",    metro: .chicago,       operatorRR: .bnsf, kind: .intermodal, serves: [.bnsf]),
        .init(id: "BNSF-LOGISTICSPARK", name: "Logistics Park Chicago", metro: .chicago,      operatorRR: .bnsf, kind: .drayage,    serves: [.bnsf]),
        .init(id: "BNSF-KCKMO",      name: "Argentine Yard",           metro: .kansasCity,    operatorRR: .bnsf, kind: .hump,       serves: [.bnsf, .up, .cpkc]),
        .init(id: "BNSF-FORTWORTH",  name: "Alliance Intermodal",      metro: .fortWorth,     operatorRR: .bnsf, kind: .intermodal, serves: [.bnsf], isPrimary: true),
        .init(id: "BNSF-HOUSTON",    name: "Pearland Logistics Park",  metro: .houston,       operatorRR: .bnsf, kind: .intermodal, serves: [.bnsf]),
        .init(id: "BNSF-MEMPHIS",    name: "Tennessee Yard",           metro: .memphis,       operatorRR: .bnsf, kind: .intermodal, serves: [.bnsf, .ns, .cpkc]),

        // ─── UP southern + western ────────────────────────────
        .init(id: "UP-ICTF",         name: "ICTF Long Beach",          metro: .longBeach,     operatorRR: .up,   kind: .intermodal, serves: [.up], isPrimary: true),
        .init(id: "UP-LATC",         name: "Los Angeles Transit Center", metro: .losAngeles,  operatorRR: .up,   kind: .intermodal, serves: [.up]),
        .init(id: "UP-OAKLAND",      name: "Oakland Outer Harbor",     metro: .oakland,       operatorRR: .up,   kind: .intermodal, serves: [.up], isPrimary: true),
        .init(id: "UP-NORTHPLATTE",  name: "Bailey Yard (largest hump worldwide)", metro: .omaha, operatorRR: .up, kind: .hump,     serves: [.up], isPrimary: true),
        .init(id: "UP-GLOBALII",     name: "Global II IMF",            metro: .chicago,       operatorRR: .up,   kind: .intermodal, serves: [.up]),
        .init(id: "UP-GLOBALIV",     name: "Global IV IMF",            metro: .chicago,       operatorRR: .up,   kind: .intermodal, serves: [.up]),
        .init(id: "UP-DALLAS",       name: "Dallas Intermodal Terminal", metro: .dallas,      operatorRR: .up,   kind: .intermodal, serves: [.up], isPrimary: true),
        .init(id: "UP-SANANTONIO",   name: "San Antonio IMF",          metro: .sanAntonio,    operatorRR: .up,   kind: .intermodal, serves: [.up], isPrimary: true),
        .init(id: "UP-LAREDO",       name: "Laredo Crossing",          metro: .laredo,        operatorRR: .up,   kind: .interchange,serves: [.up, .fxe, .cpkc], isPrimary: true),
        .init(id: "UP-EAGLEPASS",    name: "Eagle Pass Border IMF",    metro: .eaglePass,     operatorRR: .up,   kind: .interchange,serves: [.up, .fxe]),
        .init(id: "UP-NOLA",         name: "Avondale Intermodal",      metro: .newOrleans,    operatorRR: .up,   kind: .intermodal, serves: [.up, .csx, .ns], isPrimary: true),
        .init(id: "UP-HOUSTON",      name: "Englewood Yard",           metro: .houston,       operatorRR: .up,   kind: .manifest,   serves: [.up], isPrimary: true),

        // ─── CSX eastern network ─────────────────────────────
        .init(id: "CSX-NWO",         name: "North Baltimore IMF",      metro: .chicago,       operatorRR: .csx,  kind: .intermodal, serves: [.csx]),
        .init(id: "CSX-CHICAGO",     name: "59th Street Yard",         metro: .chicago,       operatorRR: .csx,  kind: .interchange,serves: [.csx, .bnsf, .up, .ns]),
        .init(id: "CSX-ATLANTA",     name: "Hulsey Yard",              metro: .atlanta,       operatorRR: .csx,  kind: .intermodal, serves: [.csx], isPrimary: true),
        .init(id: "CSX-JACKSONVILLE",name: "Bowden Yard",              metro: .jacksonville,  operatorRR: .csx,  kind: .hump,       serves: [.csx], isPrimary: true),
        .init(id: "CSX-MEMPHIS",     name: "Forrest Yard",             metro: .memphis,       operatorRR: .csx,  kind: .interchange,serves: [.csx]),
        .init(id: "CSX-SAVANNAH",    name: "Garden City Port Term.",   metro: .savannah,      operatorRR: .csx,  kind: .intermodal, serves: [.csx], isPrimary: true),

        // ─── NS eastern network ─────────────────────────────
        .init(id: "NS-LANDERS",      name: "Landers IMF",              metro: .chicago,       operatorRR: .ns,   kind: .intermodal, serves: [.ns]),
        .init(id: "NS-CALUMET",      name: "Calumet IMF",              metro: .chicago,       operatorRR: .ns,   kind: .intermodal, serves: [.ns]),
        .init(id: "NS-ATLANTA",      name: "Whitaker Yard",            metro: .atlanta,       operatorRR: .ns,   kind: .interchange,serves: [.ns]),
        .init(id: "NS-NORFOLK",      name: "Norfolk International Terminal", metro: .jacksonville, operatorRR: .ns, kind: .intermodal, serves: [.ns]),
        .init(id: "NS-MEMPHIS",      name: "Memphis Regional IMF",     metro: .memphis,       operatorRR: .ns,   kind: .intermodal, serves: [.ns]),

        // ─── CN + CPKC border ────────────────────────────────
        .init(id: "CN-MEMPHIS",      name: "Memphis Intermodal",       metro: .memphis,       operatorRR: .cn,   kind: .intermodal, serves: [.cn], isPrimary: true),
        .init(id: "CN-NOLA",         name: "Mays IMF (Mobile)",        metro: .mobile,        operatorRR: .cn,   kind: .intermodal, serves: [.cn], isPrimary: true),
        .init(id: "CN-CHICAGO",      name: "Markham Yard",             metro: .chicago,       operatorRR: .cn,   kind: .interchange,serves: [.cn, .csx, .ns]),
        .init(id: "CPKC-KCKMO",      name: "Knoche Yard",              metro: .kansasCity,    operatorRR: .cpkc, kind: .hump,       serves: [.cpkc, .bnsf, .up], isPrimary: true),
        .init(id: "CPKC-LAREDO",     name: "Sanchez IMF Laredo",       metro: .laredo,        operatorRR: .cpkc, kind: .interchange,serves: [.cpkc, .fxe, .up]),
        .init(id: "CPKC-CHICAGO",    name: "Bensenville IMF",          metro: .chicago,       operatorRR: .cpkc, kind: .intermodal, serves: [.cpkc]),
    ]

    /// All yards in a given metro. Empty when the metro has no
    /// registered yards (most US metros do; some specialty metros
    /// only have manifest yards excluded from this directory).
    public static func yards(in metro: Metro) -> [RailYard] {
        all.filter { $0.metro == metro }
    }

    /// Primary yard for routing through a metro. Returns the entry
    /// flagged `isPrimary` — or the first yard if none is flagged.
    public static func primaryYard(in metro: Metro) -> RailYard? {
        let metroYards = yards(in: metro)
        return metroYards.first(where: { $0.isPrimary }) ?? metroYards.first
    }

    /// All yards a given Class-I railroad operates OR interchanges at.
    public static func yards(for railroad: ClassIRailroad) -> [RailYard] {
        all.filter { $0.operatorRR == railroad || $0.serves.contains(railroad) }
    }

    /// Lookup by exact yard ID (operator-prefixed reporting key).
    public static func yard(matching id: String) -> RailYard? {
        all.first { $0.id == id }
    }

    /// True when a metro has at least one yard registered. Useful for
    /// the wizard's mode-switch path — it can show "ship-by-rail
    /// available in this metro" only when the lookup is non-empty.
    public static func hasYards(in metro: Metro) -> Bool {
        !yards(in: metro).isEmpty
    }
}
