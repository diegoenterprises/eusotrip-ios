//
//  VesselClassRecommender.swift
//  T-033 (2026-05-20) — Recommend a canonical VesselClassKind from
//  cargo volume + commodity descriptor.
//
//  Audit finding (01_AUDIT_FINDINGS_SYNTHESIS.md §8):
//    "Vessel class recommender missing"
//
//  The Post-Load wizard's mode picker (T-031) auto-snaps a truck
//  trailer to a vessel class via `EquipmentEquivalency.vesselFor(_:)`
//  — but that mapping is trailer-to-class, not cargo-shape-aware.
//  When a shipper picks "Vessel" without a canonical trailer (or with
//  ambiguous cargo like a flatbed-going-overseas project move), this
//  recommender picks the right vessel class from the cargo
//  description itself. Output is the canonical `VesselClassKind`
//  enum from T-001's `EquipmentEquivalency.swift`.
//

import Foundation

public enum VesselClassRecommender {

    /// Input shape — passed to the recommender by Step 1 / Step 2 of
    /// the wizard once the shipper has chosen vessel mode.
    public struct Input: Codable, Hashable {
        /// Free-text commodity description (matches Step 2's product name).
        /// The recommender does a case-insensitive substring match on
        /// canonical keywords; misses fall through to `defaultClass`.
        public let commodity: String
        /// Hazmat class (e.g., "3", "2.1"). Empty when non-hazmat.
        public let hazmatClass: String
        /// Cargo volume in metric tons. Used to disambiguate when the
        /// commodity could fit multiple vessel classes (e.g., a small
        /// bulk shipment fits a container vessel as bagged cargo;
        /// a 25,000 MT bulk shipment forces a bulker).
        public let metricTons: Double?
        /// True when the cargo is wheeled (vehicles / heavy equipment)
        /// and rolls on/off rather than being lifted. Forces .roRo.
        public let isWheeled: Bool
        /// True when the cargo requires temperature control end-to-end.
        public let requiresColdChain: Bool
        /// True when the cargo is LNG / LIN / LOX / LH2.
        public let isCryogenic: Bool

        public init(
            commodity: String = "",
            hazmatClass: String = "",
            metricTons: Double? = nil,
            isWheeled: Bool = false,
            requiresColdChain: Bool = false,
            isCryogenic: Bool = false
        ) {
            self.commodity = commodity
            self.hazmatClass = hazmatClass
            self.metricTons = metricTons
            self.isWheeled = isWheeled
            self.requiresColdChain = requiresColdChain
            self.isCryogenic = isCryogenic
        }
    }

    /// Recommendation envelope — `pick` is the canonical class chosen,
    /// `rationale` is the human-readable explanation surfaced to the
    /// shipper so they can override if the recommendation is wrong.
    public struct Recommendation: Codable, Hashable {
        public let pick: VesselClassKind
        public let rationale: String
        public let confidence: Confidence

        public enum Confidence: String, Codable, Hashable {
            case high       // unambiguous match (e.g., LNG → .lng)
            case medium     // multi-signal match (e.g., bulk + > 10k MT → .bulkCarrier)
            case low        // fallback to default — shipper should review
        }
    }

    /// Default vessel class when no signal matches. Container ships
    /// handle the broadest cargo mix so this is the safest fallback.
    public static let defaultClass: VesselClassKind = .containerShip

    /// Canonical commodity keyword bank → vessel class. Lower-case
    /// substring match. Order matters — earlier rows take precedence
    /// because the most specific keywords are higher in the list.
    private static let keywordTable: [(keyword: String, pick: VesselClassKind, rationale: String)] = [
        // Cryogenic / LNG family
        ("lng",                    .lng,             "LNG carrier — membrane / Moss-sphere cryogenic containment"),
        ("liquefied natural gas",  .lng,             "LNG carrier — membrane / Moss-sphere cryogenic containment"),
        ("lin",                    .lng,             "LNG-class vessel — liquid nitrogen treated as cryogenic"),
        ("lox",                    .lng,             "LNG-class vessel — liquid oxygen treated as cryogenic"),
        // Refrigerated containers
        ("reefer",                 .reeferContainer, "Reefer container ship — temperature-controlled freight"),
        ("frozen",                 .reeferContainer, "Reefer container ship — frozen cargo end-to-end cold chain"),
        ("produce",                .reeferContainer, "Reefer container ship — fresh produce + perishables"),
        ("pharma",                 .reeferContainer, "Reefer container ship — pharmaceutical cold chain"),
        // ISO tank chemicals
        ("iso tank",               .isoTank,         "ISO tank ship — chemicals + food-grade liquid in ISO-format tanks"),
        ("specialty chemical",     .isoTank,         "ISO tank ship — specialty chemicals routed in ISO tanks"),
        // Tanker liquids
        ("crude",                  .tanker,          "Tanker — crude oil cargo (Aframax/Suezmax/VLCC tier)"),
        ("petroleum",              .tanker,          "Tanker — refined petroleum products"),
        ("diesel",                 .tanker,          "Tanker — diesel cargo"),
        ("gasoline",               .tanker,          "Tanker — gasoline cargo"),
        ("oil",                    .tanker,          "Tanker — oil cargo"),
        // Bulk
        ("coal",                   .bulkCarrier,     "Bulk carrier — coal (Capesize/Panamax)"),
        ("iron ore",               .bulkCarrier,     "Bulk carrier — iron ore (Capesize)"),
        ("grain",                  .bulkCarrier,     "Bulk carrier — grain (Handysize/Supramax)"),
        ("aggregate",              .bulkCarrier,     "Bulk carrier — aggregate / bulk material"),
        ("ore",                    .bulkCarrier,     "Bulk carrier — ore concentrate"),
        // RoRo
        ("vehicle",                .roRo,            "RoRo — wheeled cargo (autos, heavy equipment)"),
        ("car",                    .roRo,            "RoRo — automobile shipment"),
        ("auto",                   .roRo,            "RoRo — automobile shipment"),
        ("heavy equipment",        .roRo,            "RoRo — wheeled heavy equipment"),
        ("project cargo",          .roRo,            "RoRo — oversized project cargo, rolled aboard"),
        // Container generic
        ("container",              .containerShip,   "Container ship — generic FEU/TEU box cargo"),
        ("palletized",             .containerShip,   "Container ship — palletized FCL"),
        ("pallets",                .containerShip,   "Container ship — palletized FCL"),
    ]

    /// Pick the recommended vessel class. Hard-overrides
    /// (isWheeled / isCryogenic / requiresColdChain) fire first;
    /// otherwise keyword + tonnage heuristics decide.
    public static func recommend(_ input: Input) -> Recommendation {
        // Hard overrides — take precedence over keyword matching.
        if input.isCryogenic {
            return .init(pick: .lng,
                         rationale: "Cryogenic flag set — LNG-class containment required",
                         confidence: .high)
        }
        if input.isWheeled {
            return .init(pick: .roRo,
                         rationale: "Wheeled cargo — RoRo (roll-on / roll-off) is the only canonical match",
                         confidence: .high)
        }
        if input.requiresColdChain {
            return .init(pick: .reeferContainer,
                         rationale: "Cold-chain flag set — refrigerated container ship",
                         confidence: .high)
        }

        // Keyword match against commodity.
        let normalized = input.commodity.lowercased()
        if let match = keywordTable.first(where: { normalized.contains($0.keyword) }) {
            // Tonnage refinement — boost confidence to .high when the
            // tonnage signal aligns with the pick (e.g., > 10k MT bulk).
            let confidence: Recommendation.Confidence = {
                if let mt = input.metricTons, mt >= 10000, match.pick == .bulkCarrier {
                    return .high
                }
                if let mt = input.metricTons, mt >= 50000, match.pick == .tanker {
                    return .high
                }
                return .medium
            }()
            return .init(pick: match.pick,
                         rationale: match.rationale,
                         confidence: confidence)
        }

        // Hazmat class fallback — if no keyword matched but a hazmat
        // class is set, route Class 2.x to LNG-class and Class 3
        // to a tanker (the dominant patterns at sea).
        if input.hazmatClass.hasPrefix("2.") {
            return .init(pick: .lng,
                         rationale: "Class \(input.hazmatClass) gas — vessel-class containment defaults to LNG-style",
                         confidence: .medium)
        }
        if input.hazmatClass == "3" {
            return .init(pick: .tanker,
                         rationale: "Class 3 flammable liquid — tanker is the canonical vessel class",
                         confidence: .medium)
        }

        // Default fallback — broadest-coverage class.
        return .init(pick: defaultClass,
                     rationale: "No specific signal — defaulting to container ship (broadest cargo coverage)",
                     confidence: .low)
    }
}
