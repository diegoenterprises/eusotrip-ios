//
//  LifecycleStage.swift
//  EusoTrip — canonical 8-stage lifecycle strip (fix pack L01-2).
//
//  Mirror of server/shared/lifecycle.ts. Keep the two files in lockstep — when
//  the server map changes, change this file in the same PR. Every stage-strip /
//  progress-bar derivation should call `LifecycleStage.derive(status:)` rather
//  than re-bucketing statuses locally (the drift this file exists to kill —
//  305_CatalystLoadDetail's private enum adopts this on next touch).
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import Foundation

enum LifecycleStage: String, CaseIterable, Codable {
    case posted = "POSTED", bidding = "BIDDING", awarded = "AWARDED", pickup = "PICKUP"
    case inTransit = "IN_TRANSIT", delivery = "DELIVERY", paperwork = "PAPERWORK", closed = "CLOSED"

    /// TRUCK map — covers every value of the prod loads.status enum (48 values,
    /// verified against information_schema 2026-07-08, incl. tanker sub-states).
    static let truckStatusToStage: [String: LifecycleStage] = [
        "draft": .posted, "posted": .posted,
        "bidding": .bidding,
        "awarded": .awarded, "declined": .awarded, "lapsed": .awarded,
        "accepted": .awarded, "assigned": .awarded, "confirmed": .awarded,
        "en_route_pickup": .pickup, "at_pickup": .pickup, "pickup_checkin": .pickup,
        "locked": .pickup, "backing_in": .pickup, "brakes_set": .pickup,
        "connecting": .pickup, "loading_locked": .pickup, "loading": .pickup,
        "loading_exception": .pickup, "loaded": .pickup, "load_locked_filled": .pickup,
        "in_transit": .inTransit, "transit_hold": .inTransit, "transit_exception": .inTransit,
        "temp_excursion": .inTransit, "reefer_breakdown": .inTransit,
        "contamination_reject": .inTransit, "seal_breach": .inTransit, "weight_violation": .inTransit,
        "at_delivery": .delivery, "delivery_checkin": .delivery, "discharging": .delivery,
        "unloading": .delivery, "unloading_exception": .delivery, "unloaded": .delivery,
        "vapor_purging": .delivery, "disconnecting": .delivery, "detaching": .delivery,
        "released": .delivery,
        "pod_pending": .paperwork, "pod_rejected": .paperwork, "delivered": .paperwork,
        "invoiced": .paperwork, "disputed": .paperwork,
        "paid": .closed, "complete": .closed, "cancelled": .closed, "expired": .closed,
    ]

    /// Canonical derivation. `on_hold`/`customs_hold` render in the stage they
    /// interrupted (via `previousState`) rather than jumping the strip.
    static func derive(status: String?, previousState: String? = nil) -> LifecycleStage {
        let s = (status ?? "").lowercased()
        if s == "on_hold" || s == "customs_hold" {
            if let prev = previousState?.lowercased(), let stage = truckStatusToStage[prev] { return stage }
            return .inTransit
        }
        return truckStatusToStage[s] ?? .posted
    }
}
