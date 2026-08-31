//
//  RouteOverviewView.swift
//  EusoTrip Watch App
//
//  Driver route evidence for the active load. Every estimate is scoped to
//  the current load identity and every iPhone action reports its handoff state.
//

import SwiftUI
import Combine
import WatchKit

struct RouteOverviewView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var loads: LoadStore
    @StateObject private var route = RouteProgressStore.shared
    @State private var phoneOutcome: RoutePhoneOutcome?

    private var activeLoad: WatchLoad? {
        #if targetEnvironment(simulator)
        if isActiveRouteVisualQA {
            return WatchLoad(
                id: "visual-route-7c3a",
                displayId: "LD-7C3A",
                originCity: "Los Angeles",
                originState: "CA",
                destCity: "Phoenix",
                destState: "AZ",
                pickupAt: nil,
                deliverBy: nil,
                ratePerMile: nil,
                totalRate: nil,
                miles: 372,
                status: "in_transit",
                hazmat: false,
                temperatureF: 38,
                equipment: "reefer",
                brokerName: nil
            )
        }
        #endif
        return loads.active
    }

    private var activeLoadId: String? { activeLoad?.id }

    private var isActiveRouteVisualQA: Bool {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["EUSOTRIP_PULSE_VISUAL_STATE"] == "route-active"
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(spacing: 6) {
            if let load = activeLoad {
                routeHeader(load)
                metricRail
                routeEvidencePanel
                routeActions(load)
            } else {
                emptyState
                if let phoneOutcome {
                    phoneHandoffReceipt(phoneOutcome)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, S.s2)
        .padding(.vertical, 2)
        .navigationTitle("Route")
        .task {
            #if targetEnvironment(simulator)
            if isActiveRouteVisualQA {
                route.installActiveRouteVisualQA(loadId: "visual-route-7c3a")
                return
            }
            #endif
            await route.refresh(auth: auth, loadId: activeLoadId)
        }
        .onChange(of: loads.active?.id) { _, newId in
            guard !isActiveRouteVisualQA else { return }
            phoneOutcome = nil
            Task { await route.refresh(auth: auth, loadId: newId) }
        }
        .onChange(of: auth.isSignedIn) { _, _ in
            guard !isActiveRouteVisualQA else { return }
            Task { await route.refresh(auth: auth, loadId: activeLoadId) }
        }
    }

    private func routeHeader(_ load: WatchLoad) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(route.evidenceColor)
                    .frame(width: 6, height: 6)
                Text("ACTIVE ROUTE")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(load.displayId)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text("\(load.originCity) -> \(load.destCity)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(route.evidenceLabel(at: context.date))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(route.evidenceColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.md))
        .overlay {
            RoundedRectangle(cornerRadius: R.md)
                .stroke(route.evidenceColor.opacity(0.55), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var metricRail: some View {
        HStack(spacing: 0) {
            routeMetric(value: route.etaText, label: "ETA")
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 27)
            routeMetric(value: route.milesRemainingText, label: "MILES LEFT")
        }
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: R.sm))
    }

    private func routeMetric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.esangBlue)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value == "-" ? "not supplied" : value)")
    }

    @ViewBuilder
    private var routeEvidencePanel: some View {
        if let phoneOutcome {
            phoneHandoffReceipt(phoneOutcome)
        } else if let message = route.failureMessage {
            evidenceWarning(message)
        } else {
            waypointPanel
        }
    }

    private var waypointPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("NEXT ROUTED STOP")
                .font(.system(size: 7, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: route.nextWaypoint == nil ? "location.slash" : "location.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(route.nextWaypoint == nil ? Color.esangAmber : Color.esangBlue)
                Text(route.nextWaypoint ?? "No routed stop supplied")
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if let severity = route.weatherSeverity {
                WatchWeatherChip(severity: severity, label: route.weatherFlagDisplay)
                    .frame(maxHeight: 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }

    private func evidenceWarning(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(Color.esangAmber)
            Text(message)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.esangAmber)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(Color.esangAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: R.sm))
    }

    private func routeActions(_ load: WatchLoad) -> some View {
        HStack(spacing: 5) {
            routeActionButton(
                label: "Navigate",
                systemImage: "location.north.fill"
            ) {
                sendToPhone(
                    .navigation,
                    transcript: "navigate to \(load.destShort)",
                    destination: .maps,
                    reply: "Opening driving directions on your iPhone."
                )
            }

            routeActionButton(
                label: "Rest stop",
                systemImage: "bed.double.fill"
            ) {
                sendToPhone(
                    .restStop,
                    transcript: "rest stop near my route to \(load.destShort)",
                    destination: .maps,
                    reply: "Searching for a rest stop on your iPhone."
                )
            }
        }
    }

    private func routeActionButton(
        label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 28)
            .foregroundStyle(.white)
            .background(LinearGradient.esangPrimary, in: RoundedRectangle(cornerRadius: R.sm))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.esangBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No active route")
                        .font(.system(size: 14, weight: .bold))
                    Text("Pulse has no active load from EusoTrip.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            routeActionButton(label: "Find load with ESANG", systemImage: "waveform") {
                sendToPhone(
                    .findLoad,
                    transcript: "Find an active load for me",
                    destination: .esang,
                    reply: "Continuing load search with ESANG on your iPhone.",
                    autoSubmit: true
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.md))
        .overlay {
            RoundedRectangle(cornerRadius: R.md)
                .stroke(Color.esangBlue.opacity(0.45), lineWidth: 1)
        }
    }

    private func phoneHandoffReceipt(_ outcome: RoutePhoneOutcome) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: outcome.systemImage)
                .font(.system(size: 9, weight: .bold))
            Text(outcome.message)
                .font(.system(size: 9, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(outcome.color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(outcome.color.opacity(0.12), in: RoundedRectangle(cornerRadius: R.sm))
        .accessibilityElement(children: .combine)
    }

    private func sendToPhone(
        _ intent: RoutePhoneIntent,
        transcript: String,
        destination: PhoneActivationDestination,
        reply: String,
        autoSubmit: Bool = false
    ) {
        let dispatch = connectivity.requestPhoneActivation(
            transcript: transcript,
            reply: reply,
            destination: destination,
            beginListening: false,
            autoSubmit: autoSubmit
        )
        phoneOutcome = RoutePhoneOutcome(intent: intent, dispatch: dispatch)
    }
}

enum RoutePhoneIntent: String, Equatable {
    case findLoad = "ESANG request"
    case restStop = "Rest-stop request"
    case navigation = "Directions request"
}

struct RoutePhoneOutcome: Equatable {
    let intent: RoutePhoneIntent
    let dispatch: PhoneActivationDispatch

    var message: String {
        switch dispatch {
        case .sent:
            return "\(intent.rawValue) sent to iPhone."
        case .queued:
            return "\(intent.rawValue) queued until iPhone reconnects."
        case .unavailable:
            return "iPhone bridge unavailable. Open EusoTrip on iPhone."
        }
    }

    var systemImage: String {
        switch dispatch {
        case .sent: return "checkmark.circle.fill"
        case .queued: return "clock.arrow.circlepath"
        case .unavailable: return "iphone.slash"
        }
    }

    var color: Color {
        switch dispatch {
        case .sent: return .esangGreen
        case .queued: return .esangAmber
        case .unavailable: return .esangDanger
        }
    }
}

struct RouteProgressPayload: Decodable, Equatable {
    let etaMinutes: Int?
    let milesRemaining: Double?
    let nextWaypoint: String?
    let weatherFlag: String?
}

struct RouteProgressEvidence: Equatable {
    enum Phase: Equatable {
        case idle
        case needsSignIn
        case loading
        case received
        case failed
        #if targetEnvironment(simulator)
        case visualQA
        #endif
    }

    var loadId: String?
    var etaMinutes: Int?
    var milesRemaining: Double?
    var nextWaypoint: String?
    var weatherFlag: String?
    var weatherHeadline: String?
    var receivedAt: Date?
    var lastError: String?
    var phase: Phase = .idle

    var hasRouteValues: Bool {
        etaMinutes != nil || milesRemaining != nil || nextWaypoint != nil
    }

    mutating func begin(loadId: String?, signedIn: Bool) {
        guard signedIn else {
            self = RouteProgressEvidence(
                loadId: loadId,
                lastError: "Sign in on iPhone to request route evidence.",
                phase: .needsSignIn
            )
            return
        }
        guard let loadId else {
            self = RouteProgressEvidence()
            return
        }
        if self.loadId != loadId {
            self = RouteProgressEvidence(loadId: loadId, phase: .loading)
        } else {
            phase = .loading
            lastError = nil
        }
    }

    @discardableResult
    mutating func applyProgress(
        _ payload: RouteProgressPayload,
        for loadId: String,
        receivedAt: Date
    ) -> Bool {
        guard self.loadId == loadId else { return false }
        etaMinutes = payload.etaMinutes
        milesRemaining = payload.milesRemaining
        nextWaypoint = payload.nextWaypoint?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        weatherFlag = payload.weatherFlag?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        weatherHeadline = nil
        self.receivedAt = receivedAt
        lastError = nil
        phase = .received
        return true
    }

    @discardableResult
    mutating func fail(for loadId: String, message: String) -> Bool {
        guard self.loadId == loadId else { return false }
        lastError = message
        phase = .failed
        return true
    }

    @discardableResult
    mutating func applyLaneImpact(
        riskTier: String,
        headline: String?,
        for loadId: String
    ) -> Bool {
        guard self.loadId == loadId else { return false }
        let tier = riskTier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !tier.isEmpty, tier != "none" else { return false }
        weatherFlag = tier
        weatherHeadline = headline?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return true
    }
}

@MainActor
final class RouteProgressStore: ObservableObject {
    static let shared = RouteProgressStore()

    @Published private(set) var evidence = RouteProgressEvidence()
    private var requestGeneration = 0

    var etaText: String {
        guard let minutes = evidence.etaMinutes else { return "-" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        return String(format: "%dh %02dm", hours, remainder)
    }

    var milesRemainingText: String {
        guard let miles = evidence.milesRemaining else { return "-" }
        return String(format: "%.0f", miles)
    }

    var nextWaypoint: String? { evidence.nextWaypoint }

    var weatherSeverity: WatchWeatherSeverity? {
        WatchWeatherSeverity.from(flag: evidence.weatherFlag)
    }

    var weatherFlagDisplay: String {
        if let headline = evidence.weatherHeadline { return headline }
        guard let flag = evidence.weatherFlag else { return "-" }
        return flag.replacingOccurrences(of: "-", with: " ").capitalizedFirst
    }

    var evidenceColor: Color {
        switch evidence.phase {
        case .received where evidence.hasRouteValues:
            return .esangGreen
        case .failed:
            return evidence.receivedAt == nil ? .esangDanger : .esangAmber
        case .needsSignIn, .received:
            return .esangAmber
        case .idle, .loading:
            return .esangBlue
        #if targetEnvironment(simulator)
        case .visualQA:
            return .esangBlue
        #endif
        }
    }

    var failureMessage: String? {
        switch evidence.phase {
        case .needsSignIn, .failed:
            return evidence.lastError
        case .received where !evidence.hasRouteValues:
            return "The server supplied no ETA, distance, or routed stop for this load."
        #if targetEnvironment(simulator)
        case .visualQA:
            return nil
        #endif
        default:
            return nil
        }
    }

    func evidenceLabel(at now: Date) -> String {
        switch evidence.phase {
        case .idle:
            return "NO ACTIVE ROUTE EVIDENCE"
        case .needsSignIn:
            return "IPHONE IDENTITY REQUIRED"
        case .loading:
            if let receivedAt = evidence.receivedAt {
                return "REFRESHING · LAST SERVER RESPONSE \(ageLabel(receivedAt, at: now))"
            }
            return "REQUESTING SERVER ROUTE EVIDENCE"
        case .received:
            guard evidence.hasRouteValues else { return "SERVER RESPONSE · ROUTE DATA MISSING" }
            return "SERVER RESPONSE · \(ageLabel(evidence.receivedAt, at: now))"
        case .failed:
            if let receivedAt = evidence.receivedAt {
                return "LAST SERVER RESPONSE \(ageLabel(receivedAt, at: now)) · REFRESH FAILED"
            }
            return "ROUTE SERVICE UNREACHABLE"
        #if targetEnvironment(simulator)
        case .visualQA:
            return "LAYOUT QA · SIMULATOR FIXTURE"
        #endif
        }
    }

    #if targetEnvironment(simulator)
    func installActiveRouteVisualQA(loadId: String) {
        evidence = RouteProgressEvidence(
            loadId: loadId,
            etaMinutes: 258,
            milesRemaining: 241,
            nextWaypoint: "Quartzsite, AZ",
            weatherFlag: "wind-advisory",
            weatherHeadline: "Crosswind advisory",
            receivedAt: nil,
            lastError: nil,
            phase: .visualQA
        )
    }
    #endif

    func refresh(auth: AuthStore, loadId: String?) async {
        requestGeneration += 1
        let generation = requestGeneration
        evidence.begin(loadId: loadId, signedIn: auth.isSignedIn)
        guard auth.isSignedIn, let loadId else { return }

        let client = EsangClient(auth: auth)
        do {
            let data = try await client.queryJSON(
                "routeOptimization.getProgress",
                input: ["loadId": loadId]
            )
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable { let json: RouteProgressPayload }
                    let data: DataContainer
                }
                let result: Result
            }
            let payload = try JSONDecoder().decode(Envelope.self, from: data).result.data.json
            guard generation == requestGeneration else { return }
            evidence.applyProgress(payload, for: loadId, receivedAt: Date())
        } catch {
            guard generation == requestGeneration else { return }
            evidence.fail(for: loadId, message: compactError(error))
        }

        do {
            let data = try await client.queryJSON(
                "weather.forLoad",
                input: ["loadId": loadId]
            )
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable { let json: ForLoad }
                    let data: DataContainer
                }
                let result: Result
            }
            struct ForLoad: Decodable {
                struct LaneImpact: Decodable {
                    let available: Bool?
                    let riskTier: String?
                    let headline: String?
                }
                let laneImpact: LaneImpact?
            }
            let forLoad = try JSONDecoder().decode(Envelope.self, from: data).result.data.json
            guard generation == requestGeneration,
                  let laneImpact = forLoad.laneImpact,
                  laneImpact.available == true,
                  let riskTier = laneImpact.riskTier else { return }
            evidence.applyLaneImpact(
                riskTier: riskTier,
                headline: laneImpact.headline,
                for: loadId
            )
        } catch {
            // The route response may still carry a coarse weather flag.
        }
    }

    private func compactError(_ error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count > 96 {
            return "Can't refresh route evidence from EusoTrip."
        }
        return trimmed
    }

    private func ageLabel(_ date: Date?, at now: Date) -> String {
        guard let date else { return "NOW" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "NOW" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)M AGO" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)H AGO" }
        return "\(hours / 24)D AGO"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
