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

    /// RAIL map — all 21 rail_shipments.status values (L02-21). Transit-side
    /// exceptions pin conservatively to IN_TRANSIT.
    static let railStatusToStage: [String: LifecycleStage] = [
        "requested": .posted,
        "car_ordered": .awarded,
        "car_placed": .pickup, "loading": .pickup, "loaded": .pickup, "in_consist": .pickup,
        "departed": .inTransit, "in_transit": .inTransit, "at_interchange": .inTransit,
        "in_yard": .inTransit, "interchange_delay": .inTransit, "derailment_hold": .inTransit,
        "hazmat_exception": .inTransit, "on_hold": .inTransit,
        "spotted": .delivery, "unloading": .delivery, "unloaded": .delivery,
        "empty_returned": .paperwork, "invoiced": .paperwork,
        "settled": .closed, "cancelled": .closed,
    ]

    /// VESSEL map — all 19 vessel_shipments.status values (L03-14). `customs_hold`
    /// pins to DELIVERY (destination hold) via this explicit entry, which wins
    /// over the generic hold heuristic; `rolled` re-opens BIDDING.
    static let vesselStatusToStage: [String: LifecycleStage] = [
        "booking_requested": .posted,
        "booking_confirmed": .awarded, "documentation": .awarded,
        "container_released": .pickup, "gate_in": .pickup, "loaded_on_vessel": .pickup,
        "departed": .inTransit, "in_transit": .inTransit, "transshipment": .inTransit,
        "arrived": .delivery, "customs_hold": .delivery, "customs_cleared": .delivery,
        "discharged": .delivery, "gate_out": .delivery, "delivered": .delivery,
        "invoiced": .paperwork,
        "settled": .closed, "cancelled": .closed,
        "rolled": .bidding,
    ]

    /// Transport mode for stage derivation. Mirrors the server `TransportModeKey`.
    enum Mode: String { case truck = "TRUCK", rail = "RAIL", vessel = "VESSEL" }

    private static func map(for mode: Mode) -> [String: LifecycleStage] {
        switch mode {
        case .truck:  return truckStatusToStage
        case .rail:   return railStatusToStage
        case .vessel: return vesselStatusToStage
        }
    }

    /// Mode-aware canonical derivation. The explicit per-mode mapping wins first
    /// (e.g. VESSEL `customs_hold` → DELIVERY); only an UNMAPPED `on_hold`/
    /// `customs_hold` falls back to the interrupted stage (via `previousState`)
    /// or IN_TRANSIT. Mirrors `deriveLifecycleStage` in server/shared/lifecycle.ts.
    static func derive(status: String?, mode: Mode, previousState: String? = nil) -> LifecycleStage {
        let table = map(for: mode)
        let s = (status ?? "").lowercased()
        if let stage = table[s] { return stage }
        if s == "on_hold" || s == "customs_hold" {
            if let prev = previousState?.lowercased(), let stage = table[prev] { return stage }
            return .inTransit
        }
        return .posted
    }

    /// Back-compat TRUCK overload for existing call sites.
    static func derive(status: String?, previousState: String? = nil) -> LifecycleStage {
        derive(status: status, mode: .truck, previousState: previousState)
    }
}
