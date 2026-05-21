//
//  GeminiBriefAdapter.swift
//  Daily Brief + Universal Cart client — IO 2026 P0-5.
//
//  Owns the iOS side of `esangBrief.getDailyBrief` + `esangBrief.dismissCard`
//  + `esangBrief.getUniversalCart`. Single observable adapter every
//  Home screen reads from so a Driver Home, Shipper Home, Dispatcher
//  Home, and Broker Home all see the same brief without re-fetching.
//
//  Wire types are RawValue-locked to the server enum in
//  `frontend/server/routers/esangBrief.ts`. Adding a new card kind
//  is a 3-line change: server enum + iOS `DailyBriefCardKind` +
//  the picker logic in the consuming view.
//
//  Drop into: EusoTrip/Services/GeminiBriefAdapter.swift
//

import Foundation
import Combine

// MARK: - Wire types (mirror server)

public enum DailyBriefCardKind: String, Codable, Hashable, Sendable {
    // Shipper
    case shipperActiveLoadsSummary       = "shipper.active_loads_summary"
    case shipperArAged                   = "shipper.ar_aged"
    case shipperEpodPending              = "shipper.epod_pending"
    case shipperHazmatPlacardsVerified   = "shipper.hazmat_placards_verified"
    case shipperReeferTempOk             = "shipper.reefer_temp_ok"
    // Broker
    case brokerRateConfirmationsExpiring = "broker.rate_confirmations_expiring"
    case brokerLanesUnderbid             = "broker.lanes_underbid"
    case brokerCarrierSafetyAlert        = "broker.carrier_safety_alert"
    // Dispatcher
    case dispatchDriversOnDuty           = "dispatch.drivers_on_duty"
    case dispatchHosWarnings             = "dispatch.hos_warnings"
    case dispatchRerouteRequired         = "dispatch.reroute_required"
    case dispatchExceptionsOpen          = "dispatch.exceptions_open"
    // Driver
    case driverNextPickup                = "driver.next_pickup"
    case driverHosRemaining              = "driver.hos_remaining"
    case driverWeatherAlert              = "driver.weather_alert"
    case driverDetentionLog              = "driver.detention_log"
    // Cross-role
    case commonGreeting                  = "common.greeting"
    case commonCartRecommendation        = "common.cart_recommendation"

    /// SF Symbol the iOS card row renders.
    public var systemImage: String {
        switch self {
        case .shipperActiveLoadsSummary:       return "truck.box"
        case .shipperArAged:                   return "dollarsign.circle"
        case .shipperEpodPending:              return "lock.shield"
        case .shipperHazmatPlacardsVerified:   return "exclamationmark.triangle"
        case .shipperReeferTempOk:             return "thermometer.snowflake"
        case .brokerRateConfirmationsExpiring: return "doc.text.below.ecg"
        case .brokerLanesUnderbid:             return "chart.line.downtrend.xyaxis"
        case .brokerCarrierSafetyAlert:        return "exclamationmark.shield"
        case .dispatchDriversOnDuty:           return "person.2.fill"
        case .dispatchHosWarnings:             return "timer"
        case .dispatchRerouteRequired:         return "arrow.triangle.branch"
        case .dispatchExceptionsOpen:          return "exclamationmark.bubble"
        case .driverNextPickup:                return "location.fill"
        case .driverHosRemaining:              return "clock.fill"
        case .driverWeatherAlert:              return "cloud.bolt"
        case .driverDetentionLog:              return "hourglass"
        case .commonGreeting:                  return "sun.max"
        case .commonCartRecommendation:        return "cart"
        }
    }
}

public enum DailyBriefSeverity: String, Codable, Hashable, Sendable {
    case info, notice, warning, critical
}

public struct DailyBriefCard: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: DailyBriefCardKind
    public let headline: String
    public let body: String?
    public let ctaPath: String?
    public let ctaLabel: String?
    public let severity: DailyBriefSeverity
    public let counter: Int?
    public let sampledAt: String
}

public enum CartRecommendationKind: String, Codable, Hashable, Sendable {
    case fuelCard         = "fuel_card"
    case permit           = "permit"
    case tollPass         = "toll_pass"
    case insurance        = "insurance"
    case factoring        = "factoring"
    case complianceModule = "compliance_module"

    public var systemImage: String {
        switch self {
        case .fuelCard:         return "fuelpump"
        case .permit:           return "doc.text"
        case .tollPass:         return "car"
        case .insurance:        return "checkmark.shield"
        case .factoring:        return "banknote"
        case .complianceModule: return "list.bullet.clipboard"
        }
    }
}

public struct CartRecommendation: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: CartRecommendationKind
    public let label: String
    public let rationale: String
    public let estValueUsd: Double?
    public let ctaPath: String
}

public struct DailyBrief: Codable, Hashable, Sendable {
    public let cards: [DailyBriefCard]
    public let cart: [CartRecommendation]
    public let sampledAt: String?
}

// MARK: - Adapter

/// Single observable surface every Home screen reads from. Pulls
/// the brief once per app session (or on pull-to-refresh) and
/// surfaces both the cards + the Universal Cart. Card dismissals
/// are tracked locally — the server doesn't persist them for v1.
@MainActor
public final class GeminiBriefAdapter: ObservableObject {
    public static let shared = GeminiBriefAdapter()

    @Published public private(set) var brief: DailyBrief = DailyBrief(cards: [], cart: [], sampledAt: nil)
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var loadError: String? = nil

    /// Set of card ids the user dismissed locally for today.
    @Published public private(set) var dismissedIds: Set<String> = []

    public init() {}

    /// Cards minus the locally-dismissed ones. Use this for rendering
    /// instead of `brief.cards`; the raw list stays intact so the
    /// next refresh re-evaluates the full set.
    public var visibleCards: [DailyBriefCard] {
        brief.cards.filter { !dismissedIds.contains($0.id) }
    }

    /// Pull the brief from the server. Optional vertical hint scopes
    /// shipper cards (a hazmat shipper doesn't see the reefer card).
    public func refresh(vertical: Vertical? = nil) async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        struct In: Encodable {
            let date: String?
            let vertical: String?
        }
        let input = In(date: nil, vertical: vertical?.rawValue)
        do {
            let result: DailyBrief = try await EusoTripAPI.shared.query(
                "esangBrief.getDailyBrief",
                input: input
            )
            brief = result
        } catch {
            loadError = (error as NSError).localizedDescription
        }
    }

    /// Mark a card dismissed locally (and tell the server for
    /// telemetry — the response is fire-and-forget).
    public func dismiss(_ cardId: String) async {
        dismissedIds.insert(cardId)
        do {
            struct In: Encodable { let cardId: String }
            struct Out: Decodable { let success: Bool; let cardId: String }
            let _: Out = try await EusoTripAPI.shared.mutation(
                "esangBrief.dismissCard", input: In(cardId: cardId)
            )
        } catch {
            // Non-critical — local state is the source of truth for the day.
        }
    }
}
