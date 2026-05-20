//
//  ESangIntent.swift
//  Canonical intent enum for the ESang AI voice/text dispatcher.
//
//  2026-05-20 · IO 2026 P0-2 (thinking_level) — mirrors the server-side
//  `EsangIntent` type in `frontend/server/_core/geminiConfig.ts`. Every
//  iOS surface that talks to ESang routes through this enum so:
//
//    1. The intent classification is locked at the type system level
//       (typo = compile error, no drift between client and server).
//    2. The reasoning depth (`thinkingLevel`) is co-located with the
//       intent — high-stakes regulatory queries (hazmat, USMCA, ERG)
//       get deep thinking; status reads + simple confirmations stay
//       low to save latency + cost.
//    3. Verticals that escalate the cost of a wrong reply (hazmat,
//       tanker, heavy-haul) bump otherwise-medium intents up to high.
//
//  Drop into: EusoTrip/Models/ESangIntent.swift
//

import Foundation

/// The 19 canonical ESang intents. RawValue is the wire string the
/// server's `EsangIntent` type accepts; do not rename without
/// updating `_core/geminiConfig.ts` in lockstep.
public enum ESangIntent: String, CaseIterable, Codable, Hashable, Sendable {
    // ─── Status reads — low thinking ──────────────────────────────
    case statusLocation         = "status.location"
    case statusEta              = "status.eta"
    case statusHosRemaining     = "status.hos_remaining"
    case statusNextStop         = "status.next_stop"

    // ─── Simple actions — low ─────────────────────────────────────
    case actionConfirmPickup    = "action.confirm_pickup"
    case actionConfirmDelivery  = "action.confirm_delivery"

    // ─── Moderate planning — medium ──────────────────────────────
    case planFuelStop           = "plan.fuel_stop"
    case planRoutePreview       = "plan.route_preview"
    case planDetentionLog       = "plan.detention_log"

    // ─── Multi-step / compliance — high ──────────────────────────
    case complianceHazmatSegregation = "compliance.hazmat_segregation"
    case complianceUsmcaCert         = "compliance.usmca_cert"
    case complianceErgLookup         = "compliance.erg_lookup"
    case complianceReeferTempBreach  = "compliance.reefer_temp_breach"
    case complianceLivestock28Hr     = "compliance.livestock_28hr"
    case planReroute                 = "plan.reroute"
    case planCustomsFiling           = "plan.customs_filing"
    case planHosOverride             = "plan.hos_override"

    case unknown = "unknown"

    /// Reasoning depth requested of the Gemini model for this intent.
    /// Mirrors `thinkingLevelFor` in `_core/geminiConfig.ts`.
    public var thinkingLevel: ThinkingLevel {
        switch self {
        // Compliance + multi-step planning — always deep.
        case .complianceHazmatSegregation,
             .complianceUsmcaCert,
             .complianceErgLookup,
             .complianceReeferTempBreach,
             .complianceLivestock28Hr,
             .planReroute,
             .planCustomsFiling,
             .planHosOverride:
            return .high

        // Moderate planning — medium.
        case .planFuelStop,
             .planRoutePreview,
             .planDetentionLog:
            return .medium

        // Status reads + confirm-actions — low.
        case .statusLocation,
             .statusEta,
             .statusHosRemaining,
             .statusNextStop,
             .actionConfirmPickup,
             .actionConfirmDelivery:
            return .low

        // Unknown — medium so we don't over- or under-spend.
        case .unknown:
            return .medium
        }
    }

    /// Vertical-aware escalation. Hazmat / tanker / heavy-haul lanes
    /// bump `.medium` intents up to `.high` because the regulatory
    /// cost of a wrong reply scales with the compliance overlay.
    public func thinkingLevel(forVertical vertical: Vertical?) -> ThinkingLevel {
        let base = thinkingLevel
        guard let v = vertical else { return base }
        if base == .medium && (v == .hazmat ||
                               v == .tankerLiquidBulk ||
                               v == .heavyHaulSpecialized) {
            return .high
        }
        return base
    }

    /// True when this intent triggers an FSM transition on the server
    /// side. Used by `ESangVoiceClient` to know it must wait for a
    /// thought-signature confirmation handshake (T-014 chain) before
    /// firing the underlying mutation. Maps to LoadStateFSM (per the
    /// canonical wizard inventory).
    public var triggersFsmTransition: Bool {
        switch self {
        case .actionConfirmPickup,
             .actionConfirmDelivery,
             .planReroute,
             .planCustomsFiling,
             .planHosOverride:
            return true
        default:
            return false
        }
    }

    /// Best-effort intent classification from a raw user utterance.
    /// This is the offline fallback; the real classifier lives in
    /// the server's Gemini call. Keep this list narrow so it doesn't
    /// over-claim when the real classifier would have said `.unknown`.
    public static func bestGuess(from utterance: String) -> ESangIntent {
        let t = utterance.lowercased()
        if t.contains("where") || t.contains("location") { return .statusLocation }
        if t.contains("eta") || t.contains("arrive")     { return .statusEta }
        if t.contains("hours") || t.contains("hos")      { return .statusHosRemaining }
        if t.contains("next stop") || t.contains("stop next") { return .statusNextStop }
        if t.contains("fuel") || t.contains("gas station")    { return .planFuelStop }
        if t.contains("reroute") || t.contains("re-route") || t.contains("change route") { return .planReroute }
        if t.contains("erg") || t.contains("emergency response") { return .complianceErgLookup }
        if t.contains("usmca") || t.contains("nafta")    { return .complianceUsmcaCert }
        if t.contains("segregat")                        { return .complianceHazmatSegregation }
        if t.contains("temp") && t.contains("breach")    { return .complianceReeferTempBreach }
        if t.contains("28") && t.contains("hour")        { return .complianceLivestock28Hr }
        if t.contains("customs") || t.contains("cbp")    { return .planCustomsFiling }
        if t.contains("override") && t.contains("hos")   { return .planHosOverride }
        if t.contains("confirm") && t.contains("pickup") { return .actionConfirmPickup }
        if t.contains("confirm") && t.contains("deliver"){ return .actionConfirmDelivery }
        return .unknown
    }
}

/// Reasoning depth — passed to Gemini 3+ as `thinking_config.budget`
/// on the server side. Mirrors the server's `ThinkingLevel` type.
public enum ThinkingLevel: String, Codable, Hashable, Sendable {
    case low, medium, high

    /// Token budget the server-side `thinkingConfigBlock` will pass
    /// through to the Gemini API. Surfaced here so iOS UI can show a
    /// "Thinking…" hint with rough wait expectation.
    public var approximateLatencyMs: Int {
        switch self {
        case .low:    return 180   // gemini-3.5-flash target
        case .medium: return 480
        case .high:   return 1100
        }
    }
}
