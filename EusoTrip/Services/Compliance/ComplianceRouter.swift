//
//  ComplianceRouter.swift
//  T-027 (2026-05-20) — Per-vertical compliance router protocol.
//
//  Audit finding (01_AUDIT_FINDINGS_SYNTHESIS.md §7):
//    "Per-vertical compliance: 1 of 12 (hazmat only) — 11 missing"
//
//  This file declares the shared protocol that every per-vertical
//  router conforms to. Each router subscribes to FSM transitions
//  (LoadStateTransition values) and emits a list of CompliancePrompt
//  rows the driver / dispatch UI surfaces. Concrete routers:
//    - HazmatComplianceRouter      (ERG, placards, segregation)
//    - ReeferComplianceRouter      (FSMA, FDA, temp logs)
//    - LivestockComplianceRouter   (USDA, 28-hr law)
//    - HeavyHaulComplianceRouter   (OS/OW, escorts, route survey)
//    - CrossBorderComplianceRouter (ACE / CARM / SAT)
//
//  Routing dispatch: `ComplianceRouterRegistry.routers(for: vertical,
//  isCrossBorder:)` returns the ordered list of routers that apply.
//

import Foundation

/// One compliance row surfaced to the driver / dispatcher. Routers
/// emit zero or more of these per transition; the UI groups by
/// severity and renders them as banners / sheets.
public struct CompliancePrompt: Codable, Hashable, Identifiable {
    public let id: String
    public let routerKey: String          // "hazmat" / "reefer" / etc.
    public let severity: Severity         // info / warning / blocker
    public let title: String              // "Affix placards before EN_ROUTE_TO_DELIVERY"
    public let body: String               // human-readable explanation
    public let regulatoryRef: String?     // "49 CFR 172.504"
    public let documentTypes: [DocumentType]  // attached doc requirements

    public enum Severity: String, Codable, Hashable {
        case info       // FYI, no gate
        case warning    // FSM can advance but row stays flagged
        case blocker    // FSM advance is blocked until cleared
    }

    public init(
        id: String,
        routerKey: String,
        severity: Severity,
        title: String,
        body: String,
        regulatoryRef: String? = nil,
        documentTypes: [DocumentType] = []
    ) {
        self.id = id
        self.routerKey = routerKey
        self.severity = severity
        self.title = title
        self.body = body
        self.regulatoryRef = regulatoryRef
        self.documentTypes = documentTypes
    }
}

/// Every per-vertical router conforms to this protocol. Pure-function
/// style: pass the transition + the vehicle's overlay snapshot, get
/// back the set of prompts. No mutable state in routers so they're
/// trivially testable and run identically on driver / dispatch /
/// settlement surfaces.
public protocol ComplianceRouter {
    /// Canonical key (matches `CompliancePrompt.routerKey`).
    static var key: String { get }

    /// True when this router applies to a (vertical, mode,
    /// isCrossBorder) tuple. Used by the registry to filter.
    static func applies(vertical: Vertical, mode: TransportMode, isCrossBorder: Bool) -> Bool

    /// Emit prompts for the given transition + current overlay state.
    /// Returns an empty array when no prompts apply at this transition.
    static func prompts(
        for transition: LoadStateTransition,
        overlays: CompositeLoadState?
    ) -> [CompliancePrompt]
}

/// Registry — dispatch table that returns the ordered list of routers
/// for any (vertical, mode, isCrossBorder) tuple. Drivers / dispatch
/// query the registry once per load and re-evaluate per transition.
public enum ComplianceRouterRegistry {

    /// All registered routers in canonical priority order. Hazmat fires
    /// first (highest regulatory consequence), cross-border last
    /// (borders are typically reached only after the load is moving).
    public static let allRouters: [ComplianceRouter.Type] = [
        HazmatComplianceRouter.self,
        ReeferComplianceRouter.self,
        LivestockComplianceRouter.self,
        HeavyHaulComplianceRouter.self,
        CrossBorderComplianceRouter.self,
    ]

    /// Routers that apply for a specific shipment context.
    public static func routers(
        vertical: Vertical,
        mode: TransportMode,
        isCrossBorder: Bool
    ) -> [ComplianceRouter.Type] {
        allRouters.filter { $0.applies(vertical: vertical, mode: mode, isCrossBorder: isCrossBorder) }
    }

    /// Convenience — evaluate every applicable router against a single
    /// transition and return the merged prompt list.
    public static func evaluate(
        vertical: Vertical,
        mode: TransportMode,
        isCrossBorder: Bool,
        transition: LoadStateTransition,
        overlays: CompositeLoadState?
    ) -> [CompliancePrompt] {
        routers(vertical: vertical, mode: mode, isCrossBorder: isCrossBorder)
            .flatMap { $0.prompts(for: transition, overlays: overlays) }
    }
}
