//
//  HereHaulBridge.swift
//  EusoTrip — the seam between HERE monetization add-ons and The Haul.
//
//  HERE map surfaces expose sponsored zones and operational amenities. This
//  bridge submits only a source identity and active-load intent. The server
//  verifies assignment, persisted location, HOS, provider identity, distance,
//  policy, idempotency, and the final Standing / Haul Miles award:
//
//     tap a sponsored ad-zone / fuel-affiliate pin
//        → HereAddOnDetailCard "Claim in The Haul" CTA
//        → HereHaulBridge.engage(detail)
//        → posts `.eusoHaulReward` only after a committed server credit.
//
//  The Haul dashboard (060) observes `.eusoHaulReward` to surface the
//  reward toast + refresh the profile.
//
//  Powered by ESANG AI™.
//

import Foundation
import SwiftUI

public extension Notification.Name {
    /// Posted when a HERE monetization / amenity engagement earns a Haul
    /// reward. `object` is a `HaulRewardEvent`.
    static let eusoHaulReward = Notification.Name("eusoHaulReward")
}

/// A server-confirmed HERE visit award.
public struct HaulRewardEvent: Hashable {
    public let sourceId: String
    public let kind: HereMarker.Kind
    public let title: String
    public let standingXp: Int
    public let haulMiles: Int
    public let reason: String
    public init(sourceId: String, kind: HereMarker.Kind, title: String,
                standingXp: Int, haulMiles: Int, reason: String) {
        self.sourceId = sourceId; self.kind = kind; self.title = title
        self.standingXp = standingXp; self.haulMiles = haulMiles; self.reason = reason
    }
}

public struct HereHaulEngagementResult: Hashable {
    public let message: String
    public let accepted: Bool
    public let credited: Bool
}

@MainActor
public final class HereHaulBridge {
    public static let shared = HereHaulBridge()
    private init() {}

    public static func isRewardable(_ kind: HereMarker.Kind) -> Bool {
        switch kind {
        case .adZone, .fuel, .charger, .truckStop, .parking, .weigh:
            return true
        default:
            return false
        }
    }

    /// The client submits optional load context but never selects discovery
    /// versus visit verification. The authenticated server derives that action
    /// from role, assignment, persisted location, HOS, and policy evidence.
    @discardableResult
    public func engage(_ detail: HereAddOnDetail) async -> HereHaulEngagementResult {
        guard Self.isRewardable(detail.kind) else {
            return HereHaulEngagementResult(message: "Informational map item", accepted: false, credited: false)
        }
        let loadId = DriverGPSPushService.shared.currentLoadId
        let engagement = GamificationAPI.HereEngagementOutcome(
            sourceId: detail.id,
            kind: detail.kind.rawValue
        )

        do {
            let response = try await EusoTripAPI.shared.gamification.recordHereDeliveryOutcome(
                loadId: loadId,
                engagement: engagement
            )
            let newlyCredited = response.status == "credited"
            let alreadyCredited = response.status == "already_credited"
            if newlyCredited {
                let event = HaulRewardEvent(
                    sourceId: response.source.id,
                    kind: detail.kind,
                    title: response.source.title ?? detail.title,
                    standingXp: response.reward.standingXp,
                    haulMiles: response.reward.haulMiles,
                    reason: response.message
                )
                NotificationCenter.default.post(name: .eusoHaulReward, object: event)
            }
            let message = newlyCredited
                ? "+\(response.reward.standingXp) XP"
                    + (response.reward.haulMiles > 0 ? " · +\(response.reward.haulMiles) Haul Miles" : "")
                : response.message
            return HereHaulEngagementResult(
                message: message,
                accepted: newlyCredited || alreadyCredited || response.status == "recorded",
                credited: newlyCredited
            )
        } catch {
            return HereHaulEngagementResult(
                message: "Check-in not confirmed. Try again.",
                accepted: false,
                credited: false
            )
        }
    }
}
