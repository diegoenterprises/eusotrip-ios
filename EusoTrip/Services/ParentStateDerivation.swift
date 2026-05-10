//
//  ParentStateDerivation.swift
//  EusoTrip — Pure function that derives the parent Shipment state
//  from the child Vehicle states.
//
//  Mirrors the server-side derivation in
//  ~/Desktop/todays work/03_wiring_stubs/server/parentStateDerivation.ts
//  so iOS-side calculations (e.g. on the Convoy strip when a single
//  vehicle's WebSocket event arrives) match the server snapshot
//  byte-for-byte.
//
//  Order of precedence (highest → lowest):
//    1. Blocking exception (HAZMAT_INCIDENT, CONTAMINATION_REJECT,
//       SEAL_BREACH, WEIGHT_VIOLATION, REEFER_BREAKDOWN,
//       IDENTITY_RE_VERIFICATION_REQUIRED, CUSTOMS_HOLD) →
//       EXCEPTION_BLOCKING
//    2. Any non-blocking *_EXCEPTION → EXCEPTION_ANY
//    3. All cancelled → CANCELLED
//    4. All POD signed → POD_FULL
//    5. Any POD signed (some still in transit) → POD_PARTIAL
//    6. All delivered → DELIVERED
//    7. Some delivered → PARTIALLY_DELIVERED
//    8. All in transit → IN_TRANSIT_FULL
//    9. Any at handoff → AT_HANDOFF
//   10. Any past BOOKED → IN_PROGRESS
//   11. All booked → BOOKED_FULL; any → BOOKED_PARTIAL
//   12. All tendered → TENDERED_FULL; any → TENDERED_PARTIAL
//   13. All POSTED / DRAFT → POSTED / DRAFT
//
//  Powered by ESANG AI™.
//

import Foundation

/// Pure derivation — given the children, return what the parent
/// state should be. Runs on every child state change; the result is
/// persisted on the Shipment record so any single-record read gets
/// the authoritative parent state without re-deriving.
public func deriveParentState(vehicles: [Vehicle]) -> ParentShipmentState {
    guard !vehicles.isEmpty else { return .draft }

    let states = vehicles.map(\.childState)

    // 1. Blocking exception bubbles up — settlement freezes here.
    if states.contains(where: { ChildLifecycleSet.blocking.contains($0) }) {
        return .exceptionBlocking
    }

    // 2. Non-blocking exceptions — surface to operator dashboards
    //    but don't freeze settlement.
    if states.contains(where: { $0.hasSuffix("_EXCEPTION") }) {
        return .exceptionAny
    }

    // 3. All cancelled.
    if states.allSatisfy({ ChildLifecycleSet.cancelled.contains($0) }) {
        return .cancelled
    }

    // 4. All POD signed.
    let podSet = ChildLifecycleSet.podSigned
    if states.allSatisfy({ podSet.contains($0) || ChildLifecycleSet.delivered.contains($0) }) {
        // Distinguish DELIVERED (truck dropped, no POD yet) from POD_FULL
        if states.allSatisfy({ podSet.contains($0) }) {
            return .podFull
        }
        return .delivered
    }

    // 5. Any POD signed.
    if states.contains(where: { podSet.contains($0) }) {
        return .podPartial
    }

    // 6. Some children delivered.
    if states.contains(where: { ChildLifecycleSet.delivered.contains($0) }) {
        return .partiallyDelivered
    }

    // 7. All in transit.
    if states.allSatisfy({ ChildLifecycleSet.inTransit.contains($0) }) {
        return .inTransitFull
    }

    // 8. Any at handoff.
    if states.contains(where: { ChildLifecycleSet.inHandoff.contains($0) }) {
        return .atHandoff
    }

    // 9. Any past BOOKED — convoy is moving even if not all in transit.
    if states.contains(where: { ChildLifecycleSet.inTransit.contains($0) }) {
        return .inProgress
    }

    // 10. Booked progression.
    let bookedSet = ChildLifecycleSet.booked
    if states.allSatisfy({ bookedSet.contains($0) }) { return .bookedFull }
    if states.contains(where: { bookedSet.contains($0) }) { return .bookedPartial }

    // 11. Tender progression.
    let tenderedSet: Set<String> = ["TENDERED", "TENDER_ACCEPTED", "AWARDED"]
    if states.allSatisfy({ tenderedSet.contains($0) }) { return .tenderedFull }
    if states.contains(where: { tenderedSet.contains($0) }) { return .tenderedPartial }

    // 12. Posted.
    if states.allSatisfy({ $0 == "POSTED" || $0 == "BIDDING" }) {
        return .posted
    }

    // 13. Default: still drafting.
    return .draft
}
