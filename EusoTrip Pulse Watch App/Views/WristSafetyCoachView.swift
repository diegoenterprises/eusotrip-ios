//
//  WristSafetyCoachView.swift
//  EusoTrip Pulse Watch App
//
//  A glanceable mirror of the native iPhone Safety Coach. The watch renders
//  only server-collected 30-day evidence and advisory items grounded in that
//  evidence. It never substitutes a generic pack when generation is down.
//

import SwiftUI
import Combine
import WatchKit

struct WatchSafetyEvidence: Equatable {
    let windowDays: Int
    let incidents: Int
    let violations: Int
    let nearMisses: Int
    let hazmatEndorsed: Bool?
    let driverProfileMatched: Bool
    let collectedAt: Date?
}

private struct SafetyCoachEnvelope: Decodable {
    struct Result: Decodable {
        struct DataContainer: Decodable { let json: Pack }
        let data: DataContainer
    }

    struct Pack: Decodable {
        struct Evidence: Decodable {
            let windowDays: Int
            let incidents: Int
            let violations: Int
            let nearMisses: Int
            let hazmatEndorsed: Bool?
            let driverProfileMatched: Bool
            let collectedAt: Double?
        }

        struct Item: Decodable {
            let title: String
            let body: String
            let severity: String?
            let topic: String?
        }

        let items: [Item]
        let role: String?
        let vertical: String?
        let source: String?
        let advisory: Bool?
        let evidence: Evidence?
        let generatedAt: Double?
    }

    let result: Result
}

@MainActor
final class WristSafetyCoachStore: ObservableObject {
    static let shared = WristSafetyCoachStore()

    struct CoachItem: Identifiable, Equatable {
        let id: String
        let title: String
        let body: String
        let severity: String
        let topic: String
    }

    @Published private(set) var items: [CoachItem] = []
    @Published private(set) var role = ""
    @Published private(set) var vertical = ""
    @Published private(set) var source: String?
    @Published private(set) var evidence: WatchSafetyEvidence?
    @Published private(set) var generatedAt: Date?
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private(set) var boundUserId: String?
    private var requestGeneration = 0

    var priorityItem: CoachItem? {
        items.enumerated().max { lhs, rhs in
            let left = Self.severityRank(lhs.element.severity)
            let right = Self.severityRank(rhs.element.severity)
            return left == right ? lhs.offset > rhs.offset : left < right
        }?.element
    }

    func resetForIdentity(_ userId: String?) {
        requestGeneration += 1
        boundUserId = userId
        items = []
        role = ""
        vertical = ""
        source = nil
        evidence = nil
        generatedAt = nil
        hasLoadedOnce = false
        isRefreshing = false
        lastError = nil
    }

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn,
              let userId = Self.normalized(auth.userId) else {
            resetForIdentity(nil)
            lastError = "Pair EusoTrip on iPhone to verify your safety signal."
            return
        }

        if boundUserId != userId {
            resetForIdentity(userId)
        }

        requestGeneration += 1
        let generation = requestGeneration
        isRefreshing = true
        lastError = nil

        do {
            let data = try await EsangClient(auth: auth).queryJSON(
                "esangCoach.forDriver",
                input: ["limit": 6]
            )
            let pack = try JSONDecoder().decode(SafetyCoachEnvelope.self, from: data).result.data.json
            guard generation == requestGeneration,
                  boundUserId == userId,
                  Self.normalized(auth.userId) == userId else { return }

            items = pack.items.map { remote in
                CoachItem(
                    id: "\(remote.topic ?? "other")::\(remote.title)",
                    title: remote.title,
                    body: remote.body,
                    severity: Self.normalizedSeverity(remote.severity),
                    topic: remote.topic?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "other"
                )
            }
            role = pack.role?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            vertical = pack.vertical?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            source = pack.source
            evidence = pack.evidence.map {
                WatchSafetyEvidence(
                    windowDays: $0.windowDays,
                    incidents: $0.incidents,
                    violations: $0.violations,
                    nearMisses: $0.nearMisses,
                    hazmatEndorsed: $0.hazmatEndorsed,
                    driverProfileMatched: $0.driverProfileMatched,
                    collectedAt: Self.date(fromEpochMillis: $0.collectedAt)
                )
            }
            generatedAt = Self.date(fromEpochMillis: pack.generatedAt)
            hasLoadedOnce = true
            isRefreshing = false
        } catch {
            guard generation == requestGeneration, boundUserId == userId else { return }
            lastError = Self.compactError(error)
            isRefreshing = false
        }
    }

    static func compactAge(_ date: Date, at now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "NOW" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)M" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)H" }
        return "\(hours / 24)D"
    }

    #if targetEnvironment(simulator)
    func installVisualQA(mode: String) {
        resetForIdentity("visual-safety-user")
        role = "DRIVER"
        vertical = "truck"

        if mode == "safety-error" {
            lastError = "EusoTrip could not verify the 30-day safety signal."
            return
        }

        let now = Date()
        evidence = WatchSafetyEvidence(
            windowDays: 30,
            incidents: mode == "safety-unavailable" ? 0 : 1,
            violations: mode == "safety-unavailable" ? 0 : 2,
            nearMisses: mode == "safety-unavailable" ? 0 : 1,
            hazmatEndorsed: true,
            driverProfileMatched: true,
            collectedAt: now.addingTimeInterval(-75)
        )
        generatedAt = now.addingTimeInterval(-45)
        hasLoadedOnce = true

        if mode == "safety-unavailable" {
            source = "unavailable"
            return
        }

        source = "ai_grounded"
        items = [
            CoachItem(
                id: "hos::visual-priority",
                title: "Review two HOS flags",
                body: "Your 30-day signal includes two HOS violations. Open the source events on iPhone before departure.",
                severity: "watch",
                topic: "hos"
            ),
            CoachItem(
                id: "inspection::visual-incident",
                title: "Debrief the recorded incident",
                body: "One incident is present in the verified window. Review the event with your safety program.",
                severity: "info",
                topic: "inspection"
            ),
            CoachItem(
                id: "fatigue::visual-near-miss",
                title: "Review the near-miss pattern",
                body: "One near-miss is recorded. Confirm the event details before changing your operating plan.",
                severity: "info",
                topic: "fatigue"
            ),
        ]
    }
    #endif

    private static func normalized(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func normalizedSeverity(_ raw: String?) -> String {
        switch raw?.lowercased() {
        case "critical": return "critical"
        case "watch": return "watch"
        default: return "info"
        }
    }

    private static func severityRank(_ raw: String) -> Int {
        switch raw.lowercased() {
        case "critical": return 3
        case "watch": return 2
        default: return 1
        }
    }

    private static func date(fromEpochMillis value: Double?) -> Date? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value / 1_000)
    }

    private static func compactError(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return "EusoTrip could not verify the safety signal."
    }
}

struct WristSafetyCoachView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var connectivity: WatchConnectivityManager
    @StateObject private var store = WristSafetyCoachStore.shared
    @State private var phoneDispatch: PhoneActivationDispatch?
    @State private var showAll = false

    private var visualState: String? {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["EUSOTRIP_PULSE_VISUAL_STATE"]
        #else
        nil
        #endif
    }

    private var isVisualQA: Bool {
        visualState?.hasPrefix("safety-") == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            evidenceSurface
            prioritySurface
            actionRow
            Text(phoneEvidenceLabel)
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundStyle(phoneEvidenceColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .watchEdgeGlow()
        .navigationTitle("Safety")
        .task {
            #if targetEnvironment(simulator)
            if let visualState, isVisualQA {
                store.installVisualQA(mode: visualState)
                return
            }
            #endif
            await store.refresh(auth: auth)
        }
        .onChange(of: auth.userId) { _, newUserId in
            guard !isVisualQA else { return }
            store.resetForIdentity(newUserId?.trimmingCharacters(in: .whitespacesAndNewlines))
            Task { await store.refresh(auth: auth) }
        }
        .sheet(isPresented: $showAll) {
            advisorySheet
        }
        .clipShape(ContainerRelativeShape())
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                guard !isVisualQA else { return }
                WKInterfaceDevice.current().play(.click)
                Task { await store.refresh(auth: auth) }
            } label: {
                SafetySignalMark(
                    color: headerColor,
                    isRefreshing: store.isRefreshing
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh Safety Coach")

            VStack(alignment: .leading, spacing: 1) {
                Text("SAFETY SIGNAL")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(roleAndVertical)
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 44)
        }
        .frame(minHeight: 28)
    }

    @ViewBuilder
    private var evidenceSurface: some View {
        if let evidence = store.evidence {
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    signalMetric("INCIDENTS", evidence.incidents)
                    Divider().frame(height: 26)
                    signalMetric("HOS", evidence.violations)
                    Divider().frame(height: 26)
                    signalMetric("NEAR MISS", evidence.nearMisses)
                }

                HStack(spacing: 4) {
                    Circle().fill(headerColor).frame(width: 4, height: 4)
                    Text(evidenceFooter(evidence))
                        .font(.system(size: 6, weight: .bold, design: .rounded))
                        .tracking(0.45)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(Color.esangCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(headerColor.opacity(0.55), lineWidth: 1)
            }
        } else {
            HStack(spacing: 7) {
                Image(systemName: store.isRefreshing ? "arrow.triangle.2.circlepath" : "exclamationmark.shield")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(store.isRefreshing ? Color.esangBlue : Color.esangAmber)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.isRefreshing ? "VERIFYING 30-DAY SIGNAL" : "SIGNAL UNAVAILABLE")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                    Text(store.isRefreshing ? "Reading EusoTrip records" : "No counts are being assumed")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 43)
            .padding(.horizontal, 7)
            .background(Color.esangCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private func signalMetric(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(value == 0 ? Color.primary : Color.esangAmber)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 5.5, weight: .bold, design: .rounded))
                .tracking(0.35)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var prioritySurface: some View {
        if let item = store.priorityItem {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("NEXT ADVISORY")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .tracking(0.65)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    severityPill(item.severity)
                }

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: topicIcon(item.topic))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(severityColor(item.severity))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                        Text(store.lastError == nil ? item.body : "Refresh failed. Showing the last verified pack.")
                            .font(.system(size: 7.5))
                            .foregroundStyle(store.lastError == nil ? Color.secondary : Color.esangAmber)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 59, alignment: .topLeading)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(Color.esangCard.opacity(0.78), in: RoundedRectangle(cornerRadius: 11))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                severityColor(item.severity),
                                Color.esangMagenta.opacity(0.72),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                    .padding(.vertical, 7)
                    .padding(.leading, 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                severityColor(item.severity).opacity(0.52),
                                Color.esangMagenta.opacity(0.20),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
        } else if store.hasLoadedOnce, store.evidence != nil {
            stateCard(
                icon: "exclamationmark.bubble.fill",
                title: "Coach unavailable",
                detail: "Your signal is verified above. No generic advice was inserted.",
                color: .esangAmber
            )
        } else if store.isRefreshing {
            stateCard(
                icon: "sparkles",
                title: "Grounding Safety Coach",
                detail: "Waiting for verified EusoTrip evidence.",
                color: .esangBlue
            )
        } else {
            stateCard(
                icon: store.boundUserId != nil ? "wifi.exclamationmark" : "iphone.slash",
                title: store.boundUserId != nil ? "Verification failed" : "Pair with EusoTrip",
                detail: store.lastError ?? "Open EusoTrip on iPhone to continue.",
                color: .esangAmber
            )
        }
    }

    private func stateCard(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                Text(detail)
                    .font(.system(size: 7.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 59, alignment: .topLeading)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Color.esangCard.opacity(0.78), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(color.opacity(0.36), lineWidth: 0.8)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 5) {
            if store.items.count > 1 {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    showAll = true
                } label: {
                    HStack(spacing: 2) {
                        Text("ALL \(store.items.count)")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .frame(minWidth: 47, minHeight: 29)
                    .foregroundStyle(Color.esangBlue)
                    .background(Color.esangBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View all \(store.items.count) safety advisories")
            }

            Button {
                WKInterfaceDevice.current().play(.click)
                phoneDispatch = connectivity.requestPhoneActivation(
                    transcript: "",
                    reply: "Review Safety Coach evidence on your iPhone.",
                    destination: .safetyCoach,
                    beginListening: false,
                    autoSubmit: false
                )
            } label: {
                Label("Open on iPhone", systemImage: "iphone.and.arrow.forward")
                    .font(.system(size: 9, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 29)
                    .foregroundStyle(.white)
                    .background(LinearGradient.esangPrimary, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
        }
    }

    private var advisorySheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("SAFETY COACH")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text("Grounded advisory pack")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Spacer()
                    Text("\(store.items.count)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.esangBlue)
                }

                ForEach(store.items) { item in
                    advisoryRow(item)
                }

                Text("Advisory only. Evidence comes from EusoTrip incident and HOS records. Open iPhone to inspect source events.")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
        }
        .watchEdgeGlow()
        .navigationTitle("Coach Pack")
    }

    private func advisoryRow(_ item: WristSafetyCoachStore.CoachItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: topicIcon(item.topic))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(severityColor(item.severity))
                    .frame(width: 16)
                Text(item.title)
                    .font(.system(size: 10, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                severityPill(item.severity)
            }
            Text(item.body)
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(7)
        .background(Color.esangCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func severityPill(_ severity: String) -> some View {
        Text(severity.uppercased())
            .font(.system(size: 6, weight: .bold, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(severityColor(severity))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(severityColor(severity).opacity(0.14), in: Capsule())
    }

    private var roleAndVertical: String {
        let role = store.role.isEmpty
            ? "ROLE PENDING"
            : store.role.replacingOccurrences(of: "_", with: " ")
        let vertical = store.vertical.isEmpty ? "" : " · \(store.vertical.uppercased())"
        return role + vertical
    }

    private var headerColor: Color {
        if store.lastError != nil { return .esangAmber }
        if store.evidence != nil { return .esangGreen }
        if store.isRefreshing { return .esangBlue }
        return .secondary
    }

    private func evidenceFooter(_ evidence: WatchSafetyEvidence) -> String {
        let freshness = evidence.collectedAt.map {
            WristSafetyCoachStore.compactAge($0)
        } ?? "TIME UNKNOWN"
        let source = store.source?.lowercased() == "ai_grounded" ? "AI + DATA" : "DATA ONLY"
        return "VERIFIED \(evidence.windowDays)D · \(source) · \(freshness)"
    }

    private var phoneEvidenceLabel: String {
        switch phoneDispatch {
        case .sent: return "iPhone notified"
        case .queued: return "Queued until iPhone reconnects"
        case .unavailable: return "Pair through EusoTrip on iPhone"
        case nil: return connectivity.isReachable ? "iPhone linked" : "iPhone away"
        }
    }

    private var phoneEvidenceColor: Color {
        switch phoneDispatch {
        case .sent: return .esangGreen
        case .queued: return .esangAmber
        case .unavailable: return .esangDanger
        case nil: return connectivity.isReachable ? .esangGreen : .secondary
        }
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "critical": return .esangDanger
        case "watch": return .esangAmber
        default: return .esangBlue
        }
    }

    private func topicIcon(_ topic: String) -> String {
        switch topic.lowercased() {
        case "hos": return "clock.badge.exclamationmark"
        case "hazmat": return "exclamationmark.triangle"
        case "following": return "car.2"
        case "fatigue": return "bed.double"
        case "weather": return "cloud.sun"
        case "vehicle": return "wrench.and.screwdriver"
        case "inspection": return "checkmark.shield"
        case "training": return "graduationcap"
        case "fra_certification": return "train.side.front.car"
        case "stcw": return "ferry"
        case "mmc_medical": return "cross.case"
        case "ptc": return "wave.3.right"
        case "cargo_securement": return "shippingbox"
        case "stowage": return "square.stack.3d.up"
        case "docs": return "doc.text"
        default: return "lightbulb"
        }
    }
}

private struct SafetySignalMark: View {
    let color: Color
    let isRefreshing: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.26),
                            Color.esangCard.opacity(0.94),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.28), lineWidth: 0.8)

            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .symbolEffect(.pulse, options: .repeating, isActive: isRefreshing)

            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
                .shadow(color: color.opacity(0.8), radius: 2)
                .offset(x: 9, y: -9)
                .symbolEffect(.pulse, options: .repeating, isActive: isRefreshing)
        }
        .frame(width: 29, height: 29)
    }
}
