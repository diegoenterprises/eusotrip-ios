//
//  DriverLoadActivity.swift
//  EusoTrip — shared ActivityKit attributes between iOS + watchOS.
//
//  One Live Activity per active load. Shown on:
//    - iOS Lock Screen (phone)
//    - Dynamic Island (phone)
//    - Smart Stack (watch)
//
//  Spec §7. Phase 2 deliverable.
//

import ActivityKit
import Foundation

struct DriverLoadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var phase: String          // "en_route_pickup" | "loading" | "en_route_delivery" | "unloading"
        public var etaMinutes: Int
        public var nextWaypoint: String   // "Pickup at Walmart DC 7212"
        public var milesRemaining: Int
        public var hosDriveRemainingMinutes: Int
        public var weatherFlag: String?   // "severe-thunderstorm" | "wind-advisory" | nil
    }

    public var loadDisplayId: String      // "LD-48291"
    public var originCity: String
    public var destCity: String
    public var brokerName: String?
    public var hazmat: Bool
}
