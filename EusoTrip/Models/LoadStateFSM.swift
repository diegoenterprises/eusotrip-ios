//
//  LoadStateFSM.swift
//  Canonical load-cycle FSM — base states + every vertical / mode overlay.
//
//  Locks the FSM into the Swift type system. The audit found 13/13 base states
//  present but ZERO overlay states modeled (hazmat / reefer / livestock /
//  heavy-haul / cross-border / AV-handoff / rail-specific / vessel-specific).
//  This file declares them all so server-strings round-trip through a typed
//  enum and every consumer (driver UI, dispatch, settlement, audit chain) can
//  switch exhaustively.
//
//  Drop into: EusoTrip/Models/LoadStateFSM.swift
//
//  T-001 LANDING NOTE (2026-05-20):
//  The canonical spec also declared a `TransportMode` enum here
//  (truck/rail/vessel/barge/intermodal). That collided with the existing
//  production `TransportMode` in `Models/Multimodal/MultiModalCore.swift:24`,
//  referenced across MultiModalCore + AuthModels + 204_ShipperPostLoad + the
//  wizard. To honor T-001's "compile-only, no behavior change" promise the
//  duplicate declaration was removed; references in this file resolve to
//  `MultiModalCore.TransportMode`. The intermodal case is deferred —
//  every existing consumer assumes 4 modes (truck/rail/vessel/barge), and
//  adding `intermodal` would require touching every exhaustive switch.
//  Track as a separate ticket when intermodal mode UI lands.
//

import Foundation

// MARK: - Base load-cycle states (all trailers)

public enum LoadState: String, CaseIterable, Codable, Hashable {
    case draft                = "DRAFT"
    case posted               = "POSTED"
    case tenderedPartial      = "TENDERED_PARTIAL"
    case tenderedFull         = "TENDERED_FULL"
    case booked               = "BOOKED"
    case enRouteToPickup      = "EN_ROUTE_TO_PICKUP"
    case atPickup             = "AT_PICKUP"
    case loaded               = "LOADED"
    case enRouteToDelivery    = "EN_ROUTE_TO_DELIVERY"
    case atDelivery           = "AT_DELIVERY"
    case unloaded             = "UNLOADED"
    case delivered            = "DELIVERED"
    case podSigned            = "POD_SIGNED"
    case settled              = "SETTLED"
    case cancelled            = "CANCELLED"
    case exception            = "EXCEPTION"

    public var bucket: LoadStateBucket {
        switch self {
        case .draft, .posted:                                    return .preBooking
        case .tenderedPartial, .tenderedFull, .booked:           return .booked
        case .enRouteToPickup, .atPickup, .loaded:               return .pickup
        case .enRouteToDelivery, .atDelivery, .unloaded:         return .delivery
        case .delivered, .podSigned:                             return .closeout
        case .settled:                                           return .settled
        case .cancelled, .exception:                             return .terminal
        }
    }
}

public enum LoadStateBucket: String, Codable {
    case preBooking, booked, pickup, delivery, closeout, settled, terminal
}

// MARK: - Overlay states by compliance bucket

/// Hazmat overlay (49 CFR 172 / 177 / ERG 2024).
public enum HazmatOverlay: String, CaseIterable, Codable {
    case ergVerified            = "HAZMAT.ERG_VERIFIED"             // at DRAFT
    case placardsAffixed        = "HAZMAT.PLACARDS_AFFIXED"         // at LOADED
    case segregationVerified    = "HAZMAT.SEGREGATION_VERIFIED"     // at LOADED (49 CFR 177.848)
    case hazmatLoaded           = "HAZMAT.LOADED"                   // between LOADED and EN_ROUTE_TO_DELIVERY
    case emergencyResponseReady = "HAZMAT.EMERGENCY_RESPONSE_READY" // at LOADED
}

/// Refrigerated / food-grade overlay (FSMA, FDA, USDA).
public enum ReeferOverlay: String, CaseIterable, Codable {
    case tempSetpointConfirmed = "REEFER.TEMP_SETPOINT_CONFIRMED"   // at AT_PICKUP
    case coldChainVerified     = "REEFER.COLD_CHAIN_VERIFIED"       // at AT_DELIVERY
    case tempLogSealed         = "REEFER.TEMP_LOG_SEALED"           // at POD_SIGNED
    case fsmaCertificateOnFile = "REEFER.FSMA_CERT_ON_FILE"         // at DRAFT
}

/// Livestock overlay (USDA, FMCSA 28-hour law).
public enum LivestockOverlay: String, CaseIterable, Codable {
    case usdaInspectionPassed  = "LIVESTOCK.USDA_INSPECTION_PASSED" // at AT_PICKUP
    case timer28hArmed         = "LIVESTOCK.28HR_TIMER_ARMED"       // at LOADED
    case restRequired          = "LIVESTOCK.REST_REQUIRED"          // if 28h breached
    case healthCertOnFile      = "LIVESTOCK.HEALTH_CERT_ON_FILE"    // at DRAFT
    case animalWelfareVerified = "LIVESTOCK.ANIMAL_WELFARE_VERIFIED"
}

/// Heavy haul / oversize / overweight overlay.
public enum HeavyHaulOverlay: String, CaseIterable, Codable {
    case permitsVerified           = "HEAVY_HAUL.PERMITS_VERIFIED"             // at DRAFT
    case routeSurveyComplete       = "HEAVY_HAUL.ROUTE_SURVEY_COMPLETE"        // at DRAFT
    case escortsAssigned           = "HEAVY_HAUL.ESCORTS_ASSIGNED"             // at BOOKED
    case bridgeClearanceVerified   = "HEAVY_HAUL.BRIDGE_CLEARANCE_VERIFIED"    // at LOADED
    case convoyComposed            = "HEAVY_HAUL.CONVOY_COMPOSED"
}

/// Cross-border overlay (US/MX/CA).
public enum CrossBorderOverlay: String, CaseIterable, Codable {
    case usmcaCertificateOnFile = "CROSS_BORDER.USMCA_CERT_ON_FILE"        // at DRAFT
    case enRouteToCrossing      = "CROSS_BORDER.EN_ROUTE_TO_CROSSING"
    case atBorder               = "CROSS_BORDER.AT_BORDER"
    case customsFiled           = "CROSS_BORDER.CUSTOMS_FILED"
    case customsCleared         = "CROSS_BORDER.CUSTOMS_CLEARED"
    case clearedBorder          = "CROSS_BORDER.CLEARED_BORDER"
    case ePodLockArmed          = "CROSS_BORDER.EPOD_LOCK_ARMED"
}

/// Autonomous vehicle handoff overlay.
public enum AvHandoffOverlay: String, CaseIterable, Codable {
    case oddPreCheckPassed       = "AV.ODD_PRECHECK_PASSED"           // at BOOKED
    case handoffPending          = "AV.HANDOFF_PENDING"
    case dispatched              = "AV.DISPATCHED"
    case handoffComplete         = "AV.HANDOFF_COMPLETE"
    case faultRecoveryInProgress = "AV.FAULT_RECOVERY"
}

/// Rail-mode-specific overlay states.
public enum RailOverlay: String, CaseIterable, Codable {
    case yardPlacement      = "RAIL.YARD_PLACEMENT"
    case interchangeTransfer = "RAIL.INTERCHANGE_TRANSFER"
    case waybillFiled       = "RAIL.WAYBILL_FILED"
    case customsRelease     = "RAIL.CUSTOMS_RELEASE"           // for cross-border rail
    case fullyRailed        = "RAIL.EN_ROUTE_FULLY_RAILED"
    case ramped             = "RAIL.RAMPED"                    // for intermodal drayage handoff
}

/// Vessel-mode-specific overlay states.
public enum VesselOverlay: String, CaseIterable, Codable {
    case gateIn                  = "VESSEL.GATE_IN"
    case loadPlanConfirmed       = "VESSEL.LOAD_PLAN_CONFIRMED"
    case stowPlanVerified        = "VESSEL.STOW_PLAN_VERIFIED"
    case departure               = "VESSEL.DEPARTURE"
    case inTransitAtSea          = "VESSEL.IN_TRANSIT_AT_SEA"
    case arrivalAtPort           = "VESSEL.ARRIVAL_AT_PORT"
    case customsClearance        = "VESSEL.CUSTOMS_CLEARANCE"
    case dischargeCompleted      = "VESSEL.DISCHARGE_COMPLETED"
    case pickupAvailable         = "VESSEL.PICKUP_AVAILABLE"   // for drayage leg 2
}

// MARK: - Composite state for a vehicle

/// A full state envelope: base state + every applicable overlay.
public struct CompositeLoadState: Codable, Hashable {
    public let base: LoadState
    public let hazmat: Set<HazmatOverlay>
    public let reefer: Set<ReeferOverlay>
    public let livestock: Set<LivestockOverlay>
    public let heavyHaul: Set<HeavyHaulOverlay>
    public let crossBorder: Set<CrossBorderOverlay>
    public let avHandoff: Set<AvHandoffOverlay>
    public let rail: Set<RailOverlay>
    public let vessel: Set<VesselOverlay>

    public init(
        base: LoadState,
        hazmat: Set<HazmatOverlay> = [],
        reefer: Set<ReeferOverlay> = [],
        livestock: Set<LivestockOverlay> = [],
        heavyHaul: Set<HeavyHaulOverlay> = [],
        crossBorder: Set<CrossBorderOverlay> = [],
        avHandoff: Set<AvHandoffOverlay> = [],
        rail: Set<RailOverlay> = [],
        vessel: Set<VesselOverlay> = []
    ) {
        self.base = base
        self.hazmat = hazmat
        self.reefer = reefer
        self.livestock = livestock
        self.heavyHaul = heavyHaul
        self.crossBorder = crossBorder
        self.avHandoff = avHandoff
        self.rail = rail
        self.vessel = vessel
    }

    /// Required overlay sets for a given (vertical, mode, crossBorder) tuple.
    public static func requiredOverlays(
        vertical: Vertical,
        mode: TransportMode,
        isCrossBorder: Bool,
        isAvDispatch: Bool
    ) -> (hazmat: Bool, reefer: Bool, livestock: Bool, heavyHaul: Bool,
          crossBorder: Bool, avHandoff: Bool, rail: Bool, vessel: Bool) {
        let overlay = vertical.complianceOverlay
        return (
            hazmat:      overlay == .hazmat || overlay == .tanker,
            reefer:      overlay == .coldChain,
            livestock:   overlay == .livestock,
            heavyHaul:   overlay == .heavyHaul,
            crossBorder: isCrossBorder,
            avHandoff:   isAvDispatch,
            rail:        mode == .rail,
            vessel:      mode == .vessel
        )
    }
}


// MARK: - State transition contract

/// Every state change is described by one of these.
public struct LoadStateTransition: Codable, Hashable {
    public let transitionId: String
    public let from: LoadState
    public let to: LoadState
    public let triggeredBy: String          // userId or "system"
    public let triggeredByRole: String      // driver, dispatcher, shipper, broker, ...
    public let ts: Date
    public let location: TransitionLocation?
    public let identityGatePassed: Bool
    public let identityCheckId: String?
    public let hash: String                 // SHA-256 of (from + to + triggeredBy + ts + prevHash)
    public let prevHash: String?
}

public struct TransitionLocation: Codable, Hashable {
    public let lat: Double
    public let lng: Double
    public let accuracyMeters: Double?
    public let geofenceId: String?
}
