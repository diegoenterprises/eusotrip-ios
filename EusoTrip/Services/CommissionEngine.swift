//
//  CommissionEngine.swift
//  T-025 (2026-05-20) — Canonical iOS-side commission engine.
//
//  Audit finding (01_AUDIT_FINDINGS_SYNTHESIS.md §7):
//    "Fee engine: BASE only present (5/8/10/12% by load type);
//     missing COUNTRY × VERTICAL × PRODUCT × DISTANCE × CYCLE × HAZMAT
//     (parametric)."
//
//  The audit listed `CommissionEngine.swift` in the file inventory but
//  the file didn't exist on iOS (the audit was reading the cross-repo
//  inventory and assumed parity with the platform repo). This file
//  satisfies the ticket spec on the iOS side: a single source of truth
//  for commission math that DELEGATES to `FeeMultiplierEngine` for the
//  full 7-multiplier parametric breakdown, while exposing the legacy
//  4-flat-rate signature (`rate(forType:)`) as a back-compat shim so
//  any iOS caller that hasn't migrated yet keeps working.
//
//  After T-025, every commission call site has ONE place to read from
//  — drift between broker rate sheet (402), shipper rate sheet (252),
//  loading screen (030), and any future settlement preview is
//  impossible at the type-system level.
//

import Foundation

public enum CommissionEngine {

    /// Legacy load-type → flat-rate map. Preserved verbatim from the
    /// audit's description so existing call sites (none on iOS today,
    /// but the surface is documented for parity) continue to compile.
    /// New code should call `compute(_:)` instead.
    public enum LegacyLoadType: String, CaseIterable, Codable, Hashable {
        case standard           // 5% — generic dry van / LTL
        case refrigeratedReefer // 8% — FSMA + temperature compliance
        case hazmat             // 10% — placards + ERG + segregation
        case oversize           // 12% — OS/OW + escort + permit ops
    }

    /// Legacy 4-flat-rate signature. Returns the BASE multiplier only
    /// — without country / vertical / distance / cycle adjustments.
    /// Internal call sites should migrate to `compute(_:)` for the
    /// full parametric breakdown.
    public static func legacyRate(forType type: LegacyLoadType) -> Decimal {
        switch type {
        case .standard:           return 0.05
        case .refrigeratedReefer: return 0.08
        case .hazmat:             return 0.10
        case .oversize:           return 0.12
        }
    }

    /// Canonical commission path — delegates to `FeeMultiplierEngine`
    /// for the full 7-multiplier breakdown. Every iOS surface that
    /// needs commission math (broker tender 402, shipper Step 3 pricing
    /// 252, settlement preview when it ships) reads through here so
    /// the value is identical across screens.
    @inlinable
    public static func compute(_ input: FeeComputationInput) -> FeeBreakdown {
        FeeMultiplierEngine.compute(input)
    }

    /// Convenience for callers that need only the effective multiplier
    /// (not the full breakdown). Same value as `compute(input).effective`
    /// — wrapper exists so new call sites don't need to handle the full
    /// FeeBreakdown struct when they just want a number.
    public static func effectiveMultiplier(_ input: FeeComputationInput) -> Decimal {
        compute(input).effective
    }

    /// Apply the canonical effective multiplier to a fiat amount.
    /// Returns the platform fee in USD for a given load rate, with the
    /// canonical (vertical × trailer × country × distance × cycle ×
    /// hazmat) loading. The broker / settlement preview consumes this
    /// when it needs a dollar value to show next to the rate.
    public static func feeAmount(rateUSD: Double, input: FeeComputationInput) -> Double {
        let effective = NSDecimalNumber(decimal: compute(input).effective).doubleValue
        return rateUSD * (effective - 1)
    }
}
