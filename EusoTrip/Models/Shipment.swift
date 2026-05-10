//
//  Shipment.swift
//  EusoTrip — Multi-vehicle parent shipment data model.
//
//  Mirrors the server-side shape documented in
//  ~/Desktop/todays work/01_animation_system_instructions/MULTI_VEHICLE_LOAD_ARCHITECTURE.md
//  and ~/Desktop/todays work/03_wiring_stubs/server/shipmentTypes.ts.
//
//  The atomic unit on EusoTrip is **one Shipment with N typed
//  Vehicles** — not (one truck = one driver = one carrier) like
//  every TMS today. A heavy-haul wind-blade move with one tractor +
//  two pilot cars + one chase truck is ONE Shipment with FOUR
//  Vehicles, sharing one parent BOL, one customs filing, one
//  settlement, one audit chain. Per the founder doctrine: "the
//  unowned greenfield is the unified parent model".
//
//  Powered by ESANG AI™.
//

import Foundation

// ============================================================================
// MARK: - Parent shipment
// ============================================================================

/// The atomic Shipment record. Holds 1..N vehicles, the unified
/// parent BOL, the cargo + region facts, the audit-chain anchor,
/// and the derived parent state (`parentStateDerivation()`).
public struct Shipment: Identifiable, Codable, Hashable {
    public let id: String                          // EUSOSHP-2026-0001
    public let parentBolNumber: String             // unified BOL across all vehicles
    public let shipperOrgId: String
    public let consigneeOrgId: String
    public let vertical: String                    // "tanker_hazmat", "reefer", …
    public let region: String                      // "us" | "us-mx" | "us-ca" | "mx-ca" | "us-mx-ca"
    public let totalWeight: Double
    public let totalValue: Double                  // for insurance + Triumph Factor-of-Record
    public let hazmatPresent: Bool
    public let customsRequired: Bool

    /// Derived from `vehicles[].childState` via
    /// `parentStateDerivation()`. Persisted on the parent so any
    /// surface that reads only the shipment record gets the
    /// authoritative state without re-running the derivation.
    public let parentState: ParentShipmentState

    /// 1..N vehicles. Order matches `LegSpec.sequenceNumber`.
    public let vehicles: [Vehicle]

    /// Pickup → handoff → delivery sequence. Populated for multi-leg
    /// (intermodal, drayage→rail→drayage, etc); single-vehicle
    /// shipments leave this empty.
    public let stops: [ShipmentStop]

    /// When cargo crosses Vehicle A → Vehicle B. Empty for
    /// single-vehicle shipments.
    public let handoffs: [Handoff]

    /// Convoy timing rules — escort lead-chase departure offset,
    /// minimum/maximum following distance, sync-window violations
    /// trigger detention or AV-eligibility loss.
    public let syncWindows: [SyncWindow]

    /// VUCEM (MX) / CBP ACE (US) / CBSA ACI (CA) per cross-border
    /// leg. Each filing carries its own status independent of the
    /// parent shipment state.
    public let customsFilings: [CustomsFiling]

    // MARK: - Settlement

    /// Total contract revenue from the shipper. Single dollar amount
    /// regardless of split-tender — broker / shipper sees the parent.
    public let parentRate: Money

    /// Per-child carrier payouts. Sum may differ from `parentRate`
    /// when broker margin is stripped per leg.
    public let vehicleRates: [Money]

    /// Set when the settlement engine has materialized the unified
    /// invoice. Nil for shipments still in flight.
    public let parentInvoiceId: String?

    // MARK: - Audit chain

    /// First sha256 hash of the chain. Every audit-chain row links
    /// back to this anchor via `prevHash`.
    public let hashChainAnchor: String

    // MARK: - Convenience

    /// True when ≥ 4 children OR vertical is "specialized" — the
    /// build sequence ticket calls this out as the "project cargo"
    /// path (escorted oversize, multi-trailer wind blade, etc).
    public var isProjectCargo: Bool {
        vehicles.count >= 4 || vertical == "specialized"
    }

    /// True when at least one cross-border leg is on the route.
    /// Drives the customs-filing UI gate on the wizard.
    public var isCrossBorder: Bool {
        region.contains("-")
    }
}

// ============================================================================
// MARK: - Vehicle (typed child)
// ============================================================================

/// One participant in a Shipment. Vehicles are typed: primary
/// load-bearing, secondary load-bearing (split cargo), escort lead,
/// escort chase, team driver (second driver in same vehicle), relay
/// (handoff successor), AV (autonomous platform), AV-handoff-human
/// (human meeting AV at transfer hub).
public struct Vehicle: Identifiable, Codable, Hashable {
    public let id: String                          // EUSOVEH-2026-0001-A
    public let shipmentId: String                  // foreign key to parent
    public let role: VehicleRole
    public let modality: VehicleModality
    public let equipment: EquipmentSpec
    public let driverIds: [String]                 // 1 for solo, 2 for team
    public let carrierId: String                   // catalyst / 3PL
    public let leg: LegSpec
    public let cargoSplit: CargoSplit
    public let childState: String                  // 55-state lifecycle (raw)
    public let animationManifestId: String         // resolves to one of the 33 SVG kinds
    public let geofenceEvents: [GeofenceEvent]
    public let hazmatChain: HazmatPlacardChain?    // per-vehicle placard history
    public let identityChain: [IdentityVerification]
}

public enum VehicleRole: String, Codable, Hashable {
    /// Main load-bearing vehicle.
    case primary
    /// Additional load-bearing vehicle on the same shipment (split
    /// cargo — heavy-haul, autorack, container train, tanker convoy).
    case secondary
    /// Pilot car ahead of an oversize move.
    case escortLead = "escort_lead"
    /// Chase car behind an oversize move.
    case escortChase = "escort_chase"
    /// State-trooper escort (highest-tier permit moves).
    case escortStateTrooper = "escort_state_trooper"
    /// Second driver in the same vehicle (sleeper-berth team driving).
    case teamDriver = "team_driver"
    /// Successor that takes over at a relay handoff.
    case relay
    /// Autonomous platform vehicle (Aurora / Plus / Kodiak / Gatik /
    /// Waabi / Embark / TuSimple).
    case av
    /// Human driver receiving from / handing off to an AV at a
    /// transfer hub.
    case avHandoffHuman = "av_handoff_human"
}

public enum VehicleModality: String, Codable, Hashable {
    case truck, rail, vessel
}

public struct EquipmentSpec: Codable, Hashable {
    public let type: String                        // "53_dry_van", "MC_331_tanker", …
    public let label: String                       // "53' DRY VAN"
    public let subtitle: String?
    public let trailerId: String?
    public let licensePlate: String?
    public let reportingMarks: String?             // rail (AAR mark + number)
    public let containerBicCode: String?
    public let containerIsoCode: String?
    public let vesselName: String?
    public let imoNumber: String?
    public let mmsi: String?
}

public struct LegSpec: Codable, Hashable {
    public let sequenceNumber: Int                 // 1, 2, 3 in order
    public let origin: GeoPoint
    public let destination: GeoPoint
    public let plannedDepartTs: Date?
    public let plannedArriveTs: Date?
    public let actualDepartTs: Date?
    public let actualArriveTs: Date?
    public let modeTransition: LegModeTransition
    public let predecessorVehicleId: String?
    public let successorVehicleId: String?
}

public enum LegModeTransition: String, Codable, Hashable {
    case origin
    case railRamp = "rail-ramp"
    case portGate = "port-gate"
    case transferHubAv = "transfer-hub-av"
    case destination
}

public struct GeoPoint: Codable, Hashable {
    public let lat: Double
    public let lng: Double
    public let label: String?
}

public struct CargoSplit: Codable, Hashable {
    public let weightAllocated: Double             // lbs / kg per child
    public let unitsAllocated: Int                 // pallets / containers / VINs
    public let itemRangeStart: Int?                // serialized cargo (autorack VINs)
    public let itemRangeEnd: Int?
    public let hazmatProportionAllocated: Double?  // 0.0..1.0 of parent total
}

public struct GeofenceEvent: Codable, Hashable {
    public let zoneType: String
    public let zoneId: String
    public let event: String                       // "enter" | "exit" | "dwell"
    public let timestamp: Date
}

/// Per-vehicle hazmat placard history. Drives the runtime placard
/// swap on the SVG animation (e.g. when a tank gets cleaned + re-
/// placarded between loads, the next tour shows the new class).
public struct HazmatPlacardChain: Codable, Hashable {
    public let entries: [HazmatPlacardEntry]
}

public struct HazmatPlacardEntry: Codable, Hashable {
    public let unNumber: String                    // "UN1075"
    public let hazmatClass: String                 // "2.1"
    public let placardSymbolId: String             // "class2_1Placard"
    public let appliedAt: Date
    public let appliedByUserId: String
}

/// One identity-verification check. Driven by the Highway adapter
/// (build sequence T8.1-T8.4). Per Highway Q1 2026 finding: half of
/// theft incidents involve carriers with clean records — identity
/// has to be continuous, not one-time.
public struct IdentityVerification: Codable, Hashable {
    public let timestamp: Date
    public let trigger: String                     // "tender_accept", "departed_pickup", …
    public let mcStatus: String                    // "active" | "inactive" | "out_of_service"
    public let saferSnapshotAgeHr: Double
    public let rightfulOwnerMatch: Bool
    public let dispatchServiceDetected: Bool
    public let passed: Bool
}

// ============================================================================
// MARK: - Stops, handoffs, sync windows
// ============================================================================

public struct ShipmentStop: Codable, Hashable, Identifiable {
    public let id: String
    public let sequence: Int
    public let stopType: String                    // "pickup", "delivery", "rail_ramp", "port_gate"
    public let location: GeoPoint
    public let appointmentStart: Date?
    public let appointmentEnd: Date?
    public let actualArrival: Date?
    public let actualDeparture: Date?
}

/// A handoff = one Vehicle's cargo transfers to another Vehicle. May
/// be at a rail ramp, port terminal, AV transfer hub, or simple
/// driver relay rest stop.
public struct Handoff: Codable, Hashable, Identifiable {
    public let id: String
    public let fromVehicleId: String
    public let toVehicleId: String
    public let location: GeoPoint
    public let plannedTs: Date
    public let actualTs: Date?
    public let state: HandoffState
}

public enum HandoffState: String, Codable, Hashable {
    case planned, inProgress = "in_progress", completed, failed
}

/// Convoy timing constraints — escort lead must be 1-3 minutes ahead
/// of the primary, chase must be 1-3 minutes behind, etc. ML
/// breach-probability model lives at
/// ~/Desktop/todays work/03_wiring_stubs/ml/syncWindowFeatureExtractor.ts
public struct SyncWindow: Codable, Hashable, Identifiable {
    public let id: String
    public let kind: String                        // "escort_lead", "convoy_following", …
    public let vehicleIds: [String]
    public let leadOffsetSec: Double               // seconds ahead/behind
    public let toleranceSec: Double
    public let breaches: [SyncWindowBreach]
}

public struct SyncWindowBreach: Codable, Hashable {
    public let timestamp: Date
    public let severity: String                    // "warn" | "block"
    public let reason: String
}

// ============================================================================
// MARK: - Customs filings
// ============================================================================

public struct CustomsFiling: Codable, Hashable, Identifiable {
    public let id: String
    public let system: CustomsSystem
    public let direction: String                   // "us_to_mx", "us_to_ca", etc.
    public let referenceNumber: String?
    public let status: CustomsFilingStatus
    public let filedAt: Date?
    public let releasedAt: Date?
    public let usmcaCertificateUrl: String?
}

public enum CustomsSystem: String, Codable, Hashable {
    case cbpAce = "CBP_ACE"      // US
    case cbsaAci = "CBSA_ACI"    // CA inbound
    case cbsaCarm = "CBSA_CARM"  // CA RPP declaration
    case satVucem = "SAT_VUCEM"  // MX
    case satPedimento = "SAT_PEDIMENTO"
}

public enum CustomsFilingStatus: String, Codable, Hashable {
    case draft, submitted, accepted, hold, released, rejected
}

// ============================================================================
// MARK: - Money
// ============================================================================

public struct Money: Codable, Hashable {
    public let amount: Decimal
    public let currency: String                    // "USD", "MXN", "CAD"
}

// ============================================================================
// MARK: - Parent shipment state (derived)
// ============================================================================

/// Every Shipment's parent state. Derived from `vehicles[].childState`
/// via `parentStateDerivation()`. Exception bubbling wins (any
/// blocking exception → `EXCEPTION_BLOCKING`); otherwise the lowest
/// common state across children is the parent state.
public enum ParentShipmentState: String, Codable, Hashable {
    case draft = "DRAFT"
    case posted = "POSTED"
    /// Some children tendered, some not.
    case tenderedPartial = "TENDERED_PARTIAL"
    /// All children tendered.
    case tenderedFull = "TENDERED_FULL"
    /// Some children booked.
    case bookedPartial = "BOOKED_PARTIAL"
    /// All children booked.
    case bookedFull = "BOOKED_FULL"
    /// Convoy started — at least one vehicle is past `BOOKED`.
    case inProgress = "IN_PROGRESS"
    /// Currently at a multi-vehicle handoff point.
    case atHandoff = "AT_HANDOFF"
    /// All vehicles in transit.
    case inTransitFull = "IN_TRANSIT_FULL"
    /// Some children delivered.
    case partiallyDelivered = "PARTIALLY_DELIVERED"
    /// All children delivered.
    case delivered = "DELIVERED"
    /// Some POD signed.
    case podPartial = "POD_PARTIAL"
    /// All POD signed.
    case podFull = "POD_FULL"
    /// Any child in non-blocking exception state.
    case exceptionAny = "EXCEPTION_ANY"
    /// Any child in blocking exception state — settlement frozen.
    case exceptionBlocking = "EXCEPTION_BLOCKING"
    /// Settlement run, all parties paid, audit chain sealed.
    case complete = "COMPLETE"
    case cancelled = "CANCELLED"
}

/// Child-level lifecycle states the derivation rule uses to roll up
/// to the parent. Mirrors the canonical 55-state taxonomy in
/// ~/Desktop/RIOS_LOAD_LIFECYCLE_ARCHITECTURE_2026-05-10.md §3.
public enum ChildLifecycleSet {
    /// Child states that count as "blocking exception" — bubble up
    /// to `ParentShipmentState.exceptionBlocking`.
    public static let blocking: Set<String> = [
        "HAZMAT_INCIDENT",
        "CONTAMINATION_REJECT",
        "SEAL_BREACH",
        "WEIGHT_VIOLATION",
        "REEFER_BREAKDOWN",
        "IDENTITY_RE_VERIFICATION_REQUIRED",
        "CUSTOMS_HOLD",
    ]

    public static let booked: Set<String> = [
        "ACCEPTED", "ASSIGNED", "CONFIRMED",
        "EQUIPMENT_VERIFIED", "HAZMAT_CLASS_VALIDATED",
        "BRIDGE_CLEARANCE_CHECKED",
    ]

    public static let inHandoff: Set<String> = [
        "AV_HUMAN_HANDOFF",
        "RAIL_RAMP_IN", "RAIL_RAMP_OUT",
        "VESSEL_GATE_IN",
    ]

    public static let inTransit: Set<String> = [
        "IN_TRANSIT", "IN_TRANSIT_AUTONOMOUS",
        "EN_ROUTE_PICKUP", "EN_ROUTE_DELIVERY",
        "RAIL_LINEHAUL", "VESSEL_LOADED",
    ]

    public static let delivered: Set<String> = [
        "DELIVERED", "VESSEL_DISCHARGED", "RAIL_RAMP_OUT",
    ]

    public static let podSigned: Set<String> = [
        "POD_PENDING", "DELIVERED",
    ]

    public static let cancelled: Set<String> = [
        "CANCELLED",
    ]
}
