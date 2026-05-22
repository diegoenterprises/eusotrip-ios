//
//  HereHaulBridge.swift
//  EusoTrip — the seam between HERE monetization add-ons and The Haul.
//
//  2026-05-22: the HERE map surfaces monetization pins (sponsored
//  ad-zones) and affiliate amenities (fuel / EV / truck stops / parking).
//  This bridge turns *engaging* one of those into a gamification reward in
//  The Haul (XP + Haul points + mission progress), so the monetization
//  layer and the gamification layer are one loop instead of two silos:
//
//     tap a sponsored ad-zone / fuel-affiliate pin
//        → HereAddOnDetailCard "Claim in The Haul" CTA
//        → HereHaulBridge.engage(detail)
//        → posts `.eusoHaulReward` (The Haul UI credits instantly)
//        + best-effort starts the matching server "special" mission
//        → driver sees +XP / +Haul pts, mission progress, territory.
//
//  locationAnalytics coverage (states / metros / corridor km) feeds the
//  same loop as territory progress via `recordCoverage`.
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
    /// Posted when locationAnalytics coverage updates territory progress.
    /// `object` is a `HaulTerritoryEvent`.
    static let eusoHaulTerritory = Notification.Name("eusoHaulTerritory")
}

/// What a monetization / amenity engagement is worth in The Haul.
public struct HaulRewardEvent: Hashable {
    public let sourceId: String        // pin id (adzone:… / fuel:… / ev:…)
    public let kind: HereMarker.Kind
    public let title: String
    public let xp: Int
    public let points: Int
    public let reason: String
    public init(sourceId: String, kind: HereMarker.Kind, title: String,
                xp: Int, points: Int, reason: String) {
        self.sourceId = sourceId; self.kind = kind; self.title = title
        self.xp = xp; self.points = points; self.reason = reason
    }
}

/// Territory progress derived from HERE locationAnalytics coverage.
public struct HaulTerritoryEvent: Hashable {
    public let states: [String]
    public let metros: [String]
    public let totalKm: Double
    public init(states: [String], metros: [String], totalKm: Double) {
        self.states = states; self.metros = metros; self.totalKm = totalKm
    }
}

@MainActor
public final class HereHaulBridge {
    public static let shared = HereHaulBridge()
    private init() {}

    /// XP / Haul-points a monetization or amenity engagement is worth.
    /// Sponsored ad-zones are the monetization headline, so they pay most.
    public static func reward(for kind: HereMarker.Kind) -> (xp: Int, points: Int) {
        switch kind {
        case .adZone:    return (50, 25)   // sponsored / SAE-ODD zone — monetization
        case .fuel:      return (15, 10)   // fuel affiliate
        case .charger:   return (15, 10)   // EV affiliate
        case .truckStop: return (10, 5)    // amenity affiliate
        case .parking:   return (8, 4)
        case .weigh:     return (5, 0)
        default:         return (0, 0)     // weather / camera / alert = informational
        }
    }

    public static func isRewardable(_ kind: HereMarker.Kind) -> Bool {
        reward(for: kind).xp > 0
    }

    /// Engage a monetization / amenity pin → credit The Haul. Posts a local
    /// reward event (instant UI), and best-effort starts the matching
    /// server "special" mission. Returns a short confirmation for the card.
    @discardableResult
    public func engage(_ detail: HereAddOnDetail) async -> String {
        let r = Self.reward(for: detail.kind)
        guard r.xp > 0 else { return "Noted" }

        let reason: String
        switch detail.kind {
        case .adZone:  reason = "Entered sponsored zone “\(detail.title)”"
        case .fuel:    reason = "Fueled at \(detail.title)"
        case .charger: reason = "Charged at \(detail.title)"
        default:       reason = "Visited \(detail.title)"
        }

        let event = HaulRewardEvent(
            sourceId: detail.id, kind: detail.kind, title: detail.title,
            xp: r.xp, points: r.points, reason: reason)
        NotificationCenter.default.post(name: .eusoHaulReward, object: event)

        // Best-effort server credit: start the first open "special"
        // (sponsorship / engagement) mission so it shows in mission progress.
        Task {
            if let missions = try? await EusoTripAPI.shared.gamification.getMissions(category: "special") {
                let pool = missions.available + missions.active
                if let target = pool.first(where: { ($0.status ?? "") != "claimed" }) {
                    _ = try? await EusoTripAPI.shared.gamification.startMission(missionId: target.id)
                }
            }
        }

        return "+\(r.xp) XP · +\(r.points) Haul pts"
    }

    /// Push HERE locationAnalytics coverage into The Haul as territory
    /// progress (leaderboards + territory badges). Fails soft.
    func recordCoverage(breadcrumbs: [HereMapsAPI.Breadcrumb]) async {
        guard !breadcrumbs.isEmpty else { return }
        guard let summary = try? await EusoTripAPI.shared.hereMaps.locationAnalytics(breadcrumbs: breadcrumbs)
        else { return }
        let event = HaulTerritoryEvent(
            states: summary.uniqueStates ?? [],
            metros: summary.uniqueMetros ?? [],
            totalKm: summary.totalKm ?? 0)
        NotificationCenter.default.post(name: .eusoHaulTerritory, object: event)
    }
}
