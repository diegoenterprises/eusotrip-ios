//
//  VoiceDialectPicker.swift
//  Settings — regional dialect picker (IO 2026 P0-4).
//
//  Lets the user pick their preferred regional dialect (es-MX,
//  fr-CA, en-AU, en-US-SW, en-US-SE, pt-BR…). Saves to both local
//  UserDefaults (offline-first) and server-side
//  `freight_ai_profiles.preferred_voice_dialect` (cross-device parity).
//
//  Hosted from `211_ShipperSettings`, `319_EsangSettings`, and the
//  driver Settings hub. Same component on every surface — single
//  truth, no per-role drift.
//
//  Drop into: EusoTrip/Views/Settings/VoiceDialectPicker.swift
//

import SwiftUI

public struct VoiceDialectPicker: View {
    @ObservedObject private var pref = UserVoicePreference.shared
    @State private var savingDialect: VoiceDialect? = nil
    @State private var errorMessage: String? = nil
    @State private var previewingDialect: VoiceDialect? = nil

    public init() {}

    public var body: some View {
        List {
            Section {
                ForEach(VoiceDialect.allCases) { dialect in
                    Button {
                        Task { await pick(dialect) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: dialect.systemImage)
                                .frame(width: 24)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dialect.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(dialect.previewPhrase)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)

                            // Saving indicator on the row being saved.
                            if savingDialect == dialect {
                                ProgressView()
                                    .controlSize(.small)
                            } else if pref.current == dialect {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }

                            // Preview button — speaks the dialect's
                            // preview phrase using the on-device synth.
                            Button {
                                Task {
                                    previewingDialect = dialect
                                    await ESangTTSPlayer.shared.preview(dialect)
                                    previewingDialect = nil
                                }
                            } label: {
                                Image(systemName: previewingDialect == dialect
                                      ? "speaker.wave.2.fill"
                                      : "speaker.wave.2")
                                    .foregroundStyle(.tint)
                            }
                            .buttonStyle(.plain)
                            .disabled(previewingDialect != nil)
                            .accessibilityLabel("Preview \(dialect.displayName)")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(savingDialect != nil)
                }
            } header: {
                Text("ESang voice dialect")
            } footer: {
                Text("ESang speaks replies in the dialect you choose. Voice transcription also uses this language. Pick \"System default\" to follow your device language.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } header: {
                    Text("Couldn't save")
                }
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Reconcile with server's stored value when the picker opens.
            await pref.reconcileFromServer()
        }
    }

    @MainActor
    private func pick(_ dialect: VoiceDialect) async {
        guard pref.current != dialect else { return }
        savingDialect = dialect
        errorMessage = nil
        do {
            try await pref.set(dialect)
            // Audible confirmation — speak the preview in the new dialect.
            await ESangTTSPlayer.shared.preview(dialect)
        } catch {
            errorMessage = "Couldn't save dialect. \(error.eusoUserCopy)"
        }
        savingDialect = nil
    }
}

// MARK: - Previews

#Preview("Voice Dialect Picker · Dark") {
    NavigationStack {
        VoiceDialectPicker()
    }
    .preferredColorScheme(.dark)
}

#Preview("Voice Dialect Picker · Light") {
    NavigationStack {
        VoiceDialectPicker()
    }
    .preferredColorScheme(.light)
}

// MARK: - Shared role settings center

/// Common settings stay in one account-backed surface, while role-owned
/// extensions (Dispatch board, Catalyst alerts, rail/vessel operating units)
/// remain declared separately. The server returns the signed-in role contract;
/// the client refuses to show controls when that contract does not match the
/// authenticated session.
enum RoleSettingsCategoryID: String, CaseIterable {
    case notifications
    case operations
    case privacy
    case appearance
}

struct RoleSettingsCategoryDefinition: Identifiable, Equatable {
    let id: RoleSettingsCategoryID
    let title: String
    let summary: String
    let systemImage: String
}

enum RoleSettingsCatalog {
    /// Explicit on purpose: adding a role cannot silently inherit another
    /// industry's settings journey.
    static let auditedRoles: [EusoRole] = [
        .driver, .shipper, .catalyst, .broker, .dispatch, .escort,
        .terminal, .compliance, .safety, .admin, .superAdmin, .factoring,
        .railShipper, .railCatalyst, .railDispatch, .railEngineer,
        .railConductor, .railBroker, .vesselShipper, .vesselOperator,
        .portMaster, .shipCaptain, .vesselBroker, .customsBroker,
        .serviceProvider,
    ]

    /// These Me destinations already own a richer settings route or embedded
    /// preference section. Shell adds the shared access card only elsewhere.
    static let dedicatedMeDestinations: Set<String> = [
        "me", "320", "350", "Dpch713", "Rail556", "Vesl656",
        "/settings", "/factoring/settings",
    ]

    /// Me roots that already render `EditableProfileAvatar` in their native
    /// identity header. Every other exact Me destination receives the shared
    /// profile action from `Shell`.
    static let destinationsWithEditableAvatar: Set<String> = [
        "me", "320", "350", "404B", "Dpch713", "620", "703", "804",
        "903", "Rail556", "Vesl656",
    ]

    static func needsSharedAvatar(for contract: RoleDockContract) -> Bool {
        guard let me = contract.trailing.last,
              me.label.caseInsensitiveCompare("Me") == .orderedSame,
              me.destinationId == contract.activeDestinationId else { return false }
        return !destinationsWithEditableAvatar.contains(me.destinationId)
    }

    static func needsSharedEntry(for contract: RoleDockContract) -> Bool {
        guard let me = contract.trailing.last,
              me.label.caseInsensitiveCompare("Me") == .orderedSame,
              me.destinationId == contract.activeDestinationId else { return false }
        return !dedicatedMeDestinations.contains(me.destinationId)
    }

    static func categories(for role: EusoRole) -> [RoleSettingsCategoryDefinition] {
        [
            .init(
                id: .notifications,
                title: notificationTitle(for: role),
                summary: notificationSummary(for: role),
                systemImage: "bell.badge.fill"
            ),
            .init(
                id: .operations,
                title: operationsTitle(for: role),
                summary: operationsSummary(for: role),
                systemImage: role.modes.contains(.vessel) ? "water.waves" : (role.modes.contains(.rail) ? "train.side.front.car" : "slider.horizontal.3")
            ),
            .init(
                id: .privacy,
                title: "Privacy & Presence",
                summary: privacySummary(for: role),
                systemImage: "hand.raised.fill"
            ),
            .init(
                id: .appearance,
                title: "Appearance",
                summary: "Theme saved to your EusoTrip account",
                systemImage: "circle.lefthalf.filled"
            ),
        ]
    }

    static func roleExtensionIDs(for role: EusoRole) -> [String] {
        switch role {
        case .driver:
            return ["driver_pulse"]
        case .dispatch:
            return ["dispatch_board"]
        case .catalyst:
            return ["catalyst_alerts"]
        case .railShipper, .railCatalyst, .railDispatch, .railEngineer, .railConductor, .railBroker:
            return ["rail_units"]
        case .vesselShipper, .vesselOperator, .portMaster, .shipCaptain, .vesselBroker, .customsBroker:
            return ["vessel_units"]
        case .shipper, .broker, .escort, .terminal, .compliance,
             .safety, .admin, .superAdmin, .factoring, .serviceProvider:
            return []
        }
    }

    static func distanceUnits(for role: EusoRole) -> [(label: String, value: String)] {
        switch role {
        case .vesselShipper, .vesselOperator, .portMaster, .shipCaptain, .vesselBroker, .customsBroker:
            return [("Nautical miles", "nautical_miles"), ("Kilometers", "kilometers"), ("Miles", "miles")]
        case .railShipper, .railCatalyst, .railDispatch, .railEngineer, .railConductor, .railBroker:
            return [("Miles", "miles"), ("Kilometers", "kilometers")]
        case .driver, .shipper, .catalyst, .broker, .dispatch, .escort, .terminal, .compliance, .serviceProvider:
            return [("Miles", "miles"), ("Kilometers", "kilometers")]
        case .safety, .admin, .superAdmin, .factoring:
            return []
        }
    }

    static func sharesLocation(for role: EusoRole) -> Bool {
        switch role {
        case .driver, .catalyst, .dispatch, .escort, .terminal,
             .serviceProvider,
             .railCatalyst, .railDispatch, .railEngineer, .railConductor,
             .vesselOperator, .portMaster, .shipCaptain:
            return true
        case .shipper, .broker, .compliance, .safety, .admin, .superAdmin,
             .factoring, .railShipper, .railBroker, .vesselShipper,
             .vesselBroker, .customsBroker:
            return false
        }
    }

    private static func notificationTitle(for role: EusoRole) -> String {
        switch role {
        case .driver: return "Trip Alerts"
        case .shipper, .vesselShipper, .railShipper: return "Shipment Alerts"
        case .catalyst, .railCatalyst, .vesselOperator: return "Fleet Alerts"
        case .broker, .railBroker, .vesselBroker: return "Trade Alerts"
        case .dispatch, .railDispatch: return "Dispatch Alerts"
        case .escort: return "Assignment Alerts"
        case .terminal, .portMaster: return "Facility Alerts"
        case .compliance, .customsBroker: return "Compliance Alerts"
        case .safety: return "Safety Alerts"
        case .admin, .superAdmin: return "Platform Alerts"
        case .factoring: return "Funding Alerts"
        case .railEngineer, .railConductor: return "Crew Alerts"
        case .shipCaptain: return "Bridge Alerts"
        case .serviceProvider: return "Service Alerts"
        }
    }

    private static func notificationSummary(for role: EusoRole) -> String {
        switch role {
        case .driver: return "Assignments, HOS, pickup, delivery and emergency events"
        case .shipper, .vesselShipper, .railShipper: return "Bids, milestones, documents and delivery exceptions"
        case .catalyst, .railCatalyst, .vesselOperator: return "Awards, equipment, crew and operating exceptions"
        case .broker, .railBroker, .vesselBroker: return "Tenders, counterparties and commercial exceptions"
        case .dispatch, .railDispatch: return "Board deadlines, crews, HOS and service recovery"
        case .escort: return "Assignments, route changes and permit exceptions"
        case .terminal, .portMaster: return "Appointments, queues, berth or yard exceptions"
        case .compliance, .customsBroker: return "Filings, expirations, holds and audit events"
        case .safety: return "Incidents, inspections and corrective actions"
        case .admin, .superAdmin: return "Tenant, security and platform incidents"
        case .factoring: return "Invoice eligibility, funding and repayment events"
        case .railEngineer, .railConductor: return "Duty, consist and interchange events"
        case .shipCaptain: return "Voyage, weather, port and safety events"
        case .serviceProvider: return "Assignments, approvals, parts, evidence and work-order status"
        }
    }

    private static func operationsTitle(for role: EusoRole) -> String {
        switch role {
        case .driver, .catalyst, .broker, .dispatch, .escort, .terminal, .compliance, .safety, .admin, .superAdmin, .factoring, .shipper:
            return "App & ESANG"
        case .serviceProvider:
            return "Service Operations & ESANG"
        case .railShipper, .railCatalyst, .railDispatch, .railEngineer, .railConductor, .railBroker:
            return "Rail Units & ESANG"
        case .vesselShipper, .vesselOperator, .portMaster, .shipCaptain, .vesselBroker, .customsBroker:
            return "Marine Units & ESANG"
        }
    }

    private static func operationsSummary(for role: EusoRole) -> String {
        distanceUnits(for: role).isEmpty
            ? "ESANG voice behavior across your signed-in devices"
            : "Distance units and ESANG voice behavior across devices"
    }

    private static func privacySummary(for role: EusoRole) -> String {
        sharesLocation(for: role)
            ? "Location, online status and profile visibility"
            : "Online status and profile visibility"
    }
}

struct RoleSettingsResponse: Decodable {
    struct Display: Decodable {
        let theme: String
    }
    struct Privacy: Decodable {
        let shareLocation: Bool
        let showOnlineStatus: Bool
        let profileVisibility: String
    }
    struct OperationalPreferences: Decodable {
        struct Pulse: Decodable {
            let turnByTurn: Bool
            let voiceWakeWord: Bool
            let drivingAutoDetect: Bool
            let hapticsIntensity: String
            let complicationStyle: String
        }
        let distanceUnit: String
        let esangVoiceEnabled: Bool
        let pulse: Pulse
    }
    struct MobileContract: Decodable {
        struct StorageScopes: Decodable {
            let common: String
            let company: Bool
        }
        let version: Int
        let role: String
        let companyId: Int?
        let categories: [String]
        let extensions: [String]
        let storageScopes: StorageScopes
    }
    let display: Display
    let privacy: Privacy
    let operationalPreferences: OperationalPreferences
    let mobileContract: MobileContract
}

@MainActor
final class RoleSettingsStore: ObservableObject {
    @Published private(set) var settings: RoleSettingsResponse?
    @Published private(set) var notifications: UsersAPI.PreferenceMatrix?
    @Published private(set) var loading = false
    @Published private(set) var savingControl: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var savedMessage: String?

    let role: EusoRole

    init(role: EusoRole) {
        self.role = role
    }

    var allowedCategories: Set<RoleSettingsCategoryID> {
        Set((settings?.mobileContract.categories ?? []).compactMap(RoleSettingsCategoryID.init(rawValue:)))
    }

    func load() async {
        loading = true
        errorMessage = nil
        savedMessage = nil
        defer { loading = false }
        do {
            async let settingsRequest: RoleSettingsResponse = EusoTripAPI.shared.queryNoInput("settings.getSettings")
            async let notificationRequest = EusoTripAPI.shared.users.getNotificationPreferences()
            let (loadedSettings, loadedNotifications) = try await (settingsRequest, notificationRequest)
            try validate(loadedSettings)
            settings = loadedSettings
            notifications = loadedNotifications
        } catch {
            settings = nil
            notifications = nil
            errorMessage = "Settings couldn't load. \(error.eusoUserCopy)"
        }
    }

    func setNotification(_ key: String, enabled: Bool) async {
        guard notifications != nil else { return }
        await save(control: "notifications.\(key)") {
            let acknowledgement = try await EusoTripAPI.shared.users.updateNotificationPreferences(
                self.notificationPatch(key: key, enabled: enabled)
            )
            guard acknowledgement.success else { throw RoleSettingsFailure.rejected }
            let canonical = try await EusoTripAPI.shared.users.getNotificationPreferences()
            guard self.notificationValue(key, in: canonical) == enabled else {
                throw RoleSettingsFailure.readbackMismatch
            }
            self.notifications = canonical
        }
    }

    func setTheme(_ theme: String) async {
        struct Input: Encodable { let theme: String }
        await save(control: "display.theme") {
            let acknowledgement: SettingsMutationAck = try await EusoTripAPI.shared.mutation(
                "settings.updateDisplaySettings", input: Input(theme: theme)
            )
            guard acknowledgement.success else { throw RoleSettingsFailure.rejected }
            let canonical = try await self.reloadSettings()
            guard canonical.display.theme == theme else { throw RoleSettingsFailure.readbackMismatch }
            UserDefaults.standard.set(theme, forKey: "com.eusorone.EusoTrip.appearance")
        }
    }

    func setDistanceUnit(_ unit: String) async {
        struct Input: Encodable { let distanceUnit: String }
        await save(control: "operations.distanceUnit") {
            let acknowledgement: SettingsMutationAck = try await EusoTripAPI.shared.mutation(
                "settings.updateOperationalPreferences", input: Input(distanceUnit: unit)
            )
            guard acknowledgement.success else { throw RoleSettingsFailure.rejected }
            let canonical = try await self.reloadSettings()
            guard canonical.operationalPreferences.distanceUnit == unit else {
                throw RoleSettingsFailure.readbackMismatch
            }
        }
    }

    func setESANGVoice(_ enabled: Bool) async {
        struct Input: Encodable { let esangVoiceEnabled: Bool }
        await save(control: "operations.esangVoiceEnabled") {
            let acknowledgement: SettingsMutationAck = try await EusoTripAPI.shared.mutation(
                "settings.updateOperationalPreferences", input: Input(esangVoiceEnabled: enabled)
            )
            guard acknowledgement.success else { throw RoleSettingsFailure.rejected }
            let canonical = try await self.reloadSettings()
            guard canonical.operationalPreferences.esangVoiceEnabled == enabled else {
                throw RoleSettingsFailure.readbackMismatch
            }
        }
    }

    func setPulseTurnByTurn(_ enabled: Bool) async {
        await setPulse(
            control: "operations.pulse.turnByTurn",
            patch: .init(turnByTurn: enabled),
            verify: { $0.turnByTurn == enabled }
        )
    }

    func setPulseVoiceWakeWord(_ enabled: Bool) async {
        await setPulse(
            control: "operations.pulse.voiceWakeWord",
            patch: .init(voiceWakeWord: enabled),
            verify: { $0.voiceWakeWord == enabled }
        )
    }

    func setPulseDrivingAutoDetect(_ enabled: Bool) async {
        await setPulse(
            control: "operations.pulse.drivingAutoDetect",
            patch: .init(drivingAutoDetect: enabled),
            verify: { $0.drivingAutoDetect == enabled }
        )
    }

    func setPulseHapticsIntensity(_ value: String) async {
        await setPulse(
            control: "operations.pulse.hapticsIntensity",
            patch: .init(hapticsIntensity: value),
            verify: { $0.hapticsIntensity == value }
        )
    }

    func setPulseComplicationStyle(_ value: String) async {
        await setPulse(
            control: "operations.pulse.complicationStyle",
            patch: .init(complicationStyle: value),
            verify: { $0.complicationStyle == value }
        )
    }

    func setShareLocation(_ enabled: Bool) async {
        struct Input: Encodable { let shareLocation: Bool }
        await savePrivacy(control: "privacy.shareLocation", input: Input(shareLocation: enabled)) {
            $0.shareLocation == enabled
        }
    }

    func setOnlineStatus(_ enabled: Bool) async {
        struct Input: Encodable { let showOnlineStatus: Bool }
        await savePrivacy(control: "privacy.showOnlineStatus", input: Input(showOnlineStatus: enabled)) {
            $0.showOnlineStatus == enabled
        }
    }

    func setProfileVisibility(_ value: String) async {
        struct Input: Encodable { let profileVisibility: String }
        await savePrivacy(control: "privacy.profileVisibility", input: Input(profileVisibility: value)) {
            $0.profileVisibility == value
        }
    }

    private func savePrivacy<Input: Encodable>(
        control: String,
        input: Input,
        verify: @escaping (RoleSettingsResponse.Privacy) -> Bool
    ) async {
        await save(control: control) {
            let acknowledgement: SettingsMutationAck = try await EusoTripAPI.shared.mutation(
                "settings.updatePrivacySettings", input: input
            )
            guard acknowledgement.success else { throw RoleSettingsFailure.rejected }
            let canonical = try await self.reloadSettings()
            guard verify(canonical.privacy) else { throw RoleSettingsFailure.readbackMismatch }
        }
    }

    private func setPulse(
        control: String,
        patch: PulseSettingsPatch.Pulse,
        verify: @escaping (RoleSettingsResponse.OperationalPreferences.Pulse) -> Bool
    ) async {
        await save(control: control) {
            let acknowledgement: SettingsMutationAck = try await EusoTripAPI.shared.mutation(
                "settings.updateOperationalPreferences",
                input: PulseSettingsPatch(pulse: patch)
            )
            guard acknowledgement.success else { throw RoleSettingsFailure.rejected }
            let canonical = try await self.reloadSettings()
            guard verify(canonical.operationalPreferences.pulse) else {
                throw RoleSettingsFailure.readbackMismatch
            }
            self.publishPulse(canonical.operationalPreferences.pulse)
        }
    }

    private func publishPulse(_ pulse: RoleSettingsResponse.OperationalPreferences.Pulse) {
        WatchAuthBridge.shared.pushSettings([
            "turnByTurn": pulse.turnByTurn,
            "voiceWakeWord": pulse.voiceWakeWord,
            "drivingAutoDetect": pulse.drivingAutoDetect,
            "hapticsIntensity": pulse.hapticsIntensity,
            "complicationStyle": pulse.complicationStyle,
        ])
    }

    private func save(control: String, operation: @escaping @MainActor () async throws -> Void) async {
        guard savingControl == nil else { return }
        savingControl = control
        errorMessage = nil
        savedMessage = nil
        defer { savingControl = nil }
        do {
            try await operation()
            savedMessage = "Saved to your account"
        } catch {
            errorMessage = "That setting wasn't saved. \(error.eusoUserCopy)"
        }
    }

    private func reloadSettings() async throws -> RoleSettingsResponse {
        let canonical: RoleSettingsResponse = try await EusoTripAPI.shared.queryNoInput("settings.getSettings")
        try validate(canonical)
        settings = canonical
        return canonical
    }

    private func validate(_ response: RoleSettingsResponse) throws {
        guard response.mobileContract.version == 1,
              response.mobileContract.role == role.rawValue,
              response.mobileContract.storageScopes.common == "user",
              response.mobileContract.storageScopes.company == false,
              Set(response.mobileContract.categories) == Set(RoleSettingsCategoryID.allCases.map(\.rawValue)),
              Set(response.mobileContract.extensions) == Set(RoleSettingsCatalog.roleExtensionIDs(for: role)) else {
            throw RoleSettingsFailure.contractMismatch
        }
    }

    private func notificationPatch(key: String, enabled: Bool) -> UsersAPI.Patch {
        var patch = UsersAPI.Patch(
            emailNotifications: nil, pushNotifications: nil, smsNotifications: nil,
            inAppNotifications: nil, loadUpdates: nil, bidAlerts: nil,
            paymentAlerts: nil, messageAlerts: nil, missionAlerts: nil,
            promotionalAlerts: nil, weeklyDigest: nil
        )
        switch key {
        case "emailNotifications": patch.emailNotifications = enabled
        case "pushNotifications": patch.pushNotifications = enabled
        case "smsNotifications": patch.smsNotifications = enabled
        case "inAppNotifications": patch.inAppNotifications = enabled
        default: break
        }
        return patch
    }

    private func notificationValue(_ key: String, in matrix: UsersAPI.PreferenceMatrix) -> Bool? {
        switch key {
        case "emailNotifications": return matrix.emailNotifications
        case "pushNotifications": return matrix.pushNotifications
        case "smsNotifications": return matrix.smsNotifications
        case "inAppNotifications": return matrix.inAppNotifications
        default: return nil
        }
    }
}

private struct SettingsMutationAck: Decodable {
    let success: Bool
}

private struct PulseSettingsPatch: Encodable {
    struct Pulse: Encodable {
        var turnByTurn: Bool?
        var voiceWakeWord: Bool?
        var drivingAutoDetect: Bool?
        var hapticsIntensity: String?
        var complicationStyle: String?

        init(
            turnByTurn: Bool? = nil,
            voiceWakeWord: Bool? = nil,
            drivingAutoDetect: Bool? = nil,
            hapticsIntensity: String? = nil,
            complicationStyle: String? = nil
        ) {
            self.turnByTurn = turnByTurn
            self.voiceWakeWord = voiceWakeWord
            self.drivingAutoDetect = drivingAutoDetect
            self.hapticsIntensity = hapticsIntensity
            self.complicationStyle = complicationStyle
        }
    }

    let pulse: Pulse
}

private enum RoleSettingsFailure: LocalizedError {
    case rejected
    case readbackMismatch
    case contractMismatch

    var errorDescription: String? {
        switch self {
        case .rejected: return "The server rejected the update."
        case .readbackMismatch: return "The saved value could not be verified."
        case .contractMismatch: return "This settings contract does not match your signed-in role."
        }
    }
}

/// One disclosure primitive for role Me hubs and settings surfaces. The owner
/// supplies the persisted expanded identifier; this view owns only presentation
/// and the single-open-section interaction contract.
struct RoleDisclosureSection<Content: View>: View {
    let id: String
    let systemImage: String
    let title: String
    let summary: String
    let badgeText: String?
    let anchorID: String
    let isBusy: Bool
    let onToggle: ((Bool) -> Void)?

    @Binding private var expandedID: String
    @Environment(\.palette) private var palette
    private let content: Content

    init(
        id: String,
        systemImage: String,
        title: String,
        summary: String,
        badgeText: String? = nil,
        anchorID: String? = nil,
        isBusy: Bool = false,
        expandedID: Binding<String>,
        onToggle: ((Bool) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.systemImage = systemImage
        self.title = title
        self.summary = summary
        self.badgeText = badgeText
        self.anchorID = anchorID ?? "role-disclosure-\(id)"
        self.isBusy = isBusy
        self._expandedID = expandedID
        self.onToggle = onToggle
        self.content = content()
    }

    private var isExpanded: Bool { expandedID == id }

    var body: some View {
        LifecycleCard {
            Button {
                let willOpen = !isExpanded
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedID = willOpen ? id : ""
                }
                onToggle?(willOpen)
            } label: {
                HStack(spacing: Space.s3) {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: systemImage)
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text(summary)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else if let badgeText {
                        Text(badgeText)
                            .font(EType.micro.weight(.heavy))
                            .foregroundStyle(palette.textTertiary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(palette.bgCardSoft))
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                Divider()
                    .overlay(palette.borderFaint)
                    .padding(.vertical, 6)
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .id(anchorID)
    }
}

struct RoleSettingsAccessCard: View {
    @EnvironmentObject private var session: EusoTripSession
    @Environment(\.palette) private var palette
    @State private var presented = false

    var body: some View {
        Button {
            presented = true
        } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 38, height: 38)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Alerts, units, privacy, ESANG and appearance")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(session.user?.roleEnum == nil)
        .sheet(isPresented: $presented) {
            if let role = session.user?.roleEnum {
                NavigationStack {
                    RoleSettingsCenter(role: role)
                        .environment(\.palette, palette)
                        .environmentObject(session)
                }
            }
        }
    }
}

struct RoleSettingsCenter: View {
    let role: EusoRole

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @StateObject private var store: RoleSettingsStore
    @SceneStorage("euso.role.settings.expandedCategory") private var expandedCategory = ""
    @SceneStorage("euso.role.settings.returnAnchor") private var returnAnchor = ""
    @SceneStorage("euso.role.settings.ownerRole") private var storageOwnerRole = ""

    init(role: EusoRole) {
        self.role = role
        _store = StateObject(wrappedValue: RoleSettingsStore(role: role))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("SETTINGS · \(role.displayName.uppercased())")
                            .font(EType.micro)
                            .foregroundStyle(palette.textTertiary)
                        Text("Your preferences")
                            .font(EType.h2)
                            .foregroundStyle(palette.textPrimary)
                        Text("Open a category to change settings saved to your signed-in account.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }

                    if store.loading {
                        HStack(spacing: Space.s2) {
                            ProgressView()
                            Text("Loading account settings…")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72)
                    } else if store.settings != nil, store.notifications != nil {
                        ForEach(visibleCategories) { category in
                            categoryCard(category)
                        }
                    }

                    if let error = store.errorMessage {
                        settingsMessage(error, color: Brand.danger, icon: "exclamationmark.triangle.fill")
                        Button("Retry") { Task { await store.load() } }
                            .font(EType.bodyStrong)
                    } else if let saved = store.savedMessage {
                        settingsMessage(saved, color: Brand.success, icon: "checkmark.circle.fill")
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s5)
            }
            .onAppear {
                synchronizeStoredRole()
                restorePosition(using: proxy)
            }
            .onChange(of: store.loading) { _, isLoading in
                if !isLoading { restorePosition(using: proxy) }
            }
        }
        .background(palette.bgPrimary.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task { await store.load() }
        .eusoRefreshable { await store.load() }
        .eusoRefreshSurface("role-settings:\(role.rawValue)")
    }

    private var visibleCategories: [RoleSettingsCategoryDefinition] {
        RoleSettingsCatalog.categories(for: role).filter { store.allowedCategories.contains($0.id) }
    }

    private func categoryCard(_ category: RoleSettingsCategoryDefinition) -> some View {
        let anchor = "settings-category-\(category.id.rawValue)"
        return RoleDisclosureSection(
            id: category.id.rawValue,
            systemImage: category.systemImage,
            title: category.title,
            summary: category.summary,
            anchorID: anchor,
            isBusy: store.savingControl != nil,
            expandedID: $expandedCategory,
            onToggle: { isOpen in returnAnchor = isOpen ? anchor : "" }
        ) {
            categoryControls(category.id)
        }
    }

    private func synchronizeStoredRole() {
        guard storageOwnerRole != role.rawValue else { return }
        storageOwnerRole = role.rawValue
        expandedCategory = ""
        returnAnchor = ""
    }

    private func restorePosition(using proxy: ScrollViewProxy) {
        guard storageOwnerRole == role.rawValue,
              !expandedCategory.isEmpty,
              visibleCategories.contains(where: { $0.id.rawValue == expandedCategory }) else { return }
        let fallback = "settings-category-\(expandedCategory)"
        eusoRestoreScrollPosition(
            using: proxy,
            anchor: returnAnchor.isEmpty ? fallback : returnAnchor,
            fallback: fallback
        )
    }

    @ViewBuilder
    private func categoryControls(_ category: RoleSettingsCategoryID) -> some View {
        switch category {
        case .notifications:
            if let matrix = store.notifications {
                VStack(spacing: Space.s3) {
                    settingToggle("Push", detail: "Realtime alerts on this device", key: "notifications.pushNotifications", value: matrix.pushNotifications) {
                        await store.setNotification("pushNotifications", enabled: $0)
                    }
                    settingToggle("Email", detail: "Operational summaries and documents", key: "notifications.emailNotifications", value: matrix.emailNotifications) {
                        await store.setNotification("emailNotifications", enabled: $0)
                    }
                    settingToggle("SMS", detail: "Urgent events when enabled", key: "notifications.smsNotifications", value: matrix.smsNotifications) {
                        await store.setNotification("smsNotifications", enabled: $0)
                    }
                    settingToggle("In-app", detail: "Banners while EusoTrip is open", key: "notifications.inAppNotifications", value: matrix.inAppNotifications) {
                        await store.setNotification("inAppNotifications", enabled: $0)
                    }
                }
            }

        case .operations:
            if let settings = store.settings {
                VStack(alignment: .leading, spacing: Space.s3) {
                    let units = RoleSettingsCatalog.distanceUnits(for: role)
                    if !units.isEmpty {
                        settingPicker(
                            "Distance units",
                            key: "operations.distanceUnit",
                            selection: settings.operationalPreferences.distanceUnit,
                            options: units
                        ) { await store.setDistanceUnit($0) }
                    }
                    settingToggle(
                        "ESANG voice",
                        detail: "Allow spoken ESANG responses",
                        key: "operations.esangVoiceEnabled",
                        value: settings.operationalPreferences.esangVoiceEnabled
                    ) { await store.setESANGVoice($0) }
                    if role == .driver {
                        Divider().overlay(palette.borderFaint)
                        Text("EUSOTRIP PULSE")
                            .font(EType.micro)
                            .foregroundStyle(palette.textTertiary)
                        settingToggle(
                            "Turn-by-turn on wrist",
                            detail: "Show active-load directions on Apple Watch",
                            key: "operations.pulse.turnByTurn",
                            value: settings.operationalPreferences.pulse.turnByTurn
                        ) { await store.setPulseTurnByTurn($0) }
                        settingToggle(
                            "Voice wake",
                            detail: "Listen for Hey ESANG on Apple Watch",
                            key: "operations.pulse.voiceWakeWord",
                            value: settings.operationalPreferences.pulse.voiceWakeWord
                        ) { await store.setPulseVoiceWakeWord($0) }
                        settingToggle(
                            "Auto-detect driving",
                            detail: "Start trip mode when vehicle movement begins",
                            key: "operations.pulse.drivingAutoDetect",
                            value: settings.operationalPreferences.pulse.drivingAutoDetect
                        ) { await store.setPulseDrivingAutoDetect($0) }
                        settingPicker(
                            "Wrist haptics",
                            key: "operations.pulse.hapticsIntensity",
                            selection: settings.operationalPreferences.pulse.hapticsIntensity,
                            options: [("Light", "light"), ("Standard", "standard"), ("Strong", "strong")]
                        ) { await store.setPulseHapticsIntensity($0) }
                        settingPicker(
                            "Complication",
                            key: "operations.pulse.complicationStyle",
                            selection: settings.operationalPreferences.pulse.complicationStyle,
                            options: [("ESANG orb", "orb"), ("HOS clock", "numeric"), ("Duty status", "hos")]
                        ) { await store.setPulseComplicationStyle($0) }
                    }
                }
            }

        case .privacy:
            if let settings = store.settings {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if RoleSettingsCatalog.sharesLocation(for: role) {
                        settingToggle(
                            "Share live location",
                            detail: "Visible only to authorized workflow participants",
                            key: "privacy.shareLocation",
                            value: settings.privacy.shareLocation
                        ) { await store.setShareLocation($0) }
                    }
                    settingToggle(
                        "Show online status",
                        detail: "Let authorized coworkers see availability",
                        key: "privacy.showOnlineStatus",
                        value: settings.privacy.showOnlineStatus
                    ) { await store.setOnlineStatus($0) }
                    settingPicker(
                        "Profile visibility",
                        key: "privacy.profileVisibility",
                        selection: settings.privacy.profileVisibility,
                        options: [("Company", "company"), ("Private", "private"), ("Public", "public")]
                    ) { await store.setProfileVisibility($0) }
                }
            }

        case .appearance:
            if let settings = store.settings {
                settingPicker(
                    "Theme",
                    key: "display.theme",
                    selection: settings.display.theme,
                    options: [("System", "system"), ("Light", "light"), ("Dark", "dark")]
                ) { await store.setTheme($0) }
            }
        }
    }

    private func settingToggle(
        _ title: String,
        detail: String,
        key: String,
        value: Bool,
        save: @escaping (Bool) async -> Void
    ) -> some View {
        Toggle(isOn: Binding(
            get: { value },
            set: { newValue in Task { await save(newValue) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(detail).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
        .tint(Brand.info)
        .disabled(store.savingControl != nil)
        .overlay(alignment: .trailing) {
            if store.savingControl == key { ProgressView().controlSize(.small).padding(.trailing, 52) }
        }
    }

    private func settingPicker(
        _ title: String,
        key: String,
        selection: String,
        options: [(label: String, value: String)],
        save: @escaping (String) async -> Void
    ) -> some View {
        HStack(spacing: Space.s3) {
            Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            if store.savingControl == key {
                ProgressView().controlSize(.small)
            }
            Picker(title, selection: Binding(
                get: { selection },
                set: { newValue in Task { await save(newValue) } }
            )) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(store.savingControl != nil)
        }
    }

    private func settingsMessage(_ text: String, color: Color, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(EType.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s3)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}
