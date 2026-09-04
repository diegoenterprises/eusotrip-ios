//
//  EusoTripMapStyleRegistry.swift
//  EusoTrip
//
//  Deterministic native contract for the 18 EusoTrip HARP exports.
//  Product mode, cartography family, appearance, and guidance are separate
//  dimensions. Ambiguous freight modes never silently become Truck.
//

import Foundation

public enum EusoTripMapFamily: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case operational, navigation, terrain

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .operational: return "Operational"
        case .navigation: return "Navigation"
        case .terrain: return "Terrain"
        }
    }
    public var hereBaseFamilyName: String {
        switch self {
        case .operational: return "Logistics"
        case .navigation: return "Logistics"
        case .terrain: return "Topographic"
        }
    }
    fileprivate var baseSchemeStem: String {
        switch self {
        case .operational: return "logistics"
        case .navigation: return "logistics"
        case .terrain: return "topo"
        }
    }
}

public enum EusoTripMapTheme: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case light, dark

    public var id: String { rawValue }
    public var displayName: String { self == .light ? "Light" : "Dark" }
    fileprivate var hereVariantName: String { self == .light ? "Day" : "Night" }
    fileprivate var schemeSuffix: String { self == .light ? "day" : "night" }
}

/// The only product modes with first-class authored style archives.
public enum EusoTripMapProductMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case truck, rail, vessel

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .truck: return "Truck"
        case .rail: return "Rail"
        case .vessel: return "Vessel"
        }
    }
    public var accessibilityMarkerName: String {
        switch self {
        case .truck: return "road vehicle"
        case .rail: return "rail consist"
        case .vessel: return "vessel"
        }
    }
}

/// Lossless values accepted at data boundaries. Unknown remains unknown.
public enum EusoTripMapTransportMode: String, CaseIterable, Codable, Hashable, Sendable {
    case truck, rail, vessel, barge, intermodal, escort, unknown

    public init(canonicalValue: String?) {
        let normalized = canonicalValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self = normalized.flatMap(Self.init(rawValue:)) ?? .unknown
    }
}

/// Explicit evidence supplied by the active product or active segment.
/// Barge and Escort are not global aliases, and Intermodal needs a segment.
public enum EusoTripMapModeContext: Hashable, Sendable {
    case primary(EusoTripMapProductMode)
    case barge(activeVesselProduct: Bool)
    case escort(activeRoadEscort: Bool)
    case intermodal(activeSegment: EusoTripMapProductMode?)
    case unknown

    /// Adapts a raw value without inventing alias evidence.
    public static func unconfirmed(_ mode: EusoTripMapTransportMode) -> Self {
        switch mode {
        case .truck: return .primary(.truck)
        case .rail: return .primary(.rail)
        case .vessel: return .primary(.vessel)
        case .barge: return .barge(activeVesselProduct: false)
        case .escort: return .escort(activeRoadEscort: false)
        case .intermodal: return .intermodal(activeSegment: nil)
        case .unknown: return .unknown
        }
    }

    public var sourceTransportMode: EusoTripMapTransportMode {
        switch self {
        case .primary(.truck): return .truck
        case .primary(.rail): return .rail
        case .primary(.vessel): return .vessel
        case .barge: return .barge
        case .escort: return .escort
        case .intermodal: return .intermodal
        case .unknown: return .unknown
        }
    }
}

public enum EusoTripMapFamilySelectionSource: String, Codable, Hashable, Sendable {
    case explicitSurface, manualPreference, activeJobRecommendation, surfaceDefault
}

public struct EusoTripMapFamilyResolution: Hashable, Sendable {
    public let family: EusoTripMapFamily
    public let source: EusoTripMapFamilySelectionSource
}

public enum EusoTripMapFamilyPreference {
    public static let storageKey = "com.eusorone.EusoTrip.map.family"

    /// Manual choice wins. Active work recommends Navigation only when no
    /// explicit or persisted family exists; it never forces the family.
    public static func resolve(
        explicitFamily: EusoTripMapFamily?,
        persistedRawValue: String,
        activeJob: Bool,
        surfaceDefault: EusoTripMapFamily
    ) -> EusoTripMapFamilyResolution {
        if let explicitFamily {
            return .init(family: explicitFamily, source: .explicitSurface)
        }
        if let persisted = EusoTripMapFamily(rawValue: persistedRawValue) {
            return .init(family: persisted, source: .manualPreference)
        }
        if activeJob {
            return .init(family: .navigation, source: .activeJobRecommendation)
        }
        return .init(family: surfaceDefault, source: .surfaceDefault)
    }
}

/// Transaction state for a user-requested cartography family change.
///
/// `activeFamily` is the only family the UI may mark selected or persist.
/// A request remains pending until the embedded renderer confirms that
/// `map.setBaseLayer` completed. Stale callbacks are ignored so a fast second
/// choice cannot be overwritten by a slower first archive.
public struct EusoTripMapFamilyTransitionState: Hashable, Sendable {
    public private(set) var activeFamily: EusoTripMapFamily
    public private(set) var pendingFamily: EusoTripMapFamily?
    public private(set) var failedFamily: EusoTripMapFamily?
    public private(set) var failureMessage: String?
    public private(set) var latestRequestID: Int

    public init(activeFamily: EusoTripMapFamily) {
        self.activeFamily = activeFamily
        self.pendingFamily = nil
        self.failedFamily = nil
        self.failureMessage = nil
        self.latestRequestID = 0
    }

    /// Starts (or retries) a family transition and supersedes any older one.
    @discardableResult
    public mutating func request(_ family: EusoTripMapFamily) -> Int {
        latestRequestID &+= 1
        pendingFamily = family
        failedFamily = nil
        failureMessage = nil
        return latestRequestID
    }

    /// Commits only the latest matching request.
    @discardableResult
    public mutating func commit(
        _ family: EusoTripMapFamily,
        requestID: Int
    ) -> Bool {
        guard requestID == latestRequestID, pendingFamily == family else { return false }
        activeFamily = family
        pendingFamily = nil
        failedFamily = nil
        failureMessage = nil
        return true
    }

    /// Fails only the latest matching request while preserving the active map.
    @discardableResult
    public mutating func fail(
        _ family: EusoTripMapFamily,
        requestID: Int,
        message: String
    ) -> Bool {
        guard requestID == latestRequestID, pendingFamily == family else { return false }
        pendingFamily = nil
        failedFamily = family
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        failureMessage = normalized.isEmpty ? "Map family could not be prepared." : normalized
        return true
    }

    /// Adopts a caller or persistence change only when no request is in flight.
    public mutating func synchronizeActive(_ family: EusoTripMapFamily) {
        guard pendingFamily == nil else { return }
        activeFamily = family
        failedFamily = nil
        failureMessage = nil
    }
}

public enum EusoTripMapVisualReviewState: String, Codable, Hashable, Sendable {
    case pending, blocked, approved
}

/// Matching stock Oslo family for pending, unavailable, or failed artifacts.
public struct EusoTripMapFoundationDescriptor: Codable, Hashable, Sendable {
    public let family: EusoTripMapFamily
    public let theme: EusoTripMapTheme

    public init(family: EusoTripMapFamily, theme: EusoTripMapTheme) {
        self.family = family
        self.theme = theme
    }
    public var hereDefaultFallbackName: String {
        "\(family.hereBaseFamilyName) \(theme.hereVariantName)"
    }
    public var hereDefaultStyleIdentity: String {
        "\(family.baseSchemeStem).\(theme.schemeSuffix)"
    }
    public var omvContent: String {
        switch family {
        case .operational: return "default,advanced_roads,advanced_pois,transit"
        case .navigation: return "default,transit"
        case .terrain: return "default,hillshade,contours,transit"
        }
    }
}

/// One exact product-mode/family/theme HARP artifact.
public struct EusoTripMapStyleDescriptor: Codable, Hashable, Identifiable, Sendable {
    public let mode: EusoTripMapProductMode
    public let family: EusoTripMapFamily
    public let theme: EusoTripMapTheme

    public init(mode: EusoTripMapProductMode, family: EusoTripMapFamily, theme: EusoTripMapTheme) {
        self.mode = mode
        self.family = family
        self.theme = theme
    }
    public var id: String { "\(mode.rawValue).\(family.rawValue).\(theme.rawValue)" }
    public var artifactVersion: String { family == .navigation ? "v2" : "v1" }
    public var assetName: String {
        "EusoTrip \(mode.displayName) \(family.displayName) \(theme.displayName) \(artifactVersion)"
    }
    public var artifactPath: String {
        "/map-styles/eusotrip-\(mode.rawValue)-\(family.rawValue)-\(theme.rawValue)-\(artifactVersion)-\(artifactSHA256).tar.gz"
    }
    public var artifactSHA256: String {
        switch (mode, family, theme) {
        case (.truck, .operational, .light): return "0e0daa28c29a30265110ad7d2118282bd8682749f731b7e353a15270b05be4e9"
        case (.truck, .operational, .dark): return "9b52bc8de2fe119e056514a9f0afaf0c0a2ed1d5e2a308e1695b0770856fecea"
        case (.truck, .navigation, .light): return "40ef31554a8cb3ce1fac629d4b702ca7389eb9196fb66aeab1de33d8a56d8ac8"
        case (.truck, .navigation, .dark): return "fd81c9865eed863842edbfe404bc5c2dd117aef266be8b5cd336b03cf040a0d6"
        case (.truck, .terrain, .light): return "5f0750dcb9df68286061eda3717c91cff705393dc287373f6016a9fc0f606570"
        case (.truck, .terrain, .dark): return "3e7614e7143bd4f51a9f2d769a6e8591fcdf2eaaeb839bcce53bc4d4f9d2e0f2"
        case (.rail, .operational, .light): return "4ebe23dd22a07f70e5d8fb0e3e0a732301c964c2983cc9dfdb33703ce2d79c26"
        case (.rail, .operational, .dark): return "d5f03fc7ab472f7ae7946973381a93d17220be61d863a5f7ef4d06915851f867"
        case (.rail, .navigation, .light): return "70c7de9d9ec419beb358b40c7ee8d291a22042347e6cb67bdb0ac19c4e538c1b"
        case (.rail, .navigation, .dark): return "b469e284ac6ab1ea49cda65ca45397af33db35589ee294c3666dd6b880091752"
        case (.rail, .terrain, .light): return "0473802d19e61454e90eaf310669f6eb4522e51548f7a364de8bb0cce4e1582e"
        case (.rail, .terrain, .dark): return "7930864b029abbab9edfe9ac78f21cf72d3388fbfa5072d4913a0ca3377c352e"
        case (.vessel, .operational, .light): return "0e0436786d01f57743a98791f345e7829279fb55c75e0e944aa876d0154a8b38"
        case (.vessel, .operational, .dark): return "70082d699164833621d39346f299ce949cf54d7649cedd01233b112e3d8f1f8c"
        case (.vessel, .navigation, .light): return "5d5f548168f116e4745b69818c5684cb3fe63206a71e634b21c26d35426273ab"
        case (.vessel, .navigation, .dark): return "88aec437a5f9e76caf36a0cec84845aa2ed26083cf1beda94d38a442d1819780"
        case (.vessel, .terrain, .light): return "0d77a28db8884128b6d34835778538d9d7922bd684c63c695421de5e2af36ff5"
        case (.vessel, .terrain, .dark): return "f9725b6ac055a1a27ebb24c072db2aa0b228cd979ac9d7c5ad39173a37721aa9"
        }
    }
    public var styleOverrideCount: Int { 282 }
    public var paletteVersion: String { "eusorone.mode-map.v1" }
    public var runtimeOverlayContractVersion: String { "eusorone.route-overlay.v2" }
    public var visualReviewState: EusoTripMapVisualReviewState { .pending }
    public var visualReviewNote: String {
        "Deterministic HARP foundation only; native runtime screenshots, multi-zoom contrast, and accessibility review remain pending. This artifact is not visual approval."
    }
    public var isProductionEligible: Bool { visualReviewState == .approved }
    public var foundation: EusoTripMapFoundationDescriptor { .init(family: family, theme: theme) }
    public var hereDefaultFallbackName: String { foundation.hereDefaultFallbackName }
    public var hereDefaultStyleIdentity: String { foundation.hereDefaultStyleIdentity }
    public var omvContent: String { foundation.omvContent }
}

public enum EusoTripMapStyleUnavailableReason: String, Codable, Hashable, Sendable {
    case unknownTransportMode
    case bargeRequiresActiveVesselProduct
    case escortRequiresActiveRoadProduct
    case intermodalRequiresActiveSegment
    case unknownArtifactName
}

public enum EusoTripMapStyleResolution: Hashable, Sendable {
    case resolved(EusoTripMapStyleDescriptor)
    case unavailable(
        reason: EusoTripMapStyleUnavailableReason,
        message: String,
        foundation: EusoTripMapFoundationDescriptor
    )

    public var descriptor: EusoTripMapStyleDescriptor? {
        guard case .resolved(let descriptor) = self else { return nil }
        return descriptor
    }
    public var foundation: EusoTripMapFoundationDescriptor {
        switch self {
        case .resolved(let descriptor): return descriptor.foundation
        case .unavailable(_, _, let foundation): return foundation
        }
    }
    public var unavailableReason: EusoTripMapStyleUnavailableReason? {
        guard case .unavailable(let reason, _, _) = self else { return nil }
        return reason
    }
    public var unavailableMessage: String? {
        guard case .unavailable(_, let message, _) = self else { return nil }
        return message
    }
}

/// Owned route/chrome tokens. Stops are ordered by route progress, never by
/// geographic bounds: origin blue, midpoint violet, destination purple.
public enum EusoTripMapIdentityContract {
    public static let routeOriginHex = "#1473FF"
    public static let routeMidpointHex = "#813FF5"
    public static let routeDestinationHex = "#BE01FF"
    public static let routeGradientStops = [routeOriginHex, routeMidpointHex, routeDestinationHex]
    public static let chromeGradientCSS =
        "linear-gradient(90deg, #1473FF 0%, #813FF5 52%, #BE01FF 100%)"
    public static let visualReviewState: EusoTripMapVisualReviewState = .pending
}

public enum EusoTripMapStyleRegistry {
    public static let allStyles: [EusoTripMapStyleDescriptor] =
        EusoTripMapProductMode.allCases.flatMap { mode in
            EusoTripMapFamily.allCases.flatMap { family in
                EusoTripMapTheme.allCases.map { theme in
                    .init(mode: mode, family: family, theme: theme)
                }
            }
        }

    public static func style(
        mode: EusoTripMapProductMode,
        family: EusoTripMapFamily,
        theme: EusoTripMapTheme
    ) -> EusoTripMapStyleDescriptor {
        .init(mode: mode, family: family, theme: theme)
    }

    public static func resolve(
        context: EusoTripMapModeContext,
        family: EusoTripMapFamily,
        theme: EusoTripMapTheme
    ) -> EusoTripMapStyleResolution {
        let foundation = EusoTripMapFoundationDescriptor(family: family, theme: theme)
        switch context {
        case .primary(let mode):
            return .resolved(style(mode: mode, family: family, theme: theme))
        case .barge(activeVesselProduct: true):
            return .resolved(style(mode: .vessel, family: family, theme: theme))
        case .barge(activeVesselProduct: false):
            return .unavailable(
                reason: .bargeRequiresActiveVesselProduct,
                message: "Select the active Vessel product before using a Barge map.",
                foundation: foundation
            )
        case .escort(activeRoadEscort: true):
            return .resolved(style(mode: .truck, family: family, theme: theme))
        case .escort(activeRoadEscort: false):
            return .unavailable(
                reason: .escortRequiresActiveRoadProduct,
                message: "Confirm the active road-escort product before using a Truck map.",
                foundation: foundation
            )
        case .intermodal(activeSegment: .some(let mode)):
            return .resolved(style(mode: mode, family: family, theme: theme))
        case .intermodal(activeSegment: nil):
            return .unavailable(
                reason: .intermodalRequiresActiveSegment,
                message: "Select the active Truck, Rail, or Vessel segment.",
                foundation: foundation
            )
        case .unknown:
            return .unavailable(
                reason: .unknownTransportMode,
                message: "Map mode unavailable. Select an active Truck, Rail, or Vessel segment.",
                foundation: foundation
            )
        }
    }

    /// Persisted names fail closed instead of choosing Operational Truck.
    public static func resolveAsset(
        named assetName: String?,
        preferredTheme: EusoTripMapTheme
    ) -> EusoTripMapStyleResolution {
        let normalized = assetName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized,
           let descriptor = allStyles.first(where: {
               $0.assetName.caseInsensitiveCompare(normalized) == .orderedSame
           }) {
            return .resolved(descriptor)
        }
        return .unavailable(
            reason: .unknownArtifactName,
            message: "Saved map style is unavailable. Select a product mode and map family.",
            foundation: .init(family: .operational, theme: preferredTheme)
        )
    }
}

public enum EusoTripMapGuidancePhase: String, Codable, Hashable, Sendable {
    case inactive, previewing, guiding, rerouting, arrived, unavailable

    public var isRouteGuidanceActive: Bool {
        switch self {
        case .previewing, .guiding, .rerouting: return true
        case .inactive, .arrived, .unavailable: return false
        }
    }
}

/// Persistable state. Family changes never mutate route guidance.
public struct EusoTripMapSelectionState: Codable, Hashable, Sendable {
    public private(set) var selectedFamily: EusoTripMapFamily
    public private(set) var theme: EusoTripMapTheme
    public private(set) var activeJobID: String?
    public private(set) var activeTransportMode: EusoTripMapTransportMode?
    public private(set) var activeProductSegment: EusoTripMapProductMode?
    public private(set) var guidancePhase: EusoTripMapGuidancePhase
    public private(set) var hasManualFamilyChoiceDuringActiveJob: Bool

    public init(
        selectedFamily: EusoTripMapFamily = .operational,
        theme: EusoTripMapTheme = .light,
        activeJobID: String? = nil,
        activeTransportMode: EusoTripMapTransportMode? = nil,
        activeProductSegment: EusoTripMapProductMode? = nil,
        guidancePhase: EusoTripMapGuidancePhase = .inactive,
        hasManualFamilyChoiceDuringActiveJob: Bool = false
    ) {
        let normalizedJobID = activeJobID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = normalizedJobID?.isEmpty == false
        self.selectedFamily = selectedFamily
        self.theme = theme
        self.activeJobID = valid ? normalizedJobID : nil
        self.activeTransportMode = valid ? activeTransportMode : nil
        self.activeProductSegment = valid ? activeProductSegment : nil
        self.guidancePhase = valid ? guidancePhase : .inactive
        self.hasManualFamilyChoiceDuringActiveJob = valid && hasManualFamilyChoiceDuringActiveJob
    }

    private enum CodingKeys: String, CodingKey {
        case selectedFamily, theme, activeJobID, activeTransportMode
        case activeProductSegment, guidancePhase, hasManualFamilyChoiceDuringActiveJob
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            selectedFamily: try values.decodeIfPresent(EusoTripMapFamily.self, forKey: .selectedFamily) ?? .operational,
            theme: try values.decodeIfPresent(EusoTripMapTheme.self, forKey: .theme) ?? .light,
            activeJobID: try values.decodeIfPresent(String.self, forKey: .activeJobID),
            activeTransportMode: try values.decodeIfPresent(EusoTripMapTransportMode.self, forKey: .activeTransportMode),
            activeProductSegment: try values.decodeIfPresent(EusoTripMapProductMode.self, forKey: .activeProductSegment),
            guidancePhase: try values.decodeIfPresent(EusoTripMapGuidancePhase.self, forKey: .guidancePhase) ?? .inactive,
            hasManualFamilyChoiceDuringActiveJob: try values.decodeIfPresent(Bool.self, forKey: .hasManualFamilyChoiceDuringActiveJob) ?? false
        )
    }

    public var hasActiveJob: Bool { activeJobID != nil }
    public var recommendedFamily: EusoTripMapFamily { hasActiveJob ? .navigation : .operational }
    public var mapModeContext: EusoTripMapModeContext {
        guard hasActiveJob, let activeTransportMode else { return .unknown }
        switch activeTransportMode {
        case .truck: return .primary(.truck)
        case .rail: return .primary(.rail)
        case .vessel: return .primary(.vessel)
        case .barge: return .barge(activeVesselProduct: activeProductSegment == .vessel)
        case .escort: return .escort(activeRoadEscort: activeProductSegment == .truck)
        case .intermodal: return .intermodal(activeSegment: activeProductSegment)
        case .unknown: return .unknown
        }
    }
    public var currentStyleResolution: EusoTripMapStyleResolution {
        EusoTripMapStyleRegistry.resolve(context: mapModeContext, family: selectedFamily, theme: theme)
    }
    public var currentStyle: EusoTripMapStyleDescriptor? { currentStyleResolution.descriptor }

    public mutating func beginActiveJob(
        id: String,
        transportMode: EusoTripMapTransportMode,
        activeProductSegment: EusoTripMapProductMode? = nil,
        guidancePhase: EusoTripMapGuidancePhase
    ) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        activeJobID = normalizedID.isEmpty ? nil : normalizedID
        activeTransportMode = activeJobID == nil ? nil : transportMode
        self.activeProductSegment = activeJobID == nil ? nil : activeProductSegment
        self.guidancePhase = activeJobID == nil ? .inactive : guidancePhase
        hasManualFamilyChoiceDuringActiveJob = false
    }
    public mutating func selectFamily(_ family: EusoTripMapFamily) {
        selectedFamily = family
        if hasActiveJob { hasManualFamilyChoiceDuringActiveJob = true }
    }
    public mutating func updateTheme(_ theme: EusoTripMapTheme) { self.theme = theme }
    public mutating func updateGuidance(_ phase: EusoTripMapGuidancePhase) {
        guidancePhase = hasActiveJob ? phase : .inactive
    }
    public mutating func updateActiveProductSegment(_ segment: EusoTripMapProductMode?) {
        activeProductSegment = hasActiveJob ? segment : nil
    }
    public mutating func endActiveJob() {
        activeJobID = nil
        activeTransportMode = nil
        activeProductSegment = nil
        guidancePhase = .inactive
        hasManualFamilyChoiceDuringActiveJob = false
    }
}
