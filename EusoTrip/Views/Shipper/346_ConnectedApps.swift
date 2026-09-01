//
//  346_ConnectedApps.swift
//  EusoTrip — Shipper · Connected apps + API tokens (Arc K).
//
//  Wired to the platform's REAL role-based integration framework
//  (founder build-706 feedback: "We have a whole api connection system
//  integration in our web platform... wire this to that system. Let the
//  user based on role type connect to the api integration that applies to
//  that role type or vertical."):
//
//    • CONNECTED APPS  → `userIntegrations.listCatalog` (role + primaryMode
//      scoped provider catalog) + `userIntegrations.listConnections` (the
//      signed-in user's connection state inside the active company). Connect /
//      disconnect / sync run in-app with server-authoritative ownership
//      via `userIntegrations.connect` / `.disconnect` / `.sync`. Provider rows
//      always come from the live server catalog. The local registry is an
//      offline parity artifact only and never supplies fallback provider rows.
//
//    • API TOKENS      → `devPortal.apiKeys.list` / `.create` / `.revoke`,
//      with scopes from `devPortal.mcpTools.getScopes`. Tokens are issued
//      IN-APP (the raw key is shown exactly once, copy-to-clipboard), not
//      "create them on the web shipper page."
//
//    • INTEGRATION UNLOCKS → the live `profileAdaptation` envelope folded into
//      `auth.me` (RIOS Axis O) — the same data the web's
//      useIntegrationProfileAdaptation hook consumes.
//
//  The server decides role/mode/vertical eligibility for every authenticated
//  role; iOS does not widen or reconstruct that catalog locally.
//
//  Powered by ESANG AI™.
//

import AuthenticationServices
import CoreFoundation
import Foundation
import SwiftUI
import UIKit

private enum IntegrationOAuthSessionError: LocalizedError {
    case authorizationCanceled
    case sessionCouldNotStart
    case invalidCallback
    case providerMismatch
    case providerRejected(String)

    var errorDescription: String? {
        switch self {
        case .authorizationCanceled:
            return "Provider authorization was canceled. No connection was changed."
        case .sessionCouldNotStart:
            return "The secure provider authorization session could not start."
        case .invalidCallback:
            return "The provider returned an invalid authorization confirmation."
        case .providerMismatch:
            return "The authorization confirmation did not match the selected provider."
        case .providerRejected(let reason):
            let label = reason.replacingOccurrences(of: "_", with: " ")
            return "Provider authorization was not completed: \(label)."
        }
    }
}

private enum IntegrationActivationInputError: LocalizedError {
    case invalid(field: String, requirement: String)

    var errorDescription: String? {
        switch self {
        case .invalid(let field, let requirement):
            return "\(field) \(requirement)."
        }
    }
}

/// JSON values sent to `userIntegrations.connect`. The server publishes each
/// field type, so iOS must not flatten numbers, lists, or JSON into strings.
private enum IntegrationActivationValue: Encodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([IntegrationActivationValue])
    case object([String: IntegrationActivationValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private final class IntegrationOAuthSessionCoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    private var webSession: ASWebAuthenticationSession?

    func start(
        authorizationURL: URL,
        providerId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let session = ASWebAuthenticationSession(
            url: authorizationURL,
            callbackURLScheme: "eusotrip"
        ) { [weak self] callbackURL, error in
            DispatchQueue.main.async {
                self?.webSession = nil
                if let webError = error as? ASWebAuthenticationSessionError,
                   webError.code == .canceledLogin {
                    completion(.failure(IntegrationOAuthSessionError.authorizationCanceled))
                    return
                }
                if let error {
                    completion(.failure(error))
                    return
                }
                completion(Self.validateCallback(callbackURL, providerId: providerId))
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webSession = session
        if !session.start() {
            webSession = nil
            completion(.failure(IntegrationOAuthSessionError.sessionCouldNotStart))
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
        }
        if let window = scenes.first?.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }

    private static func validateCallback(_ url: URL?, providerId: String) -> Result<Void, Error> {
        guard let url,
              url.scheme?.lowercased() == "eusotrip",
              url.host?.lowercased() == "integrations",
              url.path == "/oauth",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let status = exactlyOneQueryValue("status", in: components),
              let callbackProvider = exactlyOneQueryValue("provider", in: components) else {
            return .failure(IntegrationOAuthSessionError.invalidCallback)
        }
        guard callbackProvider == providerId else {
            return .failure(IntegrationOAuthSessionError.providerMismatch)
        }
        if status == "connected" {
            return .success(())
        }
        let reason = exactlyOneQueryValue("reason", in: components) ?? "provider_denied"
        return .failure(IntegrationOAuthSessionError.providerRejected(reason))
    }

    private static func exactlyOneQueryValue(_ name: String, in components: URLComponents) -> String? {
        let values = (components.queryItems ?? [])
            .filter { $0.name == name }
            .compactMap(\.value)
        guard values.count == 1, !values[0].isEmpty else { return nil }
        return values[0]
    }
}

struct ConnectedAppsScreen: View {
    let theme: Theme.Palette
    let initialProviderId: String?
    let showsLifecycleNav: Bool

    init(
        theme: Theme.Palette,
        initialProviderId: String? = nil,
        showsLifecycleNav: Bool = true
    ) {
        self.theme = theme
        self.initialProviderId = initialProviderId
        self.showsLifecycleNav = showsLifecycleNav
    }

    var body: some View {
        Shell(theme: theme) {
            ConnectedAppsBody(initialProviderId: initialProviderId)
        } nav: {
            if showsLifecycleNav {
                shipperLifecycleNav()
            }
        }
    }
}

// MARK: - Wire DTOs (canonical RIOS server response shapes)

private struct IntegrationInputField: Decodable, Hashable {
    let key: String
    let label: String
    let inputType: String
    let required: Bool
    let secret: Bool
}

private struct IntegrationInputAlternative: Decodable, Hashable {
    let credentials: [String]
    let configuration: [String]?
}

private struct IntegrationInputRequirement: Decodable, Hashable {
    let mode: String
    let alternatives: [IntegrationInputAlternative]
}

private struct IntegrationProvisioningRequirement: Decodable, Hashable {
    let key: String
    let label: String
    let owner: String
    let verification: String
    let docsUrl: String?
}

private struct IntegrationProvisioning: Decodable, Hashable {
    let mode: String
    let activation: String
    let requirements: [IntegrationProvisioningRequirement]
}

private struct IntegrationActivationStep: Decodable, Hashable {
    let key: String
    let label: String
    let owner: String
    let verification: String
    let state: String
    let docsUrl: String?
    let detail: String?
    let verifiedAt: String?
    let expiresAt: String?
}

private struct IntegrationActivationSummary: Decodable, Hashable {
    let attemptId: String
    let state: String
    let ready: Bool
    let steps: [IntegrationActivationStep]
}

/// `userIntegrations.listCatalog` row — role/mode-scoped provider.
private struct IntegrationProvider: Decodable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let vendor: String?
    let category: String?
    let description: String?
    let docsUrl: String?
    let authType: String?
    let status: String?
    let capabilities: ProviderCapabilityFlags
    let applicableModes: [String]
    let requiresCredentials: Bool?
    let credentialFields: [IntegrationInputField]
    let configurationFields: [IntegrationInputField]
    let inputRequirement: IntegrationInputRequirement?
    let connectionVerification: String?
    let activationVerification: String?
    let provisioning: IntegrationProvisioning?
    let ownershipScope: String?
    let canEstablishConnection: Bool
    let establishmentBlockedReason: String?
    let connectable: Bool
    let blockedReason: String?
    let catalogAliases: [String]
    let researchStatus: String?
    let researchVerifiedAt: String?
    let supportsSync: Bool?
    let syncIntervalMinutes: Int?
    let journey: IntegrationProviderJourney?

    enum CodingKeys: String, CodingKey {
        case id, displayName, vendor, category, description, docsUrl, authType, status
        case capabilities, applicableModes, requiresCredentials, credentialFields, configurationFields
        case inputRequirement, connectionVerification, activationVerification, provisioning
        case ownershipScope, canEstablishConnection, establishmentBlockedReason
        case connectable, blockedReason, catalogAliases
        case researchStatus, researchVerifiedAt, supportsSync, syncIntervalMinutes, journey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        vendor = try c.decodeIfPresent(String.self, forKey: .vendor)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        docsUrl = try c.decodeIfPresent(String.self, forKey: .docsUrl)
        authType = try c.decodeIfPresent(String.self, forKey: .authType)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        capabilities = try c.decode(ProviderCapabilityFlags.self, forKey: .capabilities)
        applicableModes = try c.decodeIfPresent([String].self, forKey: .applicableModes) ?? []
        requiresCredentials = try c.decodeIfPresent(Bool.self, forKey: .requiresCredentials)
        credentialFields = try c.decodeIfPresent([IntegrationInputField].self, forKey: .credentialFields) ?? []
        configurationFields = try c.decodeIfPresent([IntegrationInputField].self, forKey: .configurationFields) ?? []
        inputRequirement = try c.decodeIfPresent(IntegrationInputRequirement.self, forKey: .inputRequirement)
        connectionVerification = try c.decodeIfPresent(String.self, forKey: .connectionVerification)
        activationVerification = try c.decodeIfPresent(String.self, forKey: .activationVerification)
        provisioning = try c.decodeIfPresent(IntegrationProvisioning.self, forKey: .provisioning)
        ownershipScope = try c.decodeIfPresent(String.self, forKey: .ownershipScope)
        canEstablishConnection = try c.decodeIfPresent(Bool.self, forKey: .canEstablishConnection) ?? false
        establishmentBlockedReason = try c.decodeIfPresent(String.self, forKey: .establishmentBlockedReason)
        connectable = try c.decodeIfPresent(Bool.self, forKey: .connectable) ?? false
        blockedReason = try c.decodeIfPresent(String.self, forKey: .blockedReason)
        catalogAliases = try c.decodeIfPresent([String].self, forKey: .catalogAliases) ?? []
        researchStatus = try c.decodeIfPresent(String.self, forKey: .researchStatus)
        researchVerifiedAt = try c.decodeIfPresent(String.self, forKey: .researchVerifiedAt)
        supportsSync = try c.decodeIfPresent(Bool.self, forKey: .supportsSync)
        syncIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .syncIntervalMinutes)
        journey = try c.decodeIfPresent(IntegrationProviderJourney.self, forKey: .journey)
    }
}

private struct ProviderCapabilityFlags: Decodable, Hashable {
    let inbound: Bool
    let outbound: Bool
    let webhooks: Bool
    let realtime: Bool
    let scheduledSync: Bool
    let perUserOAuth: Bool
}

/// RIOS journey profile returned by `userIntegrations.listCatalog`.
/// It is computed from the same backend registry that powers actual
/// connect/sync/webhook behavior, so the copy adapts to role, provider,
/// category, capabilities, and profile adaptation instead of static
/// marketing text.
private struct IntegrationProviderJourney: Decodable, Hashable {
    let persona: String?
    let adoptionStage: String?
    let headline: String?
    let setup: String?
    let operationalUnlock: String?
    let crossRoleBenefit: String?
    let credentialHint: String?
    let dataFlow: String?
    let capabilityTags: [String]?
}

/// `userIntegrations.listConnections` row. The server query is constrained by
/// both the signed-in user id and active company id; no credential material is
/// returned to this client.
private struct IntegrationConnection: Decodable, Identifiable, Hashable {
    let id: Int
    let providerId: String
    let status: String?
    let lastSyncedAt: String?
    let lastError: String?
    let lastErrorAt: String?
    let enabledAt: String?
    let disabledAt: String?
    let updatedAt: String?
    let feedState: String?
    let feedStateReason: String?
    let syncMode: String?
    let syncIntervalMinutes: Int?
    let nextEligibleAt: String?
    let staleAt: String?
    let lastSuccessfulSyncAt: String?
    let lastAttemptAt: String?
    let syncAgeSeconds: Int?
    let credentialState: String?
    let isUsable: Bool?
    let accessible: Bool?
    let ownershipScope: String?
    let sharedWithCompany: Bool?
    let connectedByMe: Bool?
    let canManage: Bool?
    let activation: IntegrationActivationSummary?

    var effectiveFeedState: String? {
        guard let feedState = feedState?.trimmingCharacters(in: .whitespacesAndNewlines),
              !feedState.isEmpty else { return nil }
        return feedState.lowercased()
    }

    var isOperational: Bool? {
        isUsable
    }

    var isPresent: Bool {
        if effectiveFeedState == "disabled" { return false }
        if status?.lowercased() == "disabled" { return false }
        return true
    }
}

/// `devPortal.apiKeys.list` row.
private struct ApiKeyRow: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let key: String          // already masked server-side: prefix…suffix
    let scopes: [String]?
    let status: String?
    let createdAt: String?
    let expiresAt: String?
    let lastUsed: String?
    let requestCount: Int?
}

/// `devPortal.mcpTools.getScopes` row.
private struct ApiScope: Decodable, Identifiable, Hashable {
    var id: String { scope }
    let scope: String
    let description: String
}

private struct IntegrationJourneyBenefit: Identifiable, Hashable {
    let id: String
    let adoptionStage: String?
    let setup: String
    let operationalUnlock: String
    let crossRoleBenefit: String
    let providerCount: Int
    let connectedCount: Int?
    let providerNames: [String]
}

private struct IntegrationJourneyGroupKey: Hashable {
    let adoptionStage: String?
    let setup: String
    let operationalUnlock: String
    let crossRoleBenefit: String
}

private enum IntegrationLoadFailureKind: Hashable {
    case unauthenticated
    case permissionDenied
    case unavailable
}

private struct IntegrationLoadFailure: Hashable {
    let kind: IntegrationLoadFailureKind
    let detail: String
}

private struct IntegrationDisconnectIntent: Identifiable {
    let connection: IntegrationConnection
    let providerName: String

    var id: Int { connection.id }
}

struct ConnectedAppsBody: View {
    let initialProviderId: String?
    let includedCategories: Set<String>?
    let surfaceTitle: String?
    let surfaceSummary: String?
    let showsJourney: Bool
    let showsAdaptation: Bool
    let showsTokens: Bool

    init(
        initialProviderId: String? = nil,
        includedCategories: Set<String>? = nil,
        surfaceTitle: String? = nil,
        surfaceSummary: String? = nil,
        showsJourney: Bool = true,
        showsAdaptation: Bool = true,
        showsTokens: Bool = true
    ) {
        self.initialProviderId = initialProviderId
        self.includedCategories = includedCategories
        self.surfaceTitle = surfaceTitle
        self.surfaceSummary = surfaceSummary
        self.showsJourney = showsJourney
        self.showsAdaptation = showsAdaptation
        self.showsTokens = showsTokens
    }

    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    // Catalog + connections (the role-based integration system).
    @State private var providers: [IntegrationProvider] = []
    @State private var connections: [IntegrationConnection] = []
    @State private var liveAdaptation: ProfileAdaptation? = nil
    @State private var catalogFailure: IntegrationLoadFailure? = nil
    @State private var connectionsFailure: IntegrationLoadFailure? = nil
    @State private var adaptationUnavailableReason: String? = nil

    // API tokens (the developer portal).
    @State private var apiKeys: [ApiKeyRow] = []
    @State private var scopes: [ApiScope] = []
    @State private var tokensUnavailableReason: String? = nil
    @State private var scopesUnavailableReason: String? = nil

    @State private var loading = true
    @State private var actionError: String? = nil
    @State private var actionNotice: String? = nil

    // Per-provider connect form state.
    @State private var expandedProvider: String? = nil
    @State private var credInputs: [String: String] = [:]   // "providerId.field" → value
    @State private var confirmedProvisioningRequirements: Set<String> = []
    @State private var busyProvider: String? = nil
    @State private var pendingDisconnect: IntegrationDisconnectIntent? = nil
    @StateObject private var oauthSession = IntegrationOAuthSessionCoordinator()

    // API-token issuance state.
    @State private var showIssueForm = false
    @State private var newKeyName = ""
    @State private var selectedScopes: Set<String> = []
    @State private var issuing = false
    @State private var freshlyIssuedKey: String? = nil      // shown once, then cleared
    @State private var revokingKey: String? = nil

    private var roleLabel: String { session.user?.roleEnum.displayName ?? "Account" }
    private var scopedProviders: [IntegrationProvider] {
        guard let includedCategories, !includedCategories.isEmpty else { return providers }
        let normalized = Set(includedCategories.map { $0.lowercased() })
        return providers.filter { provider in
            guard let category = provider.category?.lowercased() else { return false }
            return normalized.contains(category)
        }
    }
    private var scopedConnections: [IntegrationConnection] {
        guard let includedCategories, !includedCategories.isEmpty else { return connections }
        let providerIds = Set(scopedProviders.map(\.id))
        return connections.filter { providerIds.contains($0.providerId) }
    }
    private var unmatchedConnections: [IntegrationConnection] {
        guard catalogFailure == nil,
              includedCategories == nil || includedCategories?.isEmpty == true else {
            return []
        }
        let providerIds = Set(providers.map(\.id))
        return connections.filter { $0.isPresent && !providerIds.contains($0.providerId) }
    }
    private var displayedProviders: [IntegrationProvider] {
        guard let initialProviderId,
              let provider = scopedProviders.first(where: { $0.id == initialProviderId }) else {
            return scopedProviders
        }
        return [provider]
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header

                if let aerr = actionError {
                    LifecycleCard(accentDanger: true) {
                        Text(aerr).font(EType.caption).foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let notice = actionNotice {
                    LifecycleCard {
                        Text(notice).font(EType.caption).foregroundStyle(Brand.success)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if loading {
                    LifecycleCard { Text("Loading your integrations…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    if showsJourney { integrationJourneySection }
                    connectedSection
                    if showsAdaptation { adaptationSection }
                    if showsTokens { tokensSection }
                }

                Color.clear.frame(height: 156)
            }
            .padding(.horizontal, 14).padding(.top, 72)
        }
        .eusoRefreshTask { await load() }
        .confirmationDialog(
            pendingDisconnect.map { "Disconnect \(cleanLabel($0.providerName))?" } ?? "Disconnect provider?",
            isPresented: Binding(
                get: { pendingDisconnect != nil },
                set: { if !$0 { pendingDisconnect = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let intent = pendingDisconnect {
                Button("Disconnect \(cleanLabel(intent.providerName))", role: .destructive) {
                    pendingDisconnect = nil
                    Task { await disconnect(intent.connection, providerName: intent.providerName) }
                }
            }
            Button("Keep connected", role: .cancel) {
                pendingDisconnect = nil
            }
        } message: {
            Text(pendingDisconnect?.connection.sharedWithCompany == true
                 ? "This company connection will stop providing data to eligible coworkers. EusoTrip will request provider and credential revocation, but it remains active until the current connection record confirms the feed is disabled and authorization evidence is revoked."
                 : "This personal connection will stop providing data to you. EusoTrip will request provider and credential revocation, but it remains active until the current connection record confirms the feed is disabled and authorization evidence is revoked.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.connected.to.line.below").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("\(roleLabel.uppercased()) · CONNECTED APPS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(surfaceTitle ?? "Connected apps + API tokens").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(surfaceSummary ?? "Connect the integrations that apply to your role, and issue API tokens — all in-app.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Connected apps / role-based integration catalog

    @ViewBuilder
    private var integrationJourneySection: some View {
        if let failure = catalogFailure {
            LifecycleCard(accentDanger: true) {
                LifecycleSection(label: "RIOS ADOPTION MAP", icon: "point.3.connected.trianglepath.dotted")
                Text(integrationFailureSummary(failure, resource: "Journey benefits"))
                    .font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Text(failure.detail)
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    .lineLimit(2)
            }
        } else {
            let benefits = liveJourneyBenefits(
                providers: scopedProviders,
                connections: connectionsFailure == nil ? scopedConnections : nil
            )
            LifecycleCard {
                LifecycleSection(label: "RIOS ADOPTION MAP", icon: "point.3.connected.trianglepath.dotted")

                Label("Live role catalog · \(scopedProviders.count) providers", systemImage: "checkmark.seal")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)

                if let failure = connectionsFailure {
                    Text("Connection progress is unavailable, so benefit counts are not inferred.")
                        .font(EType.caption).foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(failure.detail)
                        .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }

                if benefits.isEmpty {
                    Text(scopedProviders.isEmpty
                         ? "No providers are mapped to this role in the live catalog."
                         : "The live catalog does not currently publish journey benefits for these providers.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(benefits) { benefit in
                        journeyBenefitRow(benefit)
                    }
                }
            }
        }
    }

    private func journeyBenefitRow(_ benefit: IntegrationJourneyBenefit) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(benefit.adoptionStage.map { prettyToken($0) } ?? "Connected workflow")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                Text(benefit.connectedCount.map { "\($0)/\(benefit.providerCount) connected" } ?? "State unavailable")
                    .font(EType.mono(.micro))
                    .foregroundStyle(benefit.connectedCount.map { $0 > 0 } == true ? Brand.success : palette.textTertiary)
            }
            journeyStatement(label: "SETUP", value: benefit.setup)
            journeyStatement(label: "UNLOCK", value: benefit.operationalUnlock)
            journeyStatement(label: "SHARED", value: benefit.crossRoleBenefit)
            providerNameLine(benefit.providerNames, total: benefit.providerCount)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.borderFaint).frame(height: 1)
        }
    }

    private func journeyStatement(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(label)
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 44, alignment: .leading)
            Text(cleanLabel(value))
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func providerNameLine(_ names: [String], total: Int) -> some View {
        let visible = names.prefix(3).map(cleanLabel)
        let suffix = total > visible.count ? " +\(total - visible.count) more" : ""
        return Text(visible.joined(separator: " · ") + suffix)
            .font(EType.mono(.micro))
            .foregroundStyle(palette.textTertiary)
            .lineLimit(2)
    }

    @ViewBuilder
    private var connectedSection: some View {
        LifecycleCard {
            LifecycleSection(label: "CONNECTED APPS", icon: "rectangle.connected.to.line.below")

            if let failure = connectionsFailure {
                Text(integrationFailureSummary(failure, resource: "Connection state"))
                    .font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Text(failure.detail)
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    .lineLimit(2)
                pillButton(title: "Retry connection state", filled: false, busy: false) {
                    Task { _ = await refreshConnections() }
                }
            } else if catalogFailure != nil,
                      let includedCategories,
                      !includedCategories.isEmpty {
                Text("Connection state loaded, but category-scoped rows cannot be attributed while the live catalog is unavailable.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let connectedCount = scopedConnections.filter { $0.isOperational == true }.count
                let unknownCount = scopedConnections.filter { $0.isOperational == nil }.count
                let presentCount = scopedConnections.filter(\.isPresent).count
                Text(connectedCount == 0
                     ? (presentCount == 0
                        ? "No connections were returned for this signed-in account and active company."
                        : unknownCount > 0
                            ? "\(unknownCount) connection\(unknownCount == 1 ? "" : "s") have no authoritative feed truth; usable state is unknown."
                            : "\(presentCount) connection\(presentCount == 1 ? "" : "s") need attention; none currently provide usable data.")
                     : "\(connectedCount) usable · \(unknownCount) unknown · \(presentCount) present · \(scopedProviders.count) available for your role")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let failure = catalogFailure {
                Text(integrationFailureSummary(failure, resource: "Live provider catalog"))
                    .font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Text(failure.detail)
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    .lineLimit(2)
            }

            if scopedProviders.isEmpty {
                if catalogFailure != nil {
                    pillButton(title: "Retry catalog", filled: false, busy: loading) {
                        Task { await load() }
                    }
                } else {
                    Text("The current provider catalog lists no providers for this role and transport mode.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                ForEach(displayedProviders) { providerRow($0) }
            }

            if !unmatchedConnections.isEmpty {
                Text("CONNECTIONS OUTSIDE CURRENT CATALOG")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 4)
                Text("These accessible connections are not listed in the current role catalog. Provider details, synchronization support, and documentation are unavailable. Disconnect is offered only when the current connection record confirms management access.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(unmatchedConnections) { unavailableConnectionRow($0) }
            }
        }
    }

    private func unavailableConnectionRow(_ connection: IntegrationConnection) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.providerId)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textPrimary)
                Label(connectionDisplayStateLabel(connection), systemImage: "exclamationmark.triangle")
                    .font(EType.mono(.micro))
                    .foregroundStyle(Brand.warning)
                Text(credentialCustodyLabel(connection.credentialState))
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if connection.canManage == true {
                pillButton(
                    title: busyProvider == connection.providerId ? "…" : "Disconnect",
                    filled: false,
                    danger: true,
                    busy: false
                ) {
                    pendingDisconnect = IntegrationDisconnectIntent(
                        connection: connection,
                        providerName: connection.providerId
                    )
                }
                .disabled(busyProvider != nil)
            } else {
                Label("Management access unavailable", systemImage: "lock.shield")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func providerRow(_ p: IntegrationProvider) -> some View {
        let conn = connections.first { $0.providerId == p.id }
        let hasConnection = conn?.isPresent == true
        let isExpanded = expandedProvider == p.id
        let busy = busyProvider == p.id

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(cleanLabel(p.displayName)).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    HStack(spacing: 6) {
                        if let cat = p.category, !cat.isEmpty {
                            Text(categoryLabel(cat))
                                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                                .foregroundStyle(LinearGradient.diagonal)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(palette.bgCardSoft).clipShape(Capsule())
                        }
                        if let vendor = p.vendor, !vendor.isEmpty {
                            Text(cleanLabel(vendor)).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                        }
                    }
                    if let desc = p.description, !desc.isEmpty {
                        Text(cleanLabel(desc)).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
                    }
                    providerJourneySummary(p)
                    if !p.connectable, let reason = p.blockedReason, !reason.isEmpty {
                        Text(cleanLabel(reason))
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if p.connectable,
                       !p.canEstablishConnection,
                       let reason = p.establishmentBlockedReason,
                       !reason.isEmpty {
                        Text(cleanLabel(reason))
                            .font(EType.mono(.micro))
                            .foregroundStyle(Brand.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let url = providerDocsURL(from: p.docsUrl) {
                        Link(destination: url) {
                            Label("Provider documentation", systemImage: "safari")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Brand.blue)
                        }
                    }
                    if conn != nil {
                        connectedStatusLine(conn, provider: p)
                    }
                }
                Spacer(minLength: 8)
                providerActions(p, hasConnection: hasConnection, conn: conn, isExpanded: isExpanded, busy: busy)
            }

            if isExpanded && !hasConnection {
                connectForm(p, busy: busy)
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if p.id != displayedProviders.last?.id {
                Rectangle().fill(palette.borderFaint).frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func providerJourneySummary(_ p: IntegrationProvider) -> some View {
        if let journey = p.journey {
            VStack(alignment: .leading, spacing: 4) {
                if let headline = journey.headline, !headline.isEmpty {
                    Text(cleanLabel(headline))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let tags = journey.capabilityTags, !tags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(Array(tags.prefix(4)), id: \.self) { tag in
                            Text(prettyToken(tag).uppercased())
                                .font(.system(size: 7, weight: .heavy))
                                .tracking(0.45)
                                .foregroundStyle(palette.textTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(palette.bgCardSoft)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func connectedStatusLine(_ conn: IntegrationConnection?, provider: IntegrationProvider) -> some View {
        let state = conn?.effectiveFeedState
        let isError = state == "error"
        let isWarning = state == "stale" || state == "credentials_required"
        let color = state == nil ? Brand.warning
            : isError ? Brand.danger
            : isWarning ? Brand.warning
            : state == "connecting" ? Brand.blue
            : state == "disabled" ? palette.textTertiary
            : ["live", "on_demand"].contains(state ?? "") ? Brand.success
            : Brand.warning
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(state.map { feedStateLabel($0) } ?? "Feed state unavailable")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(color)
            if let cadence = conn?.syncIntervalMinutes, conn?.syncMode == "scheduled" {
                Text("· every \(cadence)m").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            if let synced = conn?.lastSuccessfulSyncAt ?? conn?.lastSyncedAt, !synced.isEmpty {
                Text("· \(humanISO(synced))").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
        }
        if isError, let e = conn?.lastError, !e.isEmpty {
            Text(e).font(EType.mono(.micro)).foregroundStyle(Brand.danger).lineLimit(2)
        }
        if let conn {
            if state == nil, let status = conn.status, !status.isEmpty {
                Text("\(connectionStatusLabel(status)); operational status remains unknown.")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reason = conn.feedStateReason, !reason.isEmpty {
                Text(feedStateReasonLabel(reason))
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            Label(connectionOwnershipLabel(conn), systemImage: conn.sharedWithCompany == true ? "building.2" : "person.crop.circle")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Label(credentialCustodyLabel(conn.credentialState), systemImage: "lock.shield")
                .font(EType.mono(.micro))
                .foregroundStyle(conn.credentialState == "missing" ? Brand.warning : palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Catalog verification: \(connectionVerificationLabel(provider.activationVerification ?? provider.connectionVerification))", systemImage: "checkmark.seal")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let activation = conn.activation {
                connectionActivationEvidence(activation)
            } else {
                Label("Current activation evidence is unavailable", systemImage: "questionmark.diamond")
                    .font(EType.mono(.micro))
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let updated = conn.updatedAt, !updated.isEmpty {
                Text("Connection record updated \(humanISO(updated))")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func connectionActivationEvidence(_ activation: IntegrationActivationSummary) -> some View {
        Label(activationStateLabel(activation.state), systemImage: activation.ready ? "checkmark.seal.fill" : "clock.badge.exclamationmark")
            .font(EType.mono(.micro))
            .foregroundStyle(activation.ready ? Brand.success : Brand.warning)
            .fixedSize(horizontal: false, vertical: true)
        ForEach(activation.steps, id: \.key) { step in
            let owner = step.owner == "provider" ? "Provider action" : "Company action"
            VStack(alignment: .leading, spacing: 2) {
                Text("\(owner) · \(cleanLabel(step.label)) · \(activationStepStateLabel(step.state))")
                    .font(EType.mono(.micro))
                    .foregroundStyle(step.state == "verified" ? Brand.success : palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = step.detail, !detail.isEmpty {
                    Text(cleanLabel(detail))
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let verifiedAt = step.verifiedAt, !verifiedAt.isEmpty {
                    Text("Verified \(humanISO(verifiedAt))")
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                }
                if let url = providerDocsURL(from: step.docsUrl) {
                    Link(destination: url) {
                        Label("Requirement instructions", systemImage: "safari")
                            .font(EType.mono(.micro))
                            .foregroundStyle(Brand.blue)
                    }
                }
            }
            .padding(.leading, 11)
        }
    }

    @ViewBuilder
    private func providerActions(_ p: IntegrationProvider, hasConnection: Bool, conn: IntegrationConnection?, isExpanded: Bool, busy: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if connectionsFailure != nil && p.connectable {
                pillButton(title: "State unavailable", filled: false, busy: false) {}
                    .disabled(true)
            } else if hasConnection {
                if p.supportsSync == true,
                   conn?.accessible == true,
                   let state = conn?.effectiveFeedState,
                   !["connecting", "credentials_required", "disabled"].contains(state) {
                    pillButton(title: busy ? "Syncing…" : "Sync", filled: false, busy: busy) {
                        Task { await sync(conn) }
                    }
                    .disabled(busy)
                }
                if conn?.canManage == true {
                    pillButton(title: busy ? "…" : "Disconnect", filled: false, danger: true, busy: false) {
                        guard let conn else { return }
                        pendingDisconnect = IntegrationDisconnectIntent(
                            connection: conn,
                            providerName: p.displayName
                        )
                    }
                    .disabled(busy)
                } else {
                    pillButton(title: "Company admin required", filled: false, busy: false) {}
                        .disabled(true)
                }
            } else {
                if !p.connectable {
                    pillButton(title: isExpanded ? "Close" : "Setup details", filled: false, busy: false) {
                        expandedProvider = isExpanded ? nil : p.id
                    }
                } else if !p.canEstablishConnection {
                    pillButton(title: "Credential owner required", filled: false, busy: false) {}
                        .disabled(true)
                } else if conn != nil && conn?.canManage != true {
                    pillButton(title: "Company admin required", filled: false, busy: false) {}
                        .disabled(true)
                } else {
                    pillButton(
                        title: busy ? "Connecting…" : isExpanded ? "Cancel" : "Connect",
                        filled: !isExpanded,
                        busy: busy
                    ) {
                        if isExpanded {
                            expandedProvider = nil
                        } else {
                            expandedProvider = p.id
                        }
                    }
                    .disabled(busy)
                }
            }
        }
    }

    /// Inline credential entry (push-nav style in-flow disclosure — not a slide-up sheet).
    @ViewBuilder
    private func connectForm(_ p: IntegrationProvider, busy: Bool) -> some View {
        let canCollectCredentials = p.canEstablishConnection && providerProvisioningReady(p)
        VStack(alignment: .leading, spacing: 8) {
            Text(providerCredentialGuidance(p))
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            providerActivationDisclosure(p)
            providerCompanyConfirmations(p)
            providerJourneyDisclosure(p)

            if p.connectable && !p.canEstablishConnection {
                Label(
                    p.establishmentBlockedReason
                        ?? "An authorized company credential custodian must establish this shared connection. Once verified, eligible users can consume its live workflow benefits without receiving or replacing credentials.",
                    systemImage: "building.2.crop.circle"
                )
                .font(EType.mono(.micro))
                .foregroundStyle(Brand.warning)
                .fixedSize(horizontal: false, vertical: true)
            } else if p.connectable && !canCollectCredentials {
                Label(
                    p.provisioning == nil || p.provisioning?.requirements.isEmpty == true
                        ? "The provider provisioning contract is unavailable. Credential entry and authorization remain locked."
                        : "Confirm the company prerequisites above before entering credentials or opening provider authorization.",
                    systemImage: "lock.shield"
                )
                .font(EType.mono(.micro))
                .foregroundStyle(Brand.warning)
                .fixedSize(horizontal: false, vertical: true)
            } else if p.connectable && !usesNativeOAuth(p) {
                providerAuthenticationAlternatives(p)

                if !p.credentialFields.isEmpty {
                    Text("CREDENTIALS")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    ForEach(p.credentialFields, id: \.self) { field in
                        providerInputField(provider: p.id, kind: "credential", field: field)
                    }
                }

                if !p.configurationFields.isEmpty {
                    Text("CONNECTION SETTINGS")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    ForEach(p.configurationFields, id: \.self) { field in
                        providerInputField(provider: p.id, kind: "configuration", field: field)
                    }
                }
            }

            // Provider reference. The role catalog stores verified provider
            // developer surfaces, so preserve the full destination instead of
            // collapsing deep docs back to a generic root host.
            if let url = providerDocsURL(from: p.docsUrl) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "safari").font(.system(size: 9, weight: .semibold))
                        Text("Open \(providerDocsLabel(from: url))").font(.system(size: 10, weight: .semibold))
                    }.foregroundStyle(Brand.blue)
                }
            } else {
                Label("Verified provider documentation link unavailable", systemImage: "exclamationmark.triangle")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }

            if p.connectable {
                HStack {
                    Spacer()
                    pillButton(
                        title: busy ? "Connecting…" : usesNativeOAuth(p) ? "Authorize provider" : "Connect provider",
                        filled: true,
                        busy: busy
                    ) {
                        Task {
                            if usesNativeOAuth(p) {
                                await authorizeOAuth(p)
                                return
                            }
                            do {
                                let payload = try activationPayload(for: p)
                                await connect(
                                    p,
                                    credentials: payload.credentials.isEmpty ? nil : payload.credentials,
                                    configuration: payload.configuration
                                )
                            } catch {
                                actionError = errorMessage(error)
                            }
                        }
                    }
                    .disabled(!connectFormReady(p) || busy)
                    .opacity(connectFormReady(p) ? 1 : 0.5)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func providerActivationDisclosure(_ p: IntegrationProvider) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("ACTIVATION OWNERSHIP")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text(p.provisioning == nil ? "CONTRACT UNAVAILABLE" : provisioningModeLabel(p.provisioning?.mode).uppercased())
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(p.provisioning == nil ? Brand.warning : palette.textTertiary)
            }
            if let provisioning = p.provisioning, !provisioning.requirements.isEmpty {
                ForEach(provisioning.requirements, id: \.key) { requirement in
                    provisioningRequirementRow(requirement, provider: p)
                }
                Text(provisioning.activation == "automatic_after_verification"
                     ? "EusoTrip activates automatically only after every required proof is verified."
                     : "Activation remains subject to the provider's published approval policy.")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("The live catalog did not publish provisioning requirements. Activation submission is locked.", systemImage: "exclamationmark.triangle")
                    .font(EType.mono(.micro))
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            activationDisclosureRow(
                icon: "checkmark.shield",
                title: "EusoTrip verification",
                detail: providerServerActivationRequirement(p)
            )
            activationDisclosureRow(
                icon: "lock.shield",
                title: "Credential custody",
                detail: "Submitted secrets are protected by EusoTrip, cleared from this form after the attempt, and never returned in connection details."
            )
            let proof = researchStatusLabel(p.researchStatus)
            let checked = p.researchVerifiedAt.map { " · checked \(humanISO($0))" } ?? ""
            Text("Catalog research: \(proof)\(checked)")
                .font(EType.mono(.micro))
                .foregroundStyle(p.researchStatus == "verified" ? Brand.success : palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    @ViewBuilder
    private func provisioningRequirementRow(
        _ requirement: IntegrationProvisioningRequirement,
        provider: IntegrationProvider
    ) -> some View {
        let owner = requirement.owner == "provider"
            ? "\(cleanLabel(provider.vendor ?? provider.displayName)) verifies this"
            : "Your company supplies this"
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: requirement.owner == "provider" ? "building.2.crop.circle" : "person.crop.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(cleanLabel(requirement.label))
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                Text("\(owner) · \(provisioningVerificationLabel(requirement.verification))")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = providerDocsURL(from: requirement.docsUrl) {
                    Link(destination: url) {
                        Label("Requirement instructions", systemImage: "safari")
                            .font(EType.mono(.micro))
                            .foregroundStyle(Brand.blue)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func providerCompanyConfirmations(_ p: IntegrationProvider) -> some View {
        let requirements = customerConfirmationRequirements(p)
        if !requirements.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("COMPANY CONFIRMATIONS")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                ForEach(requirements, id: \.key) { requirement in
                    let key = confirmationKey(provider: p.id, requirement: requirement.key)
                    let confirmed = confirmedProvisioningRequirements.contains(key)
                    Button {
                        if confirmed {
                            confirmedProvisioningRequirements.remove(key)
                        } else {
                            confirmedProvisioningRequirements.insert(key)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: confirmed ? "checkmark.square.fill" : "square")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(confirmed ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cleanLabel(requirement.label))
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textPrimary)
                                Text("I confirm I am authorized to attest this prerequisite for my company.")
                                    .font(EType.mono(.micro))
                                    .foregroundStyle(palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Confirm \(requirement.label)")
                }
            }
            .padding(9)
            .background(palette.bgCardSoft)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
    }

    @ViewBuilder
    private func providerAuthenticationAlternatives(_ p: IntegrationProvider) -> some View {
        if let requirement = p.inputRequirement, !requirement.alternatives.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(requirement.mode == "any_of" ? "CHOOSE ONE AUTHENTICATION METHOD" : "AUTHENTICATION REQUIREMENTS")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                ForEach(Array(requirement.alternatives.enumerated()), id: \.offset) { index, alternative in
                    let keys = alternative.credentials + (alternative.configuration ?? [])
                    Text("\(index + 1). \(keys.map { inputFieldLabel($0, provider: p) }.joined(separator: " + "))")
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func activationDisclosureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                Text(cleanLabel(detail))
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func providerJourneyDisclosure(_ p: IntegrationProvider) -> some View {
        if let journey = p.journey {
            VStack(alignment: .leading, spacing: 5) {
                journeyDisclosureRow("UNLOCK", journey.operationalUnlock)
                journeyDisclosureRow("CROSS-ROLE", journey.crossRoleBenefit)
                journeyDisclosureRow("CREDENTIAL", journey.credentialHint)
                journeyDisclosureRow("FLOW", journey.dataFlow)
            }
            .padding(9)
            .background(palette.bgCardSoft)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
    }

    @ViewBuilder
    private func journeyDisclosureRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 7) {
                Text(label)
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.55)
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 64, alignment: .leading)
                Text(cleanLabel(value))
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func providerInputField(provider: String, kind: String, field: IntegrationInputField) -> some View {
        let bindingKey = inputKey(provider: provider, kind: kind, field: field.key)
        return VStack(alignment: .leading, spacing: 3) {
            Text((field.required ? field.label : "\(field.label) · OPTIONAL").uppercased())
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                if field.inputType == "certificate" || field.inputType == "private_key" {
                    SensitiveMultilineTextEditor(text: Binding(
                        get: { credInputs[bindingKey] ?? "" },
                        set: { credInputs[bindingKey] = $0 }))
                    .frame(minHeight: 132)
                } else if field.secret || field.inputType == "secret" {
                    SecureField(field.label, text: Binding(
                        get: { credInputs[bindingKey] ?? "" },
                        set: { credInputs[bindingKey] = $0 }))
                } else if field.inputType == "json" {
                    TextEditor(text: Binding(
                        get: { credInputs[bindingKey] ?? "" },
                        set: { credInputs[bindingKey] = $0 }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 132)
                } else {
                    TextField(field.label, text: Binding(
                        get: { credInputs[bindingKey] ?? "" },
                        set: { credInputs[bindingKey] = $0 }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
            }
            .keyboardType(field.inputType == "number" ? .decimalPad
                          : field.inputType == "email" ? .emailAddress
                          : field.inputType == "url" ? .URL
                          : .default)
            .font(EType.mono(.caption))
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .accessibilityLabel(field.required ? field.label : "\(field.label), optional")
        }
    }

    // MARK: - Integration unlocks (live profileAdaptation envelope)

    @ViewBuilder
    private var adaptationSection: some View {
        let adaptation = liveAdaptation ?? session.user?.profileAdaptation
        let items = adaptation?.menuItems ?? []
        let caps = adaptation?.capabilities ?? []
        let surfaces = adaptation?.roleSurfaces ?? []
        if adaptationUnavailableReason != nil || !items.isEmpty || !caps.isEmpty || !surfaces.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "INTEGRATION UNLOCKS", icon: "puzzlepiece.extension")
                if let reason = adaptationUnavailableReason {
                    Text("Live integration unlocks could not be refreshed. Any items below are from the current authenticated session.")
                        .font(EType.caption).foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reason)
                        .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                    pillButton(title: "Retry unlocks", filled: false, busy: false) {
                        Task { await refreshProfileAdaptation() }
                    }
                }
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.icon.isEmpty ? "arrow.right.circle" : item.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(item.label).font(EType.caption).foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 8)
                        Text(item.path)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.vertical, 2)
                }
                if !caps.isEmpty {
                    Text("Capabilities: \(caps.map(prettyToken).joined(separator: ", "))")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !surfaces.isEmpty {
                    Text("Role surfaces: \(surfaces.map(prettyToken).joined(separator: ", "))")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - API tokens (issue in-app, never "go to the web page")

    @ViewBuilder
    private var tokensSection: some View {
        LifecycleCard {
            HStack {
                LifecycleSection(label: "API TOKENS", icon: "key")
                Spacer(minLength: 8)
                pillButton(title: showIssueForm ? "Close" : "Issue token", filled: !showIssueForm, busy: false) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showIssueForm.toggle()
                        if !showIssueForm { newKeyName = ""; selectedScopes = []; freshlyIssuedKey = nil }
                    }
                }
            }

            if let fresh = freshlyIssuedKey {
                freshKeyCallout(fresh)
            }

            if showIssueForm {
                issueForm
            }

            if let reason = tokensUnavailableReason {
                Text("API token state could not be loaded. Existing tokens are not assumed absent.")
                    .font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reason)
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    .lineLimit(2)
                pillButton(title: "Retry token state", filled: false, busy: false) {
                    Task { await refreshApiKeys() }
                }
            } else if apiKeys.isEmpty {
                Text("No API tokens issued yet. Tap Issue token to create one — programmatic access to your loads, tracking, and documents.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(apiKeys) { keyRow($0) }
            }
        }
    }

    private func freshKeyCallout(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.success)
                Text("Token created — copy it now").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.success)
            }
            Text("This is the only time the full key is shown. Store it securely.")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            HStack {
                Text(key).font(EType.mono(.caption)).foregroundStyle(palette.textPrimary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Button {
                    UIPasteboard.general.string = key
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc").font(.system(size: 10, weight: .semibold))
                        Text("Copy").font(.system(size: 10, weight: .heavy))
                    }.foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.success.opacity(0.45), lineWidth: 1))
    }

    @ViewBuilder
    private var issueForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TOKEN NAME").font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                TextField("e.g. Warehouse TMS sync", text: $newKeyName)
                    .font(EType.mono(.caption)).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }

            Text("SCOPES").font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            if let reason = scopesUnavailableReason {
                Text("Scope catalog could not be loaded. Token creation is locked until valid scopes are available.")
                    .font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reason)
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    .lineLimit(2)
                pillButton(title: "Retry scopes", filled: false, busy: false) {
                    Task { await refreshScopes() }
                }
            } else if scopes.isEmpty {
                Text("No token scopes are available for this role.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                FlowScopes(scopes: scopes, selected: $selectedScopes, palette: palette)
            }

            HStack {
                Spacer()
                pillButton(title: issuing ? "Issuing…" : "Create token", filled: true, busy: issuing) {
                    Task { await issueToken() }
                }
                .disabled(!issueReady || issuing)
                .opacity(issueReady ? 1 : 0.5)
            }
        }
        .padding(.top, 2)
    }

    private var issueReady: Bool {
        !newKeyName.trimmingCharacters(in: .whitespaces).isEmpty && !selectedScopes.isEmpty
    }

    private func keyRow(_ k: ApiKeyRow) -> some View {
        let revoked = (k.status ?? "").lowercased() == "revoked"
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(k.name).font(EType.bodyStrong).foregroundStyle(revoked ? palette.textTertiary : palette.textPrimary)
                        if revoked {
                            Text("REVOKED").font(.system(size: 8, weight: .heavy)).tracking(0.5)
                                .foregroundStyle(Brand.danger)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Brand.danger.opacity(0.12)).clipShape(Capsule())
                        }
                    }
                    Text(k.key).font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
                    HStack(spacing: 8) {
                        if let req = k.requestCount { Text("\(req) reqs").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary) }
                        if let used = k.lastUsed, !used.isEmpty {
                            Text("last used \(humanISO(used))").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                        } else {
                            Text("never used").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                        }
                        if let exp = k.expiresAt, !exp.isEmpty {
                            Text("exp \(humanISO(exp, format: "MMM d yyyy"))").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                        }
                    }
                    if let sc = k.scopes, !sc.isEmpty {
                        Text(sc.joined(separator: ", ")).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if !revoked {
                    Button { Task { await revoke(k.id) } } label: {
                        HStack {
                            if revokingKey == k.id { ProgressView().tint(.white) }
                            Text(revokingKey == k.id ? "Revoking…" : "Revoke").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Brand.danger).clipShape(Capsule())
                    }.buttonStyle(.plain).disabled(revokingKey != nil)
                }
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: - Shared pill button (bespoke, house gradient)

    private func pillButton(title: String, filled: Bool, danger: Bool = false, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if busy { ProgressView().scaleEffect(0.6).tint(filled ? .white : Brand.blue) }
                Text(title).font(.system(size: 10, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(filled ? .white : (danger ? Brand.danger : Brand.blue))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(filled ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(danger ? Brand.danger.opacity(0.5) : (filled ? Color.clear : palette.borderFaint), lineWidth: 1))
            .clipShape(Capsule())
        }.buttonStyle(.plain)
    }

    // MARK: - Load + actions

    private func load() async {
        loading = true
        catalogFailure = nil
        connectionsFailure = nil
        tokensUnavailableReason = nil
        scopesUnavailableReason = nil
        adaptationUnavailableReason = nil
        let api = EusoTripAPI.shared

        async let cat: Result<[IntegrationProvider], Error> = capture {
            try await api.queryNoInput("userIntegrations.listCatalog")
        }
        async let cons: Result<[IntegrationConnection], Error> = capture {
            try await api.queryNoInput("userIntegrations.listConnections")
        }
        async let keys: Result<[ApiKeyRow], Error> = loadApiKeysIfNeeded()
        async let scopeRows: Result<[ApiScope], Error> = loadApiScopesIfNeeded()
        async let adaptationEnvelope: Result<ProfileAdaptation, Error> = loadAdaptationIfNeeded()

        switch await cat {
        case .success(let rows):
            providers = rows
            if let initialProviderId,
               rows.contains(where: { $0.id == initialProviderId }) {
                expandedProvider = initialProviderId
            }
        case .failure(let error):
            providers = []
            catalogFailure = integrationLoadFailure(error)
        }
        switch await cons {
        case .success(let rows):
            connections = rows
        case .failure(let error):
            connections = []
            connectionsFailure = integrationLoadFailure(error)
        }
        switch await keys {
        case .success(let rows):
            apiKeys = rows
        case .failure(let error):
            apiKeys = []
            tokensUnavailableReason = errorMessage(error)
        }
        switch await scopeRows {
        case .success(let rows):
            scopes = rows
        case .failure(let error):
            scopes = []
            scopesUnavailableReason = errorMessage(error)
        }
        switch await adaptationEnvelope {
        case .success(let adaptation):
            liveAdaptation = adaptation
        case .failure(let error):
            adaptationUnavailableReason = errorMessage(error)
        }

        loading = false
    }

    private func loadApiKeysIfNeeded() async -> Result<[ApiKeyRow], Error> {
        guard showsTokens else { return .success([]) }
        return await capture {
            try await EusoTripAPI.shared.queryNoInput("devPortal.apiKeys.list")
        }
    }

    private func loadApiScopesIfNeeded() async -> Result<[ApiScope], Error> {
        guard showsTokens else { return .success([]) }
        return await capture {
            try await EusoTripAPI.shared.queryNoInput("devPortal.mcpTools.getScopes")
        }
    }

    private func loadAdaptationIfNeeded() async -> Result<ProfileAdaptation, Error> {
        guard showsAdaptation else { return .success(ProfileAdaptation()) }
        return await capture {
            try await EusoTripAPI.shared.queryNoInput("userIntegrations.profileAdaptation")
        }
    }

    private func capture<T>(_ operation: @escaping () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func connect(
        _ p: IntegrationProvider,
        credentials: [String: IntegrationActivationValue]?,
        configuration: [String: IntegrationActivationValue]
    ) async {
        guard p.connectable else {
            actionError = p.blockedReason ?? "This provider is unavailable for production connection."
            return
        }
        guard connectionsFailure == nil else {
            actionError = "Connection state must be readable before credentials can be submitted."
            return
        }
        guard p.canEstablishConnection else {
            actionError = p.establishmentBlockedReason
                ?? "An authorized company credential custodian must establish this connection."
            return
        }
        guard providerProvisioningReady(p) else {
            actionError = "Confirm the required company prerequisites before connecting."
            return
        }
        if let existing = connections.first(where: { $0.providerId == p.id }),
           existing.canManage != true {
            actionError = "Only the credential custodian or a company administrator can replace this connection."
            return
        }
        busyProvider = p.id
        actionError = nil
        actionNotice = nil
        defer {
            clearSubmittedValues(for: p)
            busyProvider = nil
        }
        struct In: Encodable {
            let providerId: String
            let config: [String: IntegrationActivationValue]
            let credentials: [String: IntegrationActivationValue]?
            let confirmedRequirementKeys: [String]
        }
        struct Out: Decodable {
            let status: String
            let scopes: [String]?
            let error: String?
            let detail: String?
            let verification: String?
            let connectionPreserved: Bool?
        }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "userIntegrations.connect",
                input: In(
                    providerId: p.id,
                    config: configuration,
                    credentials: credentials,
                    confirmedRequirementKeys: confirmedRequirementKeys(for: p)))
            if ["connected", "connecting"].contains(out.status.lowercased()) {
                switch await refreshConnections() {
                case .success(let rows):
                    guard let confirmed = rows.first(where: { $0.providerId == p.id }) else {
                        actionError = "\(cleanLabel(p.displayName)) accepted the request, but no accessible connection record is available. No connection is being claimed."
                        return
                    }
                    if out.connectionPreserved == true {
                        expandedProvider = nil
                        actionNotice = (out.detail ?? "The replacement is still awaiting provider proof.")
                            + " The existing verified connection remains active."
                        return
                    }
                    guard confirmed.accessible == true else {
                        actionError = "A \(cleanLabel(p.displayName)) connection record is present, but access ownership is not confirmed. No connection is being claimed."
                        return
                    }
                    expandedProvider = nil
                    if verifiedOperationalReadback(confirmed) {
                        let proof = out.verification.map { " Verification: \(connectionVerificationLabel($0))." } ?? ""
                        actionNotice = "\(cleanLabel(p.displayName)) is usable. Activation evidence and ownership are confirmed in the current connection record.\(proof)"
                    } else if let activation = confirmed.activation, !activation.ready {
                        actionNotice = "The \(cleanLabel(p.displayName)) connection request is recorded. \(activationReadbackSummary(activation)) No usable feed is being claimed yet."
                    } else {
                        actionError = "A \(cleanLabel(p.displayName)) connection record is present, but usable feed and activation evidence are not both confirmed. Operational state remains unknown."
                        return
                    }
                    await refreshProfileAdaptation()
                case .failure:
                    actionError = "\(cleanLabel(p.displayName)) accepted the request, but current connection details are unavailable. Treat it as not connected until they can be confirmed."
                }
            } else {
                let preserved = out.connectionPreserved == true ? " Your existing verified connection remains active." : ""
                let readback = await refreshConnections()
                let readbackSuffix: String
                if case .failure = readback {
                    readbackSuffix = " Current connection details are unavailable."
                } else {
                    readbackSuffix = " Current connection details were refreshed."
                }
                actionError = (out.error ?? "\(cleanLabel(p.displayName)) requires additional authorization.")
                    + preserved
                    + readbackSuffix
            }
        } catch let e as EusoTripAPIError {
            actionError = e.errorDescription ?? "Couldn't connect \(cleanLabel(p.displayName))."
            _ = await refreshConnections()
        } catch {
            actionError = error.localizedDescription
            _ = await refreshConnections()
        }
    }

    private func authorizeOAuth(_ provider: IntegrationProvider) async {
        guard provider.connectable, usesNativeOAuth(provider) else {
            actionError = provider.blockedReason ?? "Native OAuth is not enabled for this provider."
            return
        }
        guard connectionsFailure == nil else {
            actionError = "Connection state must be readable before provider authorization can start."
            return
        }
        guard provider.canEstablishConnection else {
            actionError = provider.establishmentBlockedReason
                ?? "An authorized company credential custodian must establish this connection."
            return
        }
        guard providerProvisioningReady(provider) else {
            actionError = "Confirm the required company prerequisites before authorizing this provider."
            return
        }
        if let existing = connections.first(where: { $0.providerId == provider.id }),
           existing.canManage != true {
            actionError = "Only the credential custodian or a company administrator can replace this connection."
            return
        }
        busyProvider = provider.id
        actionError = nil
        actionNotice = nil
        defer {
            clearSubmittedValues(for: provider)
            busyProvider = nil
        }
        do {
            let authorizationURL = try await EusoTripAPI.shared.startIntegrationOAuth(
                providerId: provider.id,
                confirmedRequirementKeys: confirmedRequirementKeys(for: provider)
            )
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                oauthSession.start(
                    authorizationURL: authorizationURL,
                    providerId: provider.id
                ) { result in
                    continuation.resume(with: result)
                }
            }
            switch await refreshConnections() {
            case .success(let rows):
                guard let confirmed = rows.first(where: { $0.providerId == provider.id }) else {
                    actionError = "Provider authorization returned, but no accessible connection record is available. No connection is being claimed."
                    return
                }
                guard confirmed.accessible == true else {
                    actionError = "Provider authorization returned, but connection access ownership was not confirmed. No connection is being claimed."
                    return
                }
                expandedProvider = nil
                if verifiedOperationalReadback(confirmed) {
                    actionNotice = "\(cleanLabel(provider.displayName)) authorization, usable feed, activation evidence, and ownership are confirmed in the current connection record."
                } else if let activation = confirmed.activation, !activation.ready {
                    actionNotice = "\(cleanLabel(provider.displayName)) authorization returned. \(activationReadbackSummary(activation)) No usable feed is being claimed yet."
                } else {
                    actionError = "Provider authorization returned, but usable feed and activation evidence were not both confirmed. Operational state remains unknown."
                    return
                }
                await refreshProfileAdaptation()
            case .failure:
                actionError = "Provider authorization returned, but current connection details are unavailable. Treat it as not connected until they can be confirmed."
            }
        } catch let error as IntegrationOAuthSessionError {
            if case .authorizationCanceled = error {
                actionNotice = error.errorDescription
            } else {
                actionError = error.errorDescription
                _ = await refreshConnections()
            }
        } catch let error as EusoTripAPIError {
            actionError = error.errorDescription ?? "Couldn't authorize \(cleanLabel(provider.displayName))."
            _ = await refreshConnections()
        } catch {
            actionError = error.localizedDescription
            _ = await refreshConnections()
        }
    }

    private func disconnect(_ conn: IntegrationConnection, providerName: String) async {
        guard conn.canManage == true else {
            actionError = "Only the credential custodian or a company administrator can disconnect this connection."
            return
        }
        busyProvider = conn.providerId
        actionError = nil
        actionNotice = nil
        defer { busyProvider = nil }
        struct In: Encodable { let connectionId: Int }
        struct Out: Decodable {
            let ok: Bool
            let status: String?
            let credentialState: String?
            let providerRevocation: String?
        }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation("userIntegrations.disconnect", input: In(connectionId: conn.id))
            if out.ok,
               out.status == "disabled",
               out.credentialState == "persisted_reference_revoked",
               out.providerRevocation == "adapter_completed" {
                switch await refreshConnections() {
                case .success(let rows):
                    if let readback = rows.first(where: { $0.id == conn.id }) {
                        let credentialRevoked = ["missing", "not_required"].contains(readback.credentialState ?? "")
                        let activationRevoked = readback.activation?.state == "revoked"
                        guard !readback.isPresent,
                              readback.status?.lowercased() == "disabled",
                              readback.effectiveFeedState == "disabled",
                              credentialRevoked,
                              activationRevoked else {
                            actionError = "The disconnect request was accepted, but the current \(cleanLabel(providerName)) connection record does not yet confirm a disabled feed, revoked credential custody, and revoked activation evidence. Treat it as still active."
                            return
                        }
                        actionNotice = "\(cleanLabel(providerName)) is disconnected. Current connection evidence confirms the feed is disabled and credential custody and activation evidence are revoked."
                        await refreshProfileAdaptation()
                    } else {
                        actionNotice = "\(cleanLabel(providerName)) is disconnected. Provider authorization and stored credential access were revoked, and no accessible connection remains."
                        await refreshProfileAdaptation()
                    }
                case .failure:
                    actionError = "The disconnect request was accepted, but current connection details are unavailable. Treat \(cleanLabel(providerName)) and its credential as still active until the result can be confirmed."
                }
            } else {
                actionError = "The disconnect result did not confirm provider authorization revocation, credential removal, and a disabled feed. Treat this connection and its credential as still active."
            }
        } catch let e as EusoTripAPIError {
            actionError = e.errorDescription ?? "Couldn't disconnect."
            _ = await refreshConnections()
        } catch {
            actionError = error.localizedDescription
            _ = await refreshConnections()
        }
    }

    private func sync(_ conn: IntegrationConnection?) async {
        guard let conn else { return }
        guard conn.accessible == true else {
            actionError = "Your current connection access does not permit synchronization."
            return
        }
        guard conn.isPresent else {
            actionError = "This connection is disabled and cannot be synced."
            return
        }
        busyProvider = conn.providerId
        actionError = nil
        actionNotice = nil
        struct In: Encodable { let connectionId: Int }
        struct Out: Decodable {
            let status: String
            let nextEligibleAt: String?
            let recordsIngested: Int?
            let observationsInserted: Int?
            let observationDuplicates: Int?
        }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation("userIntegrations.sync", input: In(connectionId: conn.id))
            guard ["synced", "skipped_cadence"].contains(out.status) else {
                actionError = "The provider returned an unrecognized synchronization result. No synchronization is being claimed."
                busyProvider = nil
                return
            }
            switch await refreshConnections() {
            case .success(let rows):
                guard let readback = rows.first(where: { $0.id == conn.id }) else {
                    actionError = "The synchronization response was received, but the connection is no longer available in current connection details. No durable synchronization result is being claimed."
                    break
                }
                if out.status == "synced" {
                    guard readback.accessible == true,
                          let feedState = readback.effectiveFeedState,
                          let isOperational = readback.isOperational,
                          let activation = readback.activation else {
                        actionError = "The synchronization response was received, but current connection details do not establish feed status, access, usability, or activation. Operational status remains unknown."
                        break
                    }
                    let evidence = syncCountEvidence(
                        records: out.recordsIngested,
                        observations: out.observationsInserted,
                        duplicates: out.observationDuplicates
                    )
                    if isOperational && activation.ready {
                        actionNotice = "Provider synchronization is confirmed. \(evidence) \(feedStateLabel(feedState)) feed evidence is usable."
                    } else if !activation.ready {
                        actionNotice = "Provider sync returned. \(evidence) \(activationReadbackSummary(activation)) No usable feed is being claimed yet."
                    } else {
                        actionError = "The synchronization response was received, but current connection details mark the feed unusable. No successful operational state is being claimed."
                    }
                } else {
                    guard readback.accessible == true,
                          let feedState = readback.effectiveFeedState,
                          readback.isOperational != nil else {
                        actionError = "The scheduling response was received, but current connection details do not establish feed status. Operational status remains unknown."
                        break
                    }
                    let next = out.nextEligibleAt.map { humanISO($0) } ?? "the provider's next eligible window"
                    actionNotice = "Synchronization was not due. The connection remains \(feedStateLabel(feedState).lowercased()); next eligible \(next)."
                }
                await refreshProfileAdaptation()
            case .failure:
                actionError = "The provider responded, but current connection details are unavailable. No durable synchronization result is being claimed."
            }
        } catch let e as EusoTripAPIError {
            actionError = e.errorDescription ?? "Sync failed."
            _ = await refreshConnections()
        } catch {
            actionError = error.localizedDescription
            _ = await refreshConnections()
        }
        busyProvider = nil
    }

    private func issueToken() async {
        issuing = true
        actionError = nil
        actionNotice = nil
        freshlyIssuedKey = nil
        struct In: Encodable { let name: String; let scopes: [String]; let expiresInDays: Int }
        struct Out: Decodable { let success: Bool; let apiKey: String?; let error: String? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "devPortal.apiKeys.create",
                input: In(name: newKeyName.trimmingCharacters(in: .whitespaces),
                          scopes: Array(selectedScopes).sorted(),
                          expiresInDays: 365))
            if out.success, let raw = out.apiKey {
                freshlyIssuedKey = raw
                newKeyName = ""; selectedScopes = []; showIssueForm = false
                await refreshApiKeys()
            } else {
                actionError = out.error ?? "Couldn't create the token."
            }
        } catch let e as EusoTripAPIError {
            actionError = e.errorDescription ?? "Couldn't create the token."
        } catch {
            actionError = error.localizedDescription
        }
        issuing = false
    }

    private func revoke(_ keyId: String) async {
        revokingKey = keyId
        actionError = nil
        actionNotice = nil
        struct In: Encodable { let keyId: String }
        struct Out: Decodable { let success: Bool }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation("devPortal.apiKeys.revoke", input: In(keyId: keyId))
            if out.success {
                actionNotice = "API token revoked."
                await refreshApiKeys()
            } else {
                actionError = "The revocation was not confirmed. Treat this API token as still live — retry, and rotate it if it still shows active."
            }
        } catch let e as EusoTripAPIError {
            actionError = e.errorDescription ?? "Couldn't revoke the token."
        } catch {
            actionError = error.localizedDescription
        }
        revokingKey = nil
    }

    @discardableResult
    private func refreshConnections() async -> Result<[IntegrationConnection], Error> {
        do {
            let rows: [IntegrationConnection] = try await EusoTripAPI.shared.queryNoInput("userIntegrations.listConnections")
            connections = rows
            connectionsFailure = nil
            return .success(rows)
        } catch {
            connectionsFailure = integrationLoadFailure(error)
            return .failure(error)
        }
    }

    private func refreshProfileAdaptation() async {
        do {
            let adaptation: ProfileAdaptation = try await EusoTripAPI.shared.queryNoInput("userIntegrations.profileAdaptation")
            liveAdaptation = adaptation
            adaptationUnavailableReason = nil
        } catch {
            adaptationUnavailableReason = errorMessage(error)
        }
    }

    private func refreshApiKeys() async {
        do {
            let rows: [ApiKeyRow] = try await EusoTripAPI.shared.queryNoInput("devPortal.apiKeys.list")
            apiKeys = rows
            tokensUnavailableReason = nil
        } catch {
            tokensUnavailableReason = errorMessage(error)
        }
    }

    private func refreshScopes() async {
        do {
            let rows: [ApiScope] = try await EusoTripAPI.shared.queryNoInput("devPortal.mcpTools.getScopes")
            scopes = rows
            scopesUnavailableReason = nil
        } catch {
            scopesUnavailableReason = errorMessage(error)
        }
    }

    private func clearSubmittedValues(for provider: IntegrationProvider) {
        for field in provider.credentialFields {
            credInputs[inputKey(provider: provider.id, kind: "credential", field: field.key)] = nil
        }
        for field in provider.configurationFields {
            credInputs[inputKey(provider: provider.id, kind: "configuration", field: field.key)] = nil
        }
        let prefix = "\(provider.id)|"
        confirmedProvisioningRequirements = Set(
            confirmedProvisioningRequirements.filter { !$0.hasPrefix(prefix) }
        )
    }

    private func errorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func integrationLoadFailure(_ error: Error) -> IntegrationLoadFailure {
        let detail = errorMessage(error)
        guard let apiError = error as? EusoTripAPIError else {
            return IntegrationLoadFailure(kind: .unavailable, detail: detail)
        }
        switch apiError {
        case .unauthenticated:
            return IntegrationLoadFailure(kind: .unauthenticated, detail: detail)
        case .forbidden:
            return IntegrationLoadFailure(kind: .permissionDenied, detail: detail)
        case .httpStatus(let status, _):
            if status == 401 {
                return IntegrationLoadFailure(kind: .unauthenticated, detail: detail)
            }
            if status == 403 {
                return IntegrationLoadFailure(kind: .permissionDenied, detail: detail)
            }
            return IntegrationLoadFailure(kind: .unavailable, detail: detail)
        default:
            return IntegrationLoadFailure(kind: .unavailable, detail: detail)
        }
    }

    private func integrationFailureSummary(_ failure: IntegrationLoadFailure, resource: String) -> String {
        switch failure.kind {
        case .unauthenticated:
            return "\(resource) requires a current sign-in. No connection availability is being inferred."
        case .permissionDenied:
            return "\(resource) is not permitted for this account. No connection availability is being inferred."
        case .unavailable:
            return "\(resource) is unavailable. Actions remain locked until current records can be confirmed."
        }
    }

    private func liveJourneyBenefits(
        providers: [IntegrationProvider],
        connections: [IntegrationConnection]?
    ) -> [IntegrationJourneyBenefit] {
        var groups: [IntegrationJourneyGroupKey: [IntegrationProvider]] = [:]
        for provider in providers {
            guard let journey = provider.journey,
                  let setup = journey.setup, !setup.isEmpty,
                  let unlock = journey.operationalUnlock, !unlock.isEmpty,
                  let shared = journey.crossRoleBenefit, !shared.isEmpty else {
                continue
            }
            let key = IntegrationJourneyGroupKey(
                adoptionStage: journey.adoptionStage,
                setup: setup,
                operationalUnlock: unlock,
                crossRoleBenefit: shared
            )
            groups[key, default: []].append(provider)
        }

        let operationalIds = connections.map { rows in
            Set(rows.filter { $0.isOperational == true }.map(\.providerId))
        }
        return groups.map { key, matching in
            let names = matching.map(\.displayName).sorted()
            let connectedCount = operationalIds.map { ids in
                matching.filter { ids.contains($0.id) }.count
            }
            return IntegrationJourneyBenefit(
                id: [key.adoptionStage ?? "", key.setup, key.operationalUnlock, key.crossRoleBenefit]
                    .joined(separator: "|"),
                adoptionStage: key.adoptionStage,
                setup: key.setup,
                operationalUnlock: key.operationalUnlock,
                crossRoleBenefit: key.crossRoleBenefit,
                providerCount: matching.count,
                connectedCount: connectedCount,
                providerNames: names
            )
        }
        .sorted { left, right in
            let leftConnected = left.connectedCount ?? -1
            let rightConnected = right.connectedCount ?? -1
            if leftConnected != rightConnected { return leftConnected > rightConnected }
            if left.providerCount != right.providerCount { return left.providerCount > right.providerCount }
            return left.setup < right.setup
        }
    }

    // MARK: - Helpers

    /// Strip machine tokens (bracketed enum keys, key=value pairs) that can
    /// bleed into server display strings. Mirrors 205_ShipperLoadDetail
    /// cleanLabel — display-layer only, never returns empty for non-empty input.
    private func cleanLabel(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\s*[·•]?\s*[A-Za-z_-]+=\S+"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\s*·\s*·\s*"#, with: " · ", options: .regularExpression)
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: " ·•"))
        if trimmed.isEmpty { return s.trimmingCharacters(in: .whitespaces) }
        return trimmed
    }

    /// Parse a verified provider docs URL from the live catalog. Display-layer
    /// only; never invents a destination when the catalog value is malformed.
    private func providerDocsURL(from raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let components = URLComponents(string: raw),
              components.user == nil,
              components.password == nil,
              let url = components.url,
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              components.host != nil else { return nil }
        return url
    }

    private func providerDocsLabel(from url: URL) -> String {
        (url.host ?? url.absoluteString).lowercased()
    }

    /// Turn a raw machine token ("FUEL_BUYER", "bulk-liquid") into a readable label.
    private func prettyToken(_ s: String) -> String {
        let spaced = s.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return spaced.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }

    private func feedStateLabel(_ state: String) -> String {
        switch state.lowercased() {
        case "live": return "Live"
        case "stale": return "Stale"
        case "on_demand": return "Ready on demand"
        case "error": return "Sync error"
        case "connecting": return "Connecting"
        case "credentials_required": return "Credentials needed"
        case "disabled": return "Disabled"
        default: return "Feed status unavailable"
        }
    }

    private func feedStateReasonLabel(_ reason: String) -> String {
        switch reason.lowercased() {
        case "connection_disabled":
            return "This connection is disabled."
        case "provider_not_registered":
            return "Provider registration is unavailable."
        case "provider_not_enabled_for_tenant_connections":
            return "This provider is not enabled for company connections."
        case "provider_credentials_missing":
            return "Provider credentials are required."
        case "verification_in_progress":
            return "Provider access verification is in progress."
        case "latest_provider_attempt_failed":
            return "The latest provider attempt did not complete."
        case "connection_state_invalid":
            return "The current connection status cannot be verified."
        case "scheduled_feed_never_synced":
            return "No successful provider synchronization has been recorded."
        case "scheduled_feed_missed_provider_cadence":
            return "Provider data is older than its allowed freshness window."
        case "scheduled_feed_within_provider_cadence":
            return "Provider data is within its expected freshness window."
        case "provider_push_connection_verified":
            return "Provider delivery access is verified."
        case "provider_syncs_on_demand":
            return "Provider data is available when synchronization is requested."
        case "provider_connection_verified":
            return "Provider connection access is verified."
        default:
            return "The current connection record does not explain the feed status."
        }
    }

    private func connectionStatusLabel(_ status: String) -> String {
        switch status.lowercased() {
        case "connected": return "Connection is established"
        case "connecting": return "Connection verification is in progress"
        case "error": return "The latest connection attempt did not complete"
        case "disabled": return "Connection is disabled"
        case "pending_credentials": return "Provider credentials are required"
        default: return "Connection status is unavailable"
        }
    }

    private func connectionDisplayStateLabel(_ connection: IntegrationConnection) -> String {
        if let feedState = connection.effectiveFeedState {
            return feedStateLabel(feedState)
        }
        if let status = connection.status, !status.isEmpty {
            return "\(connectionStatusLabel(status)) · feed status unavailable"
        }
        return "Connection and feed state unavailable"
    }

    private func syncCountEvidence(records: Int?, observations: Int?, duplicates: Int?) -> String {
        var evidence: [String] = []
        if let records {
            evidence.append("\(records) records received")
        }
        if let observations {
            evidence.append("\(observations) new observations stored")
        }
        if let duplicates {
            evidence.append("\(duplicates) duplicate observations ignored")
        }
        guard !evidence.isEmpty else {
            return "The provider did not return ingestion counts."
        }
        return evidence.joined(separator: ", ") + "."
    }

    private func connectionOwnershipLabel(_ connection: IntegrationConnection) -> String {
        if connection.accessible != true {
            return "Connection access and credential custody are unavailable"
        }
        if connection.ownershipScope == "user" {
            return connection.canManage == true
                ? "Personal connection · available only to you · managed by you"
                : "Personal connection · management access unavailable"
        }
        if connection.ownershipScope == "company", connection.sharedWithCompany == true {
            if connection.connectedByMe == true {
                return "Company connection · shared with eligible coworkers · managed by you"
            }
            if connection.canManage == true {
                return "Company connection · shared with eligible coworkers · administrator access"
            }
            return "Company connection · shared with eligible coworkers · credentials managed by the custodian or an administrator"
        }
        return "Connection ownership is unavailable"
    }

    private func credentialCustodyLabel(_ state: String?) -> String {
        switch state {
        case "present": return "Credential is stored and not shown"
        case "missing": return "Credential reference missing; connection is not usable"
        case "not_required": return "No provider credential required"
        default: return "Credential custody is unavailable"
        }
    }

    private func connectionVerificationLabel(_ verification: String?) -> String {
        switch verification?.lowercased() {
        case "live_probe", "health_probe": return "Live provider probe"
        case "first_sync": return "First provider sync"
        case "signed_webhook": return "Signed provider webhook"
        case "oauth_callback": return "Provider OAuth callback"
        case "public_source": return "Verified public source"
        case "contract_managed": return "Managed provider agreement"
        case .some: return "Verification path unavailable"
        case .none: return "Verification path unavailable"
        }
    }

    private func activationStateLabel(_ state: String) -> String {
        switch state.lowercased() {
        case "action_required": return "Your company must complete a prerequisite"
        case "pending_provider": return "Awaiting provider approval"
        case "verifying": return "EusoTrip is verifying live access"
        case "live": return "Activation evidence verified"
        case "failed": return "Activation verification failed"
        case "revoked": return "Activation evidence revoked"
        default: return "Activation status is unavailable"
        }
    }

    private func activationStepStateLabel(_ state: String) -> String {
        switch state.lowercased() {
        case "not_started": return "Not started"
        case "action_required": return "Action required"
        case "awaiting_provider": return "Awaiting provider"
        case "verifying": return "Verifying"
        case "verified": return "Verified"
        case "failed": return "Failed"
        case "expired": return "Expired"
        case "revoked": return "Revoked"
        default: return "Status unavailable"
        }
    }

    private func activationReadbackSummary(_ activation: IntegrationActivationSummary) -> String {
        guard let step = activation.steps.first(where: { $0.state != "verified" }) else {
            return activationStateLabel(activation.state)
        }
        let owner = step.owner == "provider" ? "Provider action" : "Company action"
        return "\(activationStateLabel(activation.state)): \(owner.lowercased()) for \(cleanLabel(step.label))."
    }

    private func verifiedOperationalReadback(_ connection: IntegrationConnection) -> Bool {
        connection.accessible == true
            && connection.isOperational == true
            && connection.effectiveFeedState != nil
            && connection.activation?.ready == true
    }

    private func provisioningModeLabel(_ mode: String?) -> String {
        switch mode?.lowercased() {
        case "self_service_credentials": return "Self-service access"
        case "customer_account_approval": return "Provider-approved company access"
        case "commercial_contract": return "Commercial provider agreement"
        case .some: return "Provisioning details unavailable"
        case .none: return "Provisioning unavailable"
        }
    }

    private func provisioningVerificationLabel(_ verification: String) -> String {
        switch verification.lowercased() {
        case "user_confirmation": return "Confirmed by your company administrator"
        case "credential_probe": return "Verified by a live credential check"
        case "health_check": return "Verified by a live provider health check"
        case "provider_entitlement": return "Verified against the provider entitlement"
        case "first_sync": return "Verified only after the first real data sync"
        default: return "Verification details unavailable"
        }
    }

    private func researchStatusLabel(_ status: String?) -> String {
        switch status?.lowercased() {
        case "verified": return "Verified"
        case "reviewed": return "Reviewed"
        case "pending": return "Review pending"
        case "unavailable", .none: return "Unavailable"
        case .some: return "Status unavailable"
        }
    }

    /// Human label for an integration category slug.
    private func categoryLabel(_ raw: String) -> String {
        let map: [String: String] = [
            "rateData": "Rate Data", "loadBoard": "Load Board", "visibility": "Visibility",
            "tms": "TMS", "erp": "ERP", "eld": "ELD", "fuelCard": "Fuel Card",
            "factoring": "Factoring", "weather": "Weather", "nav": "Navigation",
            "payments": "Payments", "docs": "Documents", "compliance": "Compliance",
            "carrierVetting": "Carrier Vetting", "banking": "Banking", "identity": "Identity",
            "crm": "CRM", "dispatch": "Dispatch", "maintenance": "Maintenance", "toll": "Toll",
            "insurance": "Insurance", "dashcam": "Dashcam", "training": "Training",
            "bgScreening": "Screening", "marketIntel": "Market Intel",
            "railClassI": "Class I Rail", "railIndustry": "Rail Industry", "railEquip": "Rail Equip",
            "railOps": "Rail Ops", "oceanBooking": "Ocean Booking", "oceanCarrier": "Ocean Carrier",
            "oceanIntel": "Ocean Intel", "marine": "Marine", "bunker": "Bunker",
            "classSociety": "Class Society", "satcom": "Satcom", "satellite": "Satellite",
            "terminalAuto": "Terminal", "crane": "Crane", "yard": "Yard",
            "dockSched": "Dock Scheduling", "workforce": "Workforce", "warehouse": "Warehouse",
            "customs": "Customs",
            "rate_market": "Rate Market", "macro_economic": "Macro Economic",
            "fuel_energy": "Fuel Energy", "agricultural": "Agricultural",
            "safety_compliance": "Safety Compliance",
            "payments_factoring": "Payments + Factoring",
            "carrier_vetting": "Carrier Vetting",
            "operational_eld": "ELD", "operational_fuel_card": "Fuel Card",
            "operational_maintenance": "Maintenance",
            "operational_tolls": "Tolls",
            "operational_payroll": "Payroll",
            "terminals_ports_drayage": "Terminals + Drayage",
            "tms_load_boards": "TMS + Load Boards",
            "documents_imaging": "Documents + Imaging",
            "identity_sso": "Identity + SSO",
            "geo_maps": "Maps + Routing",
            "observability": "Observability",
            "rail_class_i": "Class I Rail",
            "rail_industry_data": "Rail Industry",
            "rail_locomotive": "Rail Locomotive",
            "rail_crew": "Rail Crew",
            "ocean_carrier": "Ocean Carrier",
            "ocean_visibility": "Ocean Visibility",
            "ocean_charter": "Ocean Charter",
            "vessel_telematics": "Vessel Telematics",
            "vessel_bunker": "Vessel Bunker",
            "vessel_satcom": "Vessel Satcom",
            "customs_trade": "Customs + Trade",
        ]
        return map[raw] ?? prettyToken(raw)
    }

    // MARK: Server-issued provider fields

    private func inputKey(provider: String, kind: String, field: String) -> String {
        "\(provider).\(kind).\(field)"
    }

    private func connectFormReady(_ p: IntegrationProvider) -> Bool {
        guard p.canEstablishConnection, providerProvisioningReady(p) else { return false }
        if usesNativeOAuth(p) { return true }
        for field in p.credentialFields where field.required {
            if inputValue(provider: p.id, kind: "credential", field: field.key).isEmpty {
                return false
            }
        }
        for field in p.configurationFields where field.required {
            if inputValue(provider: p.id, kind: "configuration", field: field.key).isEmpty {
                return false
            }
        }
        return inputRequirementSatisfied(p)
    }

    private func confirmationKey(provider: String, requirement: String) -> String {
        "\(provider)|\(requirement)"
    }

    private func customerConfirmationRequirements(
        _ provider: IntegrationProvider
    ) -> [IntegrationProvisioningRequirement] {
        (provider.provisioning?.requirements ?? []).filter {
            $0.owner == "customer" && $0.verification == "user_confirmation"
        }
    }

    private func confirmedRequirementKeys(for provider: IntegrationProvider) -> [String] {
        customerConfirmationRequirements(provider).compactMap { requirement in
            let key = confirmationKey(provider: provider.id, requirement: requirement.key)
            return confirmedProvisioningRequirements.contains(key) ? requirement.key : nil
        }
    }

    private func providerProvisioningReady(_ provider: IntegrationProvider) -> Bool {
        guard provider.connectable,
              provider.canEstablishConnection,
              let requirements = provider.provisioning?.requirements,
              !requirements.isEmpty else { return false }
        let requiredConfirmations = customerConfirmationRequirements(provider)
        return requiredConfirmations.allSatisfy { requirement in
            confirmedProvisioningRequirements.contains(
                confirmationKey(provider: provider.id, requirement: requirement.key)
            )
        }
    }

    private func inputValue(provider: String, kind: String, field: String) -> String {
        (credInputs[inputKey(provider: provider, kind: kind, field: field)] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func activationPayload(
        for provider: IntegrationProvider
    ) throws -> (
        credentials: [String: IntegrationActivationValue],
        configuration: [String: IntegrationActivationValue]
    ) {
        var credentials: [String: IntegrationActivationValue] = [:]
        for field in provider.credentialFields {
            let key = inputKey(provider: provider.id, kind: "credential", field: field.key)
            guard let raw = credInputs[key], !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            credentials[field.key] = try activationValue(raw, field: field)
        }

        var configuration: [String: IntegrationActivationValue] = [:]
        for field in provider.configurationFields {
            let key = inputKey(provider: provider.id, kind: "configuration", field: field.key)
            guard let raw = credInputs[key], !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            configuration[field.key] = try activationValue(raw, field: field)
        }
        return (credentials, configuration)
    }

    private func activationValue(
        _ raw: String,
        field: IntegrationInputField
    ) throws -> IntegrationActivationValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field.inputType.lowercased() {
        case "number":
            guard let value = Double(trimmed), value.isFinite else {
                throw IntegrationActivationInputError.invalid(
                    field: field.label,
                    requirement: "must be a finite number"
                )
            }
            return .number(value)
        case "csv":
            let values = trimmed
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !values.isEmpty else {
                throw IntegrationActivationInputError.invalid(
                    field: field.label,
                    requirement: "must contain at least one text value"
                )
            }
            return .array(values.map(IntegrationActivationValue.string))
        case "json":
            do {
                let decoded = try JSONSerialization.jsonObject(with: Data(trimmed.utf8))
                guard decoded is [String: Any] || decoded is [Any] else {
                    throw IntegrationActivationInputError.invalid(
                        field: field.label,
                        requirement: "must be a JSON object or array"
                    )
                }
                return try jsonActivationValue(decoded, fieldLabel: field.label)
            } catch let error as IntegrationActivationInputError {
                throw error
            } catch {
                throw IntegrationActivationInputError.invalid(
                    field: field.label,
                    requirement: "must be valid JSON data"
                )
            }
        case "url":
            guard let components = URLComponents(string: trimmed),
                  components.scheme?.lowercased() == "https",
                  components.host != nil,
                  components.user == nil,
                  components.password == nil,
                  let url = components.url else {
                throw IntegrationActivationInputError.invalid(
                    field: field.label,
                    requirement: "must be an HTTPS URL without embedded credentials"
                )
            }
            return .string(url.absoluteString)
        case "email":
            guard trimmed.range(
                of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#,
                options: .regularExpression
            ) != nil else {
                throw IntegrationActivationInputError.invalid(
                    field: field.label,
                    requirement: "must be a valid email address"
                )
            }
            return .string(trimmed)
        case "certificate", "private_key":
            try validateActivationStringSize(raw, field: field)
            return .string(raw)
        case "text", "secret":
            try validateActivationStringSize(trimmed, field: field)
            return .string(trimmed)
        default:
            throw IntegrationActivationInputError.invalid(
                field: field.label,
                requirement: "uses an unsupported field type"
            )
        }
    }

    private func validateActivationStringSize(
        _ value: String,
        field: IntegrationInputField
    ) throws {
        guard value.lengthOfBytes(using: .utf8) <= 32 * 1024 else {
            throw IntegrationActivationInputError.invalid(
                field: field.label,
                requirement: "exceeds the allowed size"
            )
        }
    }

    private func jsonActivationValue(
        _ value: Any,
        fieldLabel: String
    ) throws -> IntegrationActivationValue {
        if value is NSNull { return .null }
        if let dictionary = value as? [String: Any] {
            return .object(try dictionary.mapValues {
                try jsonActivationValue($0, fieldLabel: fieldLabel)
            })
        }
        if let array = value as? [Any] {
            return .array(try array.map {
                try jsonActivationValue($0, fieldLabel: fieldLabel)
            })
        }
        if let string = value as? String { return .string(string) }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let double = number.doubleValue
            guard double.isFinite else {
                throw IntegrationActivationInputError.invalid(
                    field: fieldLabel,
                    requirement: "contains a non-finite number"
                )
            }
            return .number(double)
        }
        throw IntegrationActivationInputError.invalid(
            field: fieldLabel,
            requirement: "contains an unsupported JSON value"
        )
    }

    private func inputRequirementSatisfied(_ provider: IntegrationProvider) -> Bool {
        guard let requirement = provider.inputRequirement else { return true }
        guard requirement.mode == "any_of", !requirement.alternatives.isEmpty else { return false }
        return requirement.alternatives.contains { alternative in
            alternative.credentials.allSatisfy {
                !inputValue(provider: provider.id, kind: "credential", field: $0).isEmpty
            } && (alternative.configuration ?? []).allSatisfy {
                !inputValue(provider: provider.id, kind: "configuration", field: $0).isEmpty
            }
        }
    }

    private func inputFieldLabel(_ key: String, provider: IntegrationProvider) -> String {
        (provider.credentialFields + provider.configurationFields)
            .first(where: { $0.key == key })?.label ?? prettyToken(key)
    }

    private func usesNativeOAuth(_ provider: IntegrationProvider) -> Bool {
        guard provider.authType?.lowercased() == "oauth2" else { return false }
        return provider.capabilities.perUserOAuth
    }

    private func providerServerActivationRequirement(_ provider: IntegrationProvider) -> String {
        let verification = provider.activationVerification ?? provider.connectionVerification
        guard provider.connectable,
              provider.provisioning != nil,
              verification != nil else {
            return "Provider requirements or the verification path are incomplete, so activation remains unavailable."
        }
        return "Connection is activated only after \(connectionVerificationLabel(verification).lowercased()) succeeds and current connection evidence confirms activation, usability, access, and ownership."
    }

    private func providerCredentialGuidance(_ p: IntegrationProvider) -> String {
        let provider = cleanLabel(p.vendor ?? p.displayName)
        if !p.connectable {
            return p.blockedReason.map { cleanLabel($0) }
                ?? "\(provider) is unavailable because the live catalog does not publish a production activation path."
        }
        if !p.canEstablishConnection {
            return p.establishmentBlockedReason.map { cleanLabel($0) }
                ?? "An authorized company credential custodian must establish this shared connection."
        }
        guard let provisioning = p.provisioning, !provisioning.requirements.isEmpty else {
            return "The live catalog does not publish a complete provisioning contract. Credential entry and provider authorization remain locked."
        }
        if usesNativeOAuth(p) {
            return "Confirm the company prerequisites, then authorize \(provider) in its secure provider session. Activation is not claimed until the signed callback and current activation evidence both confirm it."
        }
        if provisioning.mode == "customer_account_approval" {
            return "Use only credentials issued after \(provider) approves your company account. EusoTrip activates only after live verification and the required activation evidence succeed."
        }
        if provisioning.mode == "commercial_contract" {
            return "Use only credentials issued after your company completes its \(provider) agreement. EusoTrip activates only after live verification succeeds."
        }
        if p.requiresCredentials == false {
            return "The live catalog requests no credential. EusoTrip still activates only after \(connectionVerificationLabel(p.activationVerification ?? p.connectionVerification).lowercased()) and current activation evidence confirm readiness."
        }
        return "Enter provider-issued credentials after completing the company prerequisites. They are cleared from iOS after this attempt; activation is claimed only after \(connectionVerificationLabel(p.activationVerification ?? p.connectionVerification).lowercased()) and current activation evidence confirm readiness."
    }
}

/// A multiline secure editor for PEM certificates and private keys. Values
/// remain masked on screen, preserve line breaks, and are cleared after each
/// connection attempt by the owning screen.
private struct SensitiveMultilineTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textColor = .label
        view.tintColor = .systemBlue
        view.isSecureTextEntry = true
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.textContentType = .password
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            view.text = text
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SensitiveMultilineTextEditor

        init(parent: SensitiveMultilineTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}

// MARK: - Scope chips (bespoke wrap layout)

private struct FlowScopes: View {
    let scopes: [ApiScope]
    @Binding var selected: Set<String>
    let palette: Theme.Palette

    var body: some View {
        // Simple wrapping chip grid.
        let cols = [GridItem(.adaptive(minimum: 110), spacing: 6)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
            ForEach(scopes) { s in
                let on = selected.contains(s.scope)
                Button {
                    if on { selected.remove(s.scope) } else { selected.insert(s.scope) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                        Text(s.scope).font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(on ? palette.textPrimary : palette.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }
}

#Preview("346 · Connected apps · Night") { ConnectedAppsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("346 · Connected apps · Afternoon") { ConnectedAppsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
