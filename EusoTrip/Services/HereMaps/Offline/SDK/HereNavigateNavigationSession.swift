//
//  HereNavigateNavigationSession.swift
//  EusoTrip
//
//  Headless HERE Navigate guidance fed only by caller-provided device location
//  samples. Native routes are retained in-process by the offline route engine;
//  DTO geometry is never promoted back into an unverifiable native route.
//

import Foundation

struct HereNavigationLocationAcceptancePolicy: Equatable, Sendable {
    let allowsSimulatedLocations: Bool
    let maximumSampleAge: TimeInterval
    let maximumFutureClockSkew: TimeInterval

    static let production = Self(
        allowsSimulatedLocations: false,
        maximumSampleAge: 30,
        maximumFutureClockSkew: 5
    )

    #if DEBUG
    /// Explicit opt-in for deterministic tests; production composition never
    /// selects this policy.
    static let simulatorTesting = Self(
        allowsSimulatedLocations: true,
        maximumSampleAge: 300,
        maximumFutureClockSkew: 300
    )
    #endif

    private init(
        allowsSimulatedLocations: Bool,
        maximumSampleAge: TimeInterval,
        maximumFutureClockSkew: TimeInterval
    ) {
        self.allowsSimulatedLocations = allowsSimulatedLocations
        self.maximumSampleAge = maximumSampleAge
        self.maximumFutureClockSkew = maximumFutureClockSkew
    }
}

/// Session-owned ordering boundary for every timestamp that can influence
/// guidance or rerouting. The wall clock establishes bounded freshness, while
/// strict ordering rejects replayed device fixes and out-of-order callbacks.
/// A native callback must match a recent accepted fix and advance the consumed
/// deviation timestamp; it cannot invent an observation or replay an old one.
struct HereNavigationTimestampBoundary: Sendable {
    /// Ten-Hz GNSS feeds retain more than the full 30-second production
    /// freshness window while placing a hard ceiling on adversarial input.
    static let maximumRetainedDeviceLocations = 512

    private let locationPolicy: HereNavigationLocationAcceptancePolicy
    private var lastAcceptedDeviceLocationAt: Date?
    private var lastAcceptedDeviationAt: Date?
    private var recentAcceptedDeviceLocationTimestamps: [Date] = []

    init(locationPolicy: HereNavigationLocationAcceptancePolicy = .production) {
        self.locationPolicy = locationPolicy
    }

    mutating func reset() {
        lastAcceptedDeviceLocationAt = nil
        lastAcceptedDeviationAt = nil
        recentAcceptedDeviceLocationTimestamps.removeAll(keepingCapacity: true)
    }

    mutating func acceptDeviceLocation(
        timestamp: Date,
        now: Date = Date()
    ) throws {
        try validatePolicy()
        try validateFreshness(
            timestamp: timestamp,
            now: now,
            invalidMessage: "The location timestamp is invalid for freight guidance.",
            staleMessage: "The location sample is too old for freight guidance.",
            futureMessage: "The location timestamp is implausibly far in the future."
        )
        if let lastAcceptedDeviceLocationAt,
           timestamp <= lastAcceptedDeviceLocationAt {
            throw Self.locationFailure(
                message: "The location sample is duplicated or out of order.",
                recovery: "Wait for a newer GNSS fix and retry."
            )
        }
        lastAcceptedDeviceLocationAt = timestamp
        pruneAcceptedDeviceLocations(now: now)
        recentAcceptedDeviceLocationTimestamps.append(timestamp)
        if recentAcceptedDeviceLocationTimestamps.count > Self.maximumRetainedDeviceLocations {
            recentAcceptedDeviceLocationTimestamps.removeFirst(
                recentAcceptedDeviceLocationTimestamps.count - Self.maximumRetainedDeviceLocations
            )
        }
    }

    mutating func acceptDeviation(
        timestamp: Date?,
        now: Date = Date()
    ) throws -> Date {
        try validatePolicy()
        guard let timestamp else {
            throw Self.locationFailure(
                message: "Route deviation evidence has no device timestamp.",
                recovery: "Wait for a fresh timestamped GNSS fix before rerouting."
            )
        }
        try validateFreshness(
            timestamp: timestamp,
            now: now,
            invalidMessage: "The route deviation timestamp is invalid for freight guidance.",
            staleMessage: "The route deviation evidence is too old for freight guidance.",
            futureMessage: "The route deviation timestamp is implausibly far in the future."
        )
        guard lastAcceptedDeviceLocationAt != nil else {
            throw Self.locationFailure(
                message: "Route deviation evidence arrived before an accepted device location.",
                recovery: "Wait for a fresh GNSS fix before evaluating route deviation."
            )
        }
        pruneAcceptedDeviceLocations(now: now)
        guard recentAcceptedDeviceLocationTimestamps.contains(timestamp) else {
            throw Self.locationFailure(
                message: "Route deviation evidence is not tied to a recent accepted device location.",
                recovery: "Wait for the next timestamped GNSS fix before rerouting."
            )
        }
        if let lastAcceptedDeviationAt,
           timestamp <= lastAcceptedDeviationAt {
            throw Self.locationFailure(
                message: "Route deviation evidence is duplicated or out of order.",
                recovery: "Wait for newer deviation evidence before rerouting."
            )
        }
        lastAcceptedDeviationAt = timestamp
        return timestamp
    }

    private mutating func pruneAcceptedDeviceLocations(now: Date) {
        let maximumSampleAge = locationPolicy.maximumSampleAge
        recentAcceptedDeviceLocationTimestamps.removeAll { timestamp in
            now.timeIntervalSince(timestamp) > maximumSampleAge
        }
    }

    private func validatePolicy() throws {
        guard locationPolicy.maximumSampleAge.isFinite,
              locationPolicy.maximumSampleAge >= 0,
              locationPolicy.maximumFutureClockSkew.isFinite,
              locationPolicy.maximumFutureClockSkew >= 0 else {
            throw Self.locationFailure(
                message: "The navigation timestamp policy is invalid.",
                recovery: "Restore the release-approved navigation timing policy."
            )
        }
    }

    private func validateFreshness(
        timestamp: Date,
        now: Date,
        invalidMessage: String,
        staleMessage: String,
        futureMessage: String
    ) throws {
        guard timestamp.timeIntervalSinceReferenceDate.isFinite,
              now.timeIntervalSinceReferenceDate.isFinite else {
            throw Self.locationFailure(
                message: invalidMessage,
                recovery: "Acquire a fresh GNSS fix with a valid device timestamp."
            )
        }
        let age = now.timeIntervalSince(timestamp)
        guard age.isFinite else {
            throw Self.locationFailure(
                message: invalidMessage,
                recovery: "Acquire a fresh GNSS fix with a valid device timestamp."
            )
        }
        if age > locationPolicy.maximumSampleAge {
            throw Self.locationFailure(
                message: staleMessage,
                recovery: "Wait for a fresh GNSS fix and retry."
            )
        }
        if age < -locationPolicy.maximumFutureClockSkew {
            throw Self.locationFailure(
                message: futureMessage,
                recovery: "Correct the device clock and acquire a new GNSS fix."
            )
        }
    }

    private static func locationFailure(
        message: String,
        recovery: String
    ) -> OfflineNavigationFailure {
        OfflineNavigationFailure(
            code: .locationRejected,
            message: message,
            recovery: recovery,
            isRecoverable: true
        )
    }
}

/// Captures the synchronous invariants that must still hold after HERE's
/// asynchronous return-to-route calculation completes. A rejected location can
/// pause the actor while that native callback is outstanding; such a result is
/// stale and must never resume guidance.
struct HereNavigationRerouteCommitBoundary: Equatable, Sendable {
    let routeID: String
    let delegateGeneration: UUID

    func permitsCommit(
        activeRouteID: String?,
        currentDelegateGeneration: UUID?,
        state: OfflineNavigationSessionState,
        pausedForRejectedLocation: Bool
    ) -> Bool {
        guard !pausedForRejectedLocation,
              activeRouteID == routeID,
              currentDelegateGeneration == delegateGeneration,
              case .rerouting(let reroutingRouteID) = state,
              reroutingRouteID == routeID else {
            return false
        }
        return true
    }
}

enum HereNavigationNativeCallbackKind: CaseIterable, Equatable, Sendable {
    case eventText
    case progress
    case deviation
    case destination
}

/// Native delegates can outlive the input that queued them. Only callbacks for
/// the current delegate generation and an exactly navigating route may mutate
/// guidance. In particular, a rejected temporal input owns the paused state
/// until a fresh accepted fix resumes the session.
struct HereNavigationNativeCallbackBoundary {
    static func permits(
        _ kind: HereNavigationNativeCallbackKind,
        expectedGeneration: UUID,
        currentDelegateGeneration: UUID?,
        activeRouteID: String?,
        state: OfflineNavigationSessionState,
        pausedForRejectedLocation: Bool,
        rerouteInFlight: Bool
    ) -> Bool {
        guard expectedGeneration == currentDelegateGeneration,
              !pausedForRejectedLocation,
              !rerouteInFlight,
              let activeRouteID,
              case .navigating(let navigatingRouteID, _) = state,
              navigatingRouteID == activeRouteID else {
            return false
        }

        switch kind {
        case .eventText, .progress, .deviation, .destination:
            return true
        }
    }
}

enum HereNavigationVoicePolicy: Equatable, Sendable {
    /// Requires an exact locale match in both HERE maneuver text and an
    /// installed Apple system voice. This is deliberately a locale, not an
    /// EusoTrip dialect claim: callers must not promote a regional preference
    /// (for example en-US-SW) unless both native systems can represent it.
    case required(localeIdentifier: String)
    /// Honest text/event guidance only. This mode never satisfies the separate
    /// `offlineVoiceGuidance` capability.
    case disabled

    static let requiredEnglishUS = Self.required(localeIdentifier: "en-US")
}

#if canImport(heresdk)
@preconcurrency import heresdk

#if canImport(AVFoundation)
@preconcurrency import AVFoundation

@MainActor
private protocol HereOfflineVoiceOutput: AnyObject {
    func prepareAudibleOutput(sessionID: UUID) throws
    func speak(_ text: String, sessionID: UUID)
    func stop(sessionID: UUID)
}

private enum HereOfflineVoicePreparationError: Error {
    case audioSessionUnavailable
    case outputRouteUnavailable
    case outputMuted
}

@MainActor
private final class HereAVSpeechOfflineVoiceOutput: HereOfflineVoiceOutput {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice
    private var activeSessionID: UUID?

    static func makeIfInstalled(
        localeIdentifier: String
    ) -> HereAVSpeechOfflineVoiceOutput? {
        guard let voice = AVSpeechSynthesisVoice.speechVoices().first(where: {
            $0.language.caseInsensitiveCompare(localeIdentifier) == .orderedSame
        }) else { return nil }
        return HereAVSpeechOfflineVoiceOutput(voice: voice)
    }

    static func canPrepareAudibleEnglishUSOutput() -> Bool {
        guard let output = makeIfInstalled(localeIdentifier: "en-US") else {
            return false
        }
        let sessionID = UUID()
        do {
            try output.prepareAudibleOutput(sessionID: sessionID)
            output.stop(sessionID: sessionID)
            return true
        } catch {
            output.stop(sessionID: sessionID)
            return false
        }
    }

    private init(voice: AVSpeechSynthesisVoice) {
        self.voice = voice
    }

    func prepareAudibleOutput(sessionID: UUID) throws {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers]
            )
            try audioSession.setActive(true)
        } catch {
            throw HereOfflineVoicePreparationError.audioSessionUnavailable
        }
        guard !audioSession.currentRoute.outputs.isEmpty else {
            try? audioSession.setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            throw HereOfflineVoicePreparationError.outputRouteUnavailable
        }
        guard audioSession.outputVolume > 0 else {
            try? audioSession.setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            throw HereOfflineVoicePreparationError.outputMuted
        }
        activeSessionID = sessionID
        #else
        _ = sessionID
        throw HereOfflineVoicePreparationError.audioSessionUnavailable
        #endif
    }

    func speak(_ text: String, sessionID: UUID) {
        guard activeSessionID == sessionID, !text.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    func stop(sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        activeSessionID = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        #endif
    }
}

private final class HereOfflineVoiceOutputBox: @unchecked Sendable {
    @MainActor let output: any HereOfflineVoiceOutput

    @MainActor
    init(output: any HereOfflineVoiceOutput) {
        self.output = output
    }
}
#endif

private final class HereNativeDeviationBox: @unchecked Sendable {
    let deviation: RouteDeviation
    let originalRoute: Route
    let currentCoordinates: GeoCoordinates
    let crossTrackMeters: Double
    let observedAt: Date?

    init(
        deviation: RouteDeviation,
        originalRoute: Route,
        currentCoordinates: GeoCoordinates,
        crossTrackMeters: Double,
        observedAt: Date?
    ) {
        self.deviation = deviation
        self.originalRoute = originalRoute
        self.currentCoordinates = currentCoordinates
        self.crossTrackMeters = crossTrackMeters
        self.observedAt = observedAt
    }
}

private final class HereNavigationDelegateBridge:
    EventTextDelegate,
    RouteProgressDelegate,
    RouteDeviationDelegate,
    DestinationReachedDelegate,
    @unchecked Sendable
{
    weak var navigator: Navigator?
    let onEventText: @Sendable (String, GeoCoordinates?) -> Void
    let onProgress: @Sendable (Int64, GeoCoordinates?) -> Void
    let onDeviation: @Sendable (HereNativeDeviationBox) -> Void
    let onDestination: @Sendable () -> Void

    init(
        navigator: Navigator,
        onEventText: @escaping @Sendable (String, GeoCoordinates?) -> Void,
        onProgress: @escaping @Sendable (Int64, GeoCoordinates?) -> Void,
        onDeviation: @escaping @Sendable (HereNativeDeviationBox) -> Void,
        onDestination: @escaping @Sendable () -> Void
    ) {
        self.navigator = navigator
        self.onEventText = onEventText
        self.onProgress = onProgress
        self.onDeviation = onDeviation
        self.onDestination = onDestination
    }

    func onEventTextUpdated(_ eventText: heresdk.EventText) {
        let text = eventText.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let coordinates = eventText.maneuverNotificationDetails?.maneuver.coordinates
        onEventText(text, coordinates)
    }

    func onRouteProgressUpdated(_ routeProgress: RouteProgress) {
        guard let next = routeProgress.maneuverProgress.first else { return }
        guard let remainingDistance = Int64(exactly: next.remainingDistanceInMeters),
              remainingDistance >= 0 else { return }
        let coordinates = navigator?.getManeuver(index: next.maneuverIndex)?.coordinates
        onProgress(remainingDistance, coordinates)
    }

    func onRouteDeviation(_ routeDeviation: RouteDeviation) {
        guard let route = navigator?.route else { return }

        let currentLocation = routeDeviation.currentLocation
        let currentCoordinates = currentLocation.mapMatchedLocation?.coordinates
            ?? currentLocation.originalLocation.coordinates

        let lastCoordinates: GeoCoordinates?
        if let lastLocation = routeDeviation.lastLocationOnRoute {
            lastCoordinates = lastLocation.mapMatchedLocation?.coordinates
                ?? lastLocation.originalLocation.coordinates
        } else {
            lastCoordinates = route.sections.first?.departurePlace.originalCoordinates
        }
        guard let lastCoordinates else { return }
        let distance = currentCoordinates.distance(to: lastCoordinates)
        guard distance.isFinite, distance >= 0 else { return }
        onDeviation(
            HereNativeDeviationBox(
                deviation: routeDeviation,
                originalRoute: route,
                currentCoordinates: currentCoordinates,
                crossTrackMeters: distance,
                observedAt: currentLocation.originalLocation.time
            )
        )
    }

    func onDestinationReached() {
        onDestination()
    }
}

actor HereNavigateNavigationSession: OfflineNavigationSessionProviding {
    private static let deviationThresholdMeters = 50.0
    private static let deviationSampleThreshold = 3
    /// HERE 4.27's Navigator does not expose installed RegionId attribution or
    /// an installed-map boundary callback. This stays false until EusoTrip can
    /// bind the native route/location stream to validated local region geometry.
    private static var hasInstalledCoverageBoundaryEvidence: Bool { false }

    private let routeStore: HereNativeRouteStore
    private let navigator: Navigator?
    private let locationPolicy: HereNavigationLocationAcceptancePolicy
    private let voicePolicy: HereNavigationVoicePolicy
    private var timestampBoundary: HereNavigationTimestampBoundary
    #if canImport(AVFoundation)
    private var voiceOutput: HereOfflineVoiceOutputBox?
    private var voiceSessionID: UUID?
    #endif
    private var routingEngine: OfflineRoutingEngine?
    private var delegateBridge: HereNavigationDelegateBridge?
    /// HERE can deliver one callback that was queued before a route/delegate
    /// replacement. A fresh token for every native route installation makes
    /// those callbacks harmless instead of letting stale guidance reach the
    /// active freight session.
    private var delegateGeneration: UUID?
    private var runtimeLeaseID: UUID?
    private var state: OfflineNavigationSessionState = .idle
    private var eventHandler: OfflineNavigationEventHandler?
    private var activeRouteID: String?
    private var activeMode: OfflineRouteMode?
    private var lastManeuverDistanceMeters: Int64 = 0
    private var lastManeuverCoordinates: OfflineGeoCoordinate?
    private var maneuverSequence = 0
    private var deviationSamples = 0
    private var rerouteInFlight = false
    private var rerouteGeneration: UUID?
    private var pausedForRejectedLocation = false

    init(
        routeStore: HereNativeRouteStore = .shared,
        locationPolicy: HereNavigationLocationAcceptancePolicy = .production,
        voicePolicy: HereNavigationVoicePolicy = .requiredEnglishUS
    ) {
        self.routeStore = routeStore
        self.locationPolicy = locationPolicy
        self.voicePolicy = voicePolicy
        self.timestampBoundary = HereNavigationTimestampBoundary(
            locationPolicy: locationPolicy
        )
        self.navigator = try? Navigator()
    }

    static func canInitializeNativeGuidance() -> Bool {
        (try? Navigator()) != nil
    }

    @MainActor
    static func canInitializeOfflineVoiceGuidance() -> Bool {
        #if canImport(AVFoundation)
        HereAVSpeechOfflineVoiceOutput.canPrepareAudibleEnglishUSOutput()
        #else
        false
        #endif
    }

    func currentState() async -> OfflineNavigationSessionState {
        state
    }

    func start(
        route: OfflineLocalRoute,
        eventHandler: @escaping OfflineNavigationEventHandler
    ) async throws {
        guard !isActive else {
            throw OfflineNavigationFailure(
                code: .sessionAlreadyActive,
                message: "An offline navigation session is already active.",
                recovery: "Stop the active trip before starting another route.",
                isRecoverable: true
            )
        }
        self.eventHandler = eventHandler
        guard route.mode == .road || route.mode == .truck else {
            try failAndThrow(
                routeID: route.id,
                code: .unsupportedRouteMode,
                message: "HERE local guidance supports road and truck routes only.",
                recovery: "Use the cached server-canonical package for rail or vessel execution."
            )
        }
        guard route.provenance == .hereOfflineLocal else {
            try failAndThrow(
                routeID: route.id,
                code: .unsupportedRouteProvenance,
                message: "This route was not produced by the local HERE routing engine.",
                recovery: "Calculate a new road or truck route from installed HERE map data."
            )
        }
        guard Self.hasInstalledCoverageBoundaryEvidence else {
            try failAndThrow(
                routeID: route.id,
                code: .mapCoverageMissing,
                message: "HERE cannot prove installed-region coverage and boundary behavior for this guidance session.",
                recovery: "Add release-validated installed-region geometry before enabling native freight guidance."
            )
        }
        guard SDKNativeEngine.sharedInstance?.isOfflineMode == true else {
            try failAndThrow(
                routeID: route.id,
                code: .nativeGuidanceUnavailable,
                message: "HERE guidance is blocked until native radio silence is confirmed.",
                recovery: "Prepare offline maps with the radio-silent policy before departure."
            )
        }
        guard let navigator else {
            try failAndThrow(
                routeID: route.id,
                code: .nativeGuidanceUnavailable,
                message: "HERE native guidance could not initialize.",
                recovery: "Verify the Navigate entitlement and restart offline maps."
            )
        }
        guard let nativeRoute = await routeStore.route(for: route.id),
              nativeRoute.mode == route.mode else {
            try failAndThrow(
                routeID: route.id,
                code: .routeDataUnavailable,
                message: "The native HERE route is no longer available in this process.",
                recovery: "Recalculate the route locally before starting guidance."
            )
        }
        do {
            routingEngine = try OfflineRoutingEngine()
        } catch {
            try failAndThrow(
                routeID: route.id,
                code: .nativeGuidanceUnavailable,
                message: "HERE offline rerouting could not initialize.",
                recovery: "Verify the offline-routing entitlement before departure."
            )
        }
        switch voicePolicy {
        case .required(let localeIdentifier):
            guard localeIdentifier.caseInsensitiveCompare("en-US") == .orderedSame else {
                try failAndThrow(
                    routeID: route.id,
                    code: .nativeGuidanceUnavailable,
                    message: "Offline voice guidance cannot represent the requested locale exactly.",
                    recovery: "Choose text-only guidance or pass en-US after the user explicitly accepts that exact system voice."
                )
            }
            #if canImport(AVFoundation)
            let output = await MainActor.run {
                HereAVSpeechOfflineVoiceOutput.makeIfInstalled(
                    localeIdentifier: localeIdentifier
                )
                    .map { HereOfflineVoiceOutputBox(output: $0) }
            }
            guard let output else {
                try failAndThrow(
                    routeID: route.id,
                    code: .nativeGuidanceUnavailable,
                    message: "Offline voice guidance is unavailable because no installed en-US system voice was proven.",
                    recovery: "Install an en-US system voice before departure, or explicitly choose text-only guidance."
                )
            }
            let sessionID = UUID()
            do {
                try await MainActor.run {
                    try output.output.prepareAudibleOutput(sessionID: sessionID)
                }
            } catch {
                try failAndThrow(
                    routeID: route.id,
                    code: .nativeGuidanceUnavailable,
                    message: "Offline voice guidance could not prepare an audible system output.",
                    recovery: "Select an audio route, raise the device volume, and retry before departure."
                )
            }
            voiceOutput = output
            voiceSessionID = sessionID
            #else
            try failAndThrow(
                routeID: route.id,
                code: .nativeGuidanceUnavailable,
                message: "Offline voice guidance is unavailable in this build.",
                recovery: "Link AVFoundation and prove an installed en-US system voice."
            )
            #endif
        case .disabled:
            #if canImport(AVFoundation)
            voiceOutput = nil
            voiceSessionID = nil
            #endif
        }

        let leaseID: UUID
        do {
            leaseID = try await MainActor.run {
                try HereNavigateRuntimeSupervisor.shared
                    .acquireNavigationLease(owner: self)
            }
        } catch {
            await stopPreparedVoiceOutput()
            try failAndThrow(
                routeID: route.id,
                code: .nativeGuidanceUnavailable,
                message: "HERE native guidance could not acquire the shared radio-silent runtime.",
                recovery: "Finish connected map maintenance, then prepare the shared engine in radio-silent mode."
            )
        }
        runtimeLeaseID = leaseID

        activeRouteID = route.id
        activeMode = route.mode
        maneuverSequence = 0
        lastManeuverDistanceMeters = 0
        lastManeuverCoordinates = nil
        deviationSamples = 0
        rerouteInFlight = false
        rerouteGeneration = nil
        pausedForRejectedLocation = false
        timestampBoundary.reset()
        transition(.starting(routeID: route.id))

        installNativeDelegates(on: navigator)

        var notificationOptions = ManeuverNotificationOptions()
        notificationOptions.language = .enUs
        notificationOptions.unitSystem = .metric
        notificationOptions.enableLaneRecommendation = true
        navigator.maneuverNotificationOptions = notificationOptions
        navigator.route = nativeRoute.route

        // HERE does not expose installed-region attribution for navigator state.
        transition(.navigating(routeID: route.id, coverage: .unknown))
        eventHandler(.coverageChanged(.unknown))
    }

    private func installNativeDelegates(on navigator: Navigator) {
        let generation = UUID()
        delegateGeneration = generation
        let bridge = HereNavigationDelegateBridge(
            navigator: navigator,
            onEventText: { [weak self] text, coordinates in
                guard let self else { return }
                Task {
                    await self.receiveEventText(
                        text,
                        coordinates: coordinates,
                        generation: generation
                    )
                }
            },
            onProgress: { [weak self] distance, coordinates in
                guard let self else { return }
                Task {
                    await self.receiveProgress(
                        distance: distance,
                        coordinates: coordinates,
                        generation: generation
                    )
                }
            },
            onDeviation: { [weak self] deviation in
                guard let self else { return }
                Task {
                    await self.receiveDeviation(
                        deviation,
                        generation: generation
                    )
                }
            },
            onDestination: { [weak self] in
                guard let self else { return }
                Task { await self.receiveDestination(generation: generation) }
            }
        )
        delegateBridge = bridge
        navigator.eventTextDelegate = bridge
        navigator.routeProgressDelegate = bridge
        navigator.routeDeviationDelegate = bridge
        navigator.destinationReachedDelegate = bridge
    }

    func feed(location: OfflineDeviceLocationSample) async throws {
        guard let navigator, let routeID = activeRouteID, isActive else {
            throw OfflineNavigationFailure(
                code: .locationRejected,
                message: "There is no active native guidance session for this location.",
                recovery: "Start a local road or truck route before feeding device locations.",
                isRecoverable: true
            )
        }
        guard location.provenance != .unknown else {
            let failure = OfflineNavigationFailure(
                code: .locationRejected,
                message: "The location sample has unknown provenance.",
                recovery: "Feed a device, external-GNSS, or fused sample. Simulation requires the explicit debug-only policy.",
                isRecoverable: true
            )
            pauseForRejectedInput(failure, routeID: routeID)
            throw failure
        }
        if location.provenance == .simulated, !locationPolicy.allowsSimulatedLocations {
            let failure = OfflineNavigationFailure(
                code: .locationRejected,
                message: "Simulated locations are blocked by the production guidance policy.",
                recovery: "Use a device or external GNSS sample. Simulator input requires the explicit debug-only policy.",
                isRecoverable: true
            )
            pauseForRejectedInput(failure, routeID: routeID)
            throw failure
        }
        do {
            try timestampBoundary.acceptDeviceLocation(
                timestamp: location.timestamp
            )
        } catch let failure as OfflineNavigationFailure {
            pauseForRejectedInput(failure, routeID: routeID)
            throw failure
        } catch {
            let failure = OfflineNavigationFailure(
                code: .locationRejected,
                message: "The location timestamp could not be validated for freight guidance.",
                recovery: "Acquire a fresh GNSS fix and retry.",
                isRecoverable: true
            )
            pauseForRejectedInput(failure, routeID: routeID)
            throw failure
        }

        var nativeLocation = Location(
            coordinates: GeoCoordinates(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        )
        nativeLocation.time = location.timestamp
        nativeLocation.horizontalAccuracyInMeters = location.horizontalAccuracyMeters
        nativeLocation.speedInMetersPerSecond = location.speedMetersPerSecond
        nativeLocation.bearingInDegrees = location.courseDegrees
        navigator.onLocationUpdated(nativeLocation)
        if pausedForRejectedLocation {
            pausedForRejectedLocation = false
            transition(.navigating(routeID: routeID, coverage: .unknown))
        }
    }

    private func pauseForRejectedInput(
        _ failure: OfflineNavigationFailure,
        routeID: String
    ) {
        pausedForRejectedLocation = true
        deviationSamples = 0
        transition(.paused(routeID: routeID, reason: failure.message))
        eventHandler?(.inputRejected(failure))
    }

    func stop() async {
        let routeID = activeRouteID
        await detachNativeGuidance()
        activeRouteID = nil
        activeMode = nil
        rerouteInFlight = false
        rerouteGeneration = nil
        deviationSamples = 0
        pausedForRejectedLocation = false
        timestampBoundary.reset()
        transition(.stopped(routeID: routeID, stoppedAt: Date()))
        eventHandler = nil
    }

    private var isActive: Bool {
        switch state {
        case .starting, .navigating, .paused, .offRoute, .rerouting:
            return true
        case .idle, .arrived, .stopped, .failed:
            return false
        }
    }

    private func permitsNativeCallback(
        _ kind: HereNavigationNativeCallbackKind,
        generation: UUID
    ) -> Bool {
        HereNavigationNativeCallbackBoundary.permits(
            kind,
            expectedGeneration: generation,
            currentDelegateGeneration: delegateGeneration,
            activeRouteID: activeRouteID,
            state: state,
            pausedForRejectedLocation: pausedForRejectedLocation,
            rerouteInFlight: rerouteInFlight
        )
    }

    private func receiveProgress(
        distance: Int64,
        coordinates: GeoCoordinates?,
        generation: UUID
    ) {
        guard permitsNativeCallback(.progress, generation: generation) else { return }
        lastManeuverDistanceMeters = max(distance, 0)
        if let coordinates {
            lastManeuverCoordinates = try? OfflineGeoCoordinate(
                latitude: coordinates.latitude,
                longitude: coordinates.longitude
            )
        }
    }

    private func receiveEventText(
        _ text: String,
        coordinates: GeoCoordinates?,
        generation: UUID
    ) async {
        guard permitsNativeCallback(.eventText, generation: generation) else { return }
        let coordinate = coordinates.flatMap {
            try? OfflineGeoCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        } ?? lastManeuverCoordinates
        guard let event = try? OfflineNavigationManeuverEvent(
            sequence: maneuverSequence,
            instruction: text,
            distanceMeters: lastManeuverDistanceMeters,
            coordinate: coordinate
        ) else { return }
        maneuverSequence += 1
        eventHandler?(.maneuver(event))
        #if canImport(AVFoundation)
        if let voiceOutput, let voiceSessionID {
            await MainActor.run {
                voiceOutput.output.speak(text, sessionID: voiceSessionID)
            }
        }
        #endif
    }

    private func receiveDeviation(
        _ native: HereNativeDeviationBox,
        generation: UUID
    ) async {
        guard permitsNativeCallback(.deviation, generation: generation),
              let routeID = activeRouteID else { return }
        let observedAt: Date
        do {
            observedAt = try timestampBoundary.acceptDeviation(
                timestamp: native.observedAt
            )
        } catch let failure as OfflineNavigationFailure {
            pauseForRejectedInput(failure, routeID: routeID)
            return
        } catch {
            let failure = OfflineNavigationFailure(
                code: .locationRejected,
                message: "Route deviation evidence could not be validated for freight guidance.",
                recovery: "Wait for a fresh GNSS fix before rerouting.",
                isRecoverable: true
            )
            pauseForRejectedInput(failure, routeID: routeID)
            return
        }
        if native.crossTrackMeters < Self.deviationThresholdMeters {
            deviationSamples = 0
            return
        }
        deviationSamples += 1
        guard deviationSamples >= Self.deviationSampleThreshold else { return }
        let deviation: OfflineNavigationDeviation
        do {
            deviation = try OfflineNavigationDeviation(
                crossTrackMeters: native.crossTrackMeters,
                consecutiveSamples: deviationSamples,
                observedAt: observedAt
            )
        } catch {
            let failure = OfflineNavigationFailure(
                code: .routeDeviation,
                message: "HERE produced invalid route deviation evidence.",
                recovery: "Wait for fresh GNSS evidence before attempting an offline reroute.",
                isRecoverable: true
            )
            pauseForRejectedInput(failure, routeID: routeID)
            return
        }

        transition(.offRoute(routeID: routeID, deviation: deviation))
        eventHandler?(.deviationDetected(deviation))
        await returnToRoute(
            native,
            routeID: routeID,
            generation: generation
        )
    }

    private func returnToRoute(
        _ native: HereNativeDeviationBox,
        routeID: String,
        generation: UUID
    ) async {
        guard let routingEngine, let navigator, let mode = activeMode else { return }
        rerouteInFlight = true
        rerouteGeneration = generation
        transition(.rerouting(routeID: routeID))
        let commitBoundary = HereNavigationRerouteCommitBoundary(
            routeID: routeID,
            delegateGeneration: generation
        )

        var waypoint = Waypoint(coordinates: native.currentCoordinates)
        waypoint.headingInDegrees = native.deviation.currentLocation.mapMatchedLocation?.bearingInDegrees
            ?? native.deviation.currentLocation.originalLocation.bearingInDegrees

        let result: Result<Route, OfflineNavigationFailure> = await withCheckedContinuation { continuation in
            _ = routingEngine.returnToRoute(
                native.originalRoute,
                startingPoint: waypoint,
                lastTraveledSectionIndex: native.deviation.lastTraveledSectionIndex,
                traveledDistanceOnLastSectionInMeters: native.deviation.traveledDistanceOnLastSectionInMeters
            ) { error, routes in
                guard error == nil, let route = routes?.first else {
                    continuation.resume(
                        returning: .failure(
                            OfflineNavigationFailure(
                                code: .offlineRerouteFailed,
                                message: "HERE could not return to the route using installed map data.",
                                recovery: "Stop safely, install missing corridor maps, or retry from the last covered road.",
                                isRecoverable: true
                            )
                        )
                    )
                    return
                }
                continuation.resume(returning: .success(route))
            }
        }

        guard rerouteGeneration == generation else { return }
        rerouteInFlight = false
        rerouteGeneration = nil
        guard commitBoundary.permitsCommit(
            activeRouteID: activeRouteID,
            currentDelegateGeneration: delegateGeneration,
            state: state,
            pausedForRejectedLocation: pausedForRejectedLocation
        ) else { return }
        switch result {
        case .success(let newRoute):
            invalidateNativeDelegates(on: navigator)
            navigator.route = newRoute
            installNativeDelegates(on: navigator)
            deviationSamples = 0
            transition(.navigating(routeID: routeID, coverage: .unknown))
            eventHandler?(.coverageChanged(.unknown))
            await routeStore.replace(
                HereNativeRouteBox(route: newRoute, mode: mode),
                id: routeID
            )
        case .failure(let failure):
            transition(.paused(routeID: routeID, reason: failure.message))
            eventHandler?(.rerouteFailed(failure))
        }
    }

    private func receiveDestination(generation: UUID) async {
        guard permitsNativeCallback(.destination, generation: generation),
              let routeID = activeRouteID else { return }
        let date = Date()
        transition(.arrived(routeID: routeID, arrivedAt: date))
        eventHandler?(.arrived(date))
        await detachNativeGuidance()
        activeRouteID = nil
        activeMode = nil
        rerouteInFlight = false
        rerouteGeneration = nil
        deviationSamples = 0
        pausedForRejectedLocation = false
        timestampBoundary.reset()
        eventHandler = nil
    }

    private func detachNativeGuidance() async {
        if let navigator {
            invalidateNativeDelegates(on: navigator)
            navigator.route = nil
        }
        routingEngine = nil
        await stopPreparedVoiceOutput()
        if let runtimeLeaseID {
            await MainActor.run {
                HereNavigateRuntimeSupervisor.shared
                    .releaseNavigationLease(runtimeLeaseID)
            }
            self.runtimeLeaseID = nil
        }
    }

    private func stopPreparedVoiceOutput() async {
        #if canImport(AVFoundation)
        if let voiceOutput, let voiceSessionID {
            await MainActor.run {
                voiceOutput.output.stop(sessionID: voiceSessionID)
            }
        }
        voiceOutput = nil
        voiceSessionID = nil
        #endif
    }

    private func invalidateNativeDelegates(on navigator: Navigator) {
        delegateGeneration = nil
        navigator.eventTextDelegate = nil
        navigator.routeProgressDelegate = nil
        navigator.routeDeviationDelegate = nil
        navigator.destinationReachedDelegate = nil
        delegateBridge = nil
    }

    private func transition(_ next: OfflineNavigationSessionState) {
        state = next
        eventHandler?(.stateChanged(next))
    }

    private func failAndThrow(
        routeID: String?,
        code: OfflineNavigationFailureCode,
        message: String,
        recovery: String?
    ) throws -> Never {
        let failure = OfflineNavigationFailure(
            code: code,
            message: message,
            recovery: recovery,
            isRecoverable: true
        )
        transition(.failed(routeID: routeID, failure: failure))
        eventHandler = nil
        activeRouteID = nil
        activeMode = nil
        routingEngine = nil
        rerouteInFlight = false
        rerouteGeneration = nil
        deviationSamples = 0
        pausedForRejectedLocation = false
        timestampBoundary.reset()
        throw failure
    }
}

#else

actor HereNavigateNavigationSession: OfflineNavigationSessionProviding {
    private var state: OfflineNavigationSessionState = .idle

    init(
        locationPolicy: HereNavigationLocationAcceptancePolicy = .production,
        voicePolicy: HereNavigationVoicePolicy = .requiredEnglishUS
    ) {
        _ = locationPolicy
        _ = voicePolicy
    }

    static func canInitializeNativeGuidance() -> Bool { false }

    @MainActor
    static func canInitializeOfflineVoiceGuidance() -> Bool { false }

    func currentState() async -> OfflineNavigationSessionState {
        state
    }

    func start(
        route: OfflineLocalRoute,
        eventHandler: @escaping OfflineNavigationEventHandler
    ) async throws {
        let failure = Self.missingFrameworkFailure
        state = .failed(routeID: route.id, failure: failure)
        eventHandler(.stateChanged(state))
        throw failure
    }

    func feed(location: OfflineDeviceLocationSample) async throws {
        _ = location
        let failure = Self.missingFrameworkFailure
        state = .failed(routeID: nil, failure: failure)
        throw failure
    }

    func stop() async {
        state = .stopped(routeID: nil, stoppedAt: Date())
    }

    private static let missingFrameworkFailure = OfflineNavigationFailure(
        code: .nativeGuidanceUnavailable,
        message: "The licensed HERE Navigate framework is not present in this build.",
        recovery: "Install the entitled HERE Navigate binary and rebuild the iOS app.",
        isRecoverable: false
    )
}

#endif
