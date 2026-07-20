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
//      user's own connection state). Connect / disconnect / sync run in-app
//      via `userIntegrations.connect` / `.disconnect` / `.sync`. When the
//      server catalog is empty/unreachable we fall back to the doc-verified
//      `RoleIntegrationRegistry` so an integration-owning role is NEVER shown
//      a blank "go to the web page" dead-end — it sees the real provider list.
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
//  Surfaces only for integration-OWNING roles (SHIPPER / CATALYST / BROKER
//  families across truck / rail / vessel, plus ADMIN); operator/driver roles
//  get an honest, graceful explanation rather than an empty placeholder.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct ConnectedAppsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ConnectedAppsBody() } nav: { shipperLifecycleNav() }
    }
}

// MARK: - Wire DTOs (byte-identical to the server contract)

private struct IntegrationInputField: Decodable, Hashable {
    let key: String
    let label: String
    let inputType: String
    let required: Bool
    let secret: Bool
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
    let capabilities: [String]?
    let requiresCredentials: Bool?
    let credentialFields: [IntegrationInputField]
    let configurationFields: [IntegrationInputField]
    let connectable: Bool
    let blockedReason: String?
    let supportsSync: Bool?
    let syncIntervalMinutes: Int?
    let journey: IntegrationProviderJourney?

    enum CodingKeys: String, CodingKey {
        case id, displayName, vendor, category, description, docsUrl, authType, status
        case capabilities, requiresCredentials, credentialFields, configurationFields
        case connectable, blockedReason, supportsSync, syncIntervalMinutes, journey
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
        requiresCredentials = try c.decodeIfPresent(Bool.self, forKey: .requiresCredentials)
        credentialFields = try c.decodeIfPresent([IntegrationInputField].self, forKey: .credentialFields) ?? []
        configurationFields = try c.decodeIfPresent([IntegrationInputField].self, forKey: .configurationFields) ?? []
        connectable = try c.decodeIfPresent(Bool.self, forKey: .connectable) ?? false
        blockedReason = try c.decodeIfPresent(String.self, forKey: .blockedReason)
        supportsSync = try c.decodeIfPresent(Bool.self, forKey: .supportsSync)
        syncIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .syncIntervalMinutes)
        journey = try c.decodeIfPresent(IntegrationProviderJourney.self, forKey: .journey)

        if let arr = try? c.decodeIfPresent([String].self, forKey: .capabilities) {
            capabilities = arr
        } else if let flags = try? c.decodeIfPresent(ProviderCapabilityFlags.self, forKey: .capabilities) {
            capabilities = flags.enabledLabels
        } else {
            capabilities = nil
        }
    }
}

private struct ProviderCapabilityFlags: Decodable, Hashable {
    let inbound: Bool?
    let outbound: Bool?
    let webhooks: Bool?
    let realtime: Bool?
    let scheduledSync: Bool?
    let perUserOAuth: Bool?

    var enabledLabels: [String] {
        var labels: [String] = []
        if inbound == true { labels.append("Inbound") }
        if outbound == true { labels.append("Outbound") }
        if webhooks == true { labels.append("Webhooks") }
        if realtime == true { labels.append("Realtime") }
        if scheduledSync == true { labels.append("Scheduled sync") }
        if perUserOAuth == true { labels.append("User OAuth") }
        return labels
    }
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

/// `userIntegrations.listConnections` row — one per (user, provider).
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

    var effectiveFeedState: String {
        if let feedState, !feedState.isEmpty { return feedState.lowercased() }
        switch (status ?? "").lowercased() {
        case "connected": return "live"
        case "pending_credentials": return "credentials_required"
        default: return (status ?? "disabled").lowercased()
        }
    }

    var isOperational: Bool {
        if let isUsable { return isUsable }
        return ["live", "on_demand"].contains(effectiveFeedState)
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

private struct IntegrationJourneyImpact: Identifiable, Hashable {
    let id: String
    let title: String
    let outcome: String
    let icon: String
    let providerCount: Int
    let connectedCount: Int
    let providerNames: [String]
}

private struct IntegrationAdoptionSignal: Identifiable, Hashable {
    let id: String
    let title: String
    let outcome: String
    let icon: String
    let providerCount: Int
    let connectedCount: Int
    let providerNames: [String]
}

private struct IntegrationNetworkBenefit: Identifiable, Hashable {
    let id: String
    let recipient: String
    let benefit: String
    let icon: String
    let providerCount: Int
    let connectedCount: Int
    let providerNames: [String]
}

private struct ConnectedAppsBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    // Catalog + connections (the role-based integration system).
    @State private var providers: [IntegrationProvider] = []
    @State private var connections: [IntegrationConnection] = []
    @State private var liveAdaptation: ProfileAdaptation? = nil
    @State private var usedRegistryFallback = false
    @State private var catalogUnavailableReason: String? = nil

    // API tokens (the developer portal).
    @State private var apiKeys: [ApiKeyRow] = []
    @State private var scopes: [ApiScope] = []

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionError: String? = nil

    // Per-provider connect form state.
    @State private var expandedProvider: String? = nil
    @State private var credInputs: [String: String] = [:]   // "providerId.field" → value
    @State private var busyProvider: String? = nil

    // API-token issuance state.
    @State private var showIssueForm = false
    @State private var newKeyName = ""
    @State private var selectedScopes: Set<String> = []
    @State private var issuing = false
    @State private var freshlyIssuedKey: String? = nil      // shown once, then cleared
    @State private var revokingKey: String? = nil

    private var role: String { session.user?.role ?? "" }
    private var roleLabel: String { session.user?.roleEnum.displayName ?? "Account" }
    private var roleOwnsIntegrations: Bool {
        let r = role.uppercased()
        if r.isEmpty { return false }
        if r == "ADMIN" || r == "SUPER_ADMIN" { return true }
        return !RoleIntegrationRegistry.providers(for: r).isEmpty
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

                if loading {
                    LifecycleCard { Text("Loading your integrations…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !roleOwnsIntegrations {
                    nonIntegrationRoleCard
                } else {
                    integrationJourneySection
                    connectedSection
                    adaptationSection
                    tokensSection
                }

                Color.clear.frame(height: 156)
            }
            .padding(.horizontal, 14).padding(.top, 72)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.connected.to.line.below").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("\(roleLabel.uppercased()) · CONNECTED APPS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Connected apps + API tokens").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Connect the integrations that apply to your role, and issue API tokens — all in-app.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Non-integration role (honest, not a dead-end)

    private var nonIntegrationRoleCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CONNECTED APPS", icon: "rectangle.connected.to.line.below")
            Text("This role does not own account-level integrations. Ask an account admin to connect providers or issue API tokens.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Connected apps / role-based integration catalog

    @ViewBuilder
    private var integrationJourneySection: some View {
        let impacts = IntegrationJourneyPlanner.impacts(for: providers, connections: connections)
        let adoptionSignals = IntegrationJourneyPlanner.adoptionSignals(for: providers, connections: connections)
        let networkBenefits = IntegrationJourneyPlanner.networkBenefits(for: providers, connections: connections)
        if !impacts.isEmpty || !adoptionSignals.isEmpty || !networkBenefits.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "RIOS ADOPTION MAP", icon: "point.3.connected.trianglepath.dotted")

                Text("\(providers.count) role-mapped providers can shorten onboarding, enrich this account, and improve the counterparties who depend on this role.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !adoptionSignals.isEmpty {
                    journeySubhead("ONBOARDING ACCELERATORS")
                    ForEach(adoptionSignals) { signal in
                        adoptionSignalRow(signal)
                    }
                }

                if !networkBenefits.isEmpty {
                    journeyDivider
                    journeySubhead("CROSS-ROLE BENEFIT")
                    ForEach(networkBenefits) { benefit in
                        networkBenefitRow(benefit)
                    }
                }

                if !impacts.isEmpty {
                    journeyDivider
                    journeySubhead("WORKFLOW UNLOCKS")
                    ForEach(impacts) { impact in
                        journeyImpactRow(impact)
                    }
                }
            }
        }
    }

    private func journeySubhead(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .heavy))
            .tracking(0.7)
            .foregroundStyle(palette.textTertiary)
            .padding(.top, 4)
    }

    private var journeyDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(height: 1)
            .padding(.vertical, 2)
    }

    private func adoptionSignalRow(_ signal: IntegrationAdoptionSignal) -> some View {
        journeyMetricRow(
            icon: signal.icon,
            title: signal.title,
            body: signal.outcome,
            count: "\(signal.connectedCount)/\(signal.providerCount) connected",
            providerNames: signal.providerNames,
            providerCount: signal.providerCount,
            active: signal.connectedCount > 0)
    }

    private func networkBenefitRow(_ benefit: IntegrationNetworkBenefit) -> some View {
        journeyMetricRow(
            icon: benefit.icon,
            title: benefit.recipient,
            body: benefit.benefit,
            count: "\(benefit.connectedCount)/\(benefit.providerCount) connected",
            providerNames: benefit.providerNames,
            providerCount: benefit.providerCount,
            active: benefit.connectedCount > 0)
    }

    private func journeyImpactRow(_ impact: IntegrationJourneyImpact) -> some View {
        journeyMetricRow(
            icon: impact.icon,
            title: impact.title,
            body: impact.outcome,
            count: "\(impact.connectedCount)/\(impact.providerCount) connected",
            providerNames: impact.providerNames,
            providerCount: impact.providerCount,
            active: impact.connectedCount > 0)
    }

    private func journeyMetricRow(
        icon: String,
        title: String,
        body: String,
        count: String,
        providerNames: [String],
        providerCount: Int,
        active: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(title)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 8)
                        Text(count)
                            .font(EType.mono(.micro))
                            .foregroundStyle(active ? Brand.success : palette.textTertiary)
                    }
                    Text(body)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    providerNameLine(providerNames, total: providerCount)
                }
            }
        }
        .padding(.vertical, 6)
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

            let connectedCount = connections.filter(\.isOperational).count
            Text(connectedCount == 0
                 ? "No integrations connected yet. Pick a provider below to connect."
                 : "\(connectedCount) connected · \(providers.count) available for your role")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if usedRegistryFallback {
                Text("Live provider catalog is temporarily unavailable.")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = catalogUnavailableReason, !reason.isEmpty {
                    Text(reason)
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
            }

            if providers.isEmpty {
                if usedRegistryFallback {
                    pillButton(title: "Retry catalog", filled: false, busy: loading) {
                        Task { await load() }
                    }
                } else {
                    Text("No providers are mapped to your role yet.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                ForEach(providers) { providerRow($0) }
            }
        }
    }

    @ViewBuilder
    private func providerRow(_ p: IntegrationProvider) -> some View {
        let conn = connections.first { $0.providerId == p.id && ($0.status ?? "").lowercased() != "disabled" }
        let isConnected = conn.map { ["live", "stale", "on_demand", "connecting"].contains($0.effectiveFeedState) } ?? false
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
                        if let url = providerDocsURL(from: p.docsUrl) {
                            Link(destination: url) {
                                Label("Provider details", systemImage: "safari")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Brand.blue)
                            }
                        }
                    }
                    if conn != nil {
                        connectedStatusLine(conn)
                    }
                }
                Spacer(minLength: 8)
                providerActions(p, isConnected: isConnected, conn: conn, isExpanded: isExpanded, busy: busy)
            }

            if isExpanded && !isConnected {
                connectForm(p, busy: busy)
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if p.id != providers.last?.id {
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
    private func connectedStatusLine(_ conn: IntegrationConnection?) -> some View {
        let state = conn?.effectiveFeedState ?? "disabled"
        let isError = state == "error"
        let isWarning = state == "stale" || state == "credentials_required"
        let color = isError ? Brand.danger : isWarning ? Brand.warning : state == "connecting" ? Brand.blue : Brand.success
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(feedStateLabel(state))
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
    }

    @ViewBuilder
    private func providerActions(_ p: IntegrationProvider, isConnected: Bool, conn: IntegrationConnection?, isExpanded: Bool, busy: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if isConnected {
                if p.supportsSync == true && conn?.effectiveFeedState != "connecting" {
                    pillButton(title: busy ? "Syncing…" : "Sync", filled: false, busy: busy) {
                        Task { await sync(conn) }
                    }
                }
                pillButton(title: busy ? "…" : "Disconnect", filled: false, danger: true, busy: false) {
                    Task { await disconnect(conn) }
                }
            } else {
                if !p.connectable {
                    pillButton(title: "Setup required", filled: false, busy: false) {}
                        .disabled(true)
                } else {
                    pillButton(title: isExpanded ? "Cancel" : "Connect", filled: !isExpanded, busy: false) {
                        if isExpanded {
                            expandedProvider = nil
                        } else if !p.credentialFields.isEmpty || !p.configurationFields.isEmpty {
                            expandedProvider = p.id
                        } else {
                            // Public provider — connect with no credentials.
                            Task { await connect(p, credentials: nil, configuration: [:]) }
                        }
                    }
                }
            }
        }
    }

    /// Inline credential entry (push-nav style in-flow disclosure — not a slide-up sheet).
    @ViewBuilder
    private func connectForm(_ p: IntegrationProvider, busy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter the credentials \(cleanLabel(p.displayName)) issued to you. They're stored encrypted and never shown again.")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            providerJourneyDisclosure(p)

            if !p.credentialFields.isEmpty {
                Text("CREDENTIALS")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            ForEach(p.credentialFields, id: \.self) { field in
                providerInputField(provider: p.id, kind: "credential", field: field)
            }

            if !p.configurationFields.isEmpty {
                Text("CONNECTION SETTINGS")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            ForEach(p.configurationFields, id: \.self) { field in
                providerInputField(provider: p.id, kind: "configuration", field: field)
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
                Text("Credentials are issued from your \(cleanLabel(p.displayName)) account — generate an API key there, then paste it above.")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Get your API credentials from your \(cleanLabel(p.displayName)) account or admin, then paste them above.")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                pillButton(title: busy ? "Connecting…" : "Connect provider", filled: true, busy: busy) {
                    Task {
                        var creds: [String: String] = [:]
                        for field in p.credentialFields {
                            let v = credInputs[inputKey(provider: p.id, kind: "credential", field: field.key)] ?? ""
                            if !v.isEmpty { creds[field.key] = v }
                        }
                        var configuration: [String: String] = [:]
                        for field in p.configurationFields {
                            let v = credInputs[inputKey(provider: p.id, kind: "configuration", field: field.key)] ?? ""
                            if !v.isEmpty { configuration[field.key] = v }
                        }
                        await connect(p, credentials: creds.isEmpty ? nil : creds, configuration: configuration)
                    }
                }
                .disabled(!connectFormReady(p) || busy)
                .opacity(connectFormReady(p) ? 1 : 0.5)
            }
        }
        .padding(.top, 4)
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
                if field.secret || field.inputType == "secret" || field.inputType == "private_key" {
                    SecureField(field.label, text: Binding(
                        get: { credInputs[bindingKey] ?? "" },
                        set: { credInputs[bindingKey] = $0 }))
                } else {
                    TextField(field.label, text: Binding(
                        get: { credInputs[bindingKey] ?? "" },
                        set: { credInputs[bindingKey] = $0 }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
            }
            .font(EType.mono(.caption))
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
    }

    // MARK: - Integration unlocks (live profileAdaptation envelope)

    @ViewBuilder
    private var adaptationSection: some View {
        let adaptation = liveAdaptation ?? session.user?.profileAdaptation
        let items = adaptation?.menuItems ?? []
        let caps = adaptation?.capabilities ?? []
        let surfaces = adaptation?.roleSurfaces ?? []
        if !items.isEmpty || !caps.isEmpty || !surfaces.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "INTEGRATION UNLOCKS", icon: "puzzlepiece.extension")
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

            if apiKeys.isEmpty {
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
            if scopes.isEmpty {
                Text("Scope catalog unavailable right now.").font(EType.caption).foregroundStyle(palette.textSecondary)
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
        loading = true; loadError = nil; catalogUnavailableReason = nil
        let api = EusoTripAPI.shared

        async let cat: Result<[IntegrationProvider], Error> = capture {
            try await api.queryNoInput("userIntegrations.listCatalog")
        }
        async let cons: [IntegrationConnection] = api.queryNoInput("userIntegrations.listConnections")
        async let keys: [ApiKeyRow] = api.queryNoInput("devPortal.apiKeys.list")
        async let scopeRows: [ApiScope] = api.queryNoInput("devPortal.mcpTools.getScopes")
        async let adaptationEnvelope = refreshProfileAdaptationEnvelope()

        let catalogResult = await cat
        let catalog: [IntegrationProvider]
        switch catalogResult {
        case .success(let rows):
            catalog = rows
        case .failure(let error):
            catalog = []
            catalogUnavailableReason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        connections = (try? await cons) ?? []
        apiKeys = (try? await keys) ?? []
        scopes = (try? await scopeRows) ?? []
        if let adaptation = await adaptationEnvelope {
            liveAdaptation = adaptation
        }

        providers = catalog
        usedRegistryFallback = catalog.isEmpty && catalogUnavailableReason != nil

        loading = false
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
        credentials: [String: String]?,
        configuration: [String: String]
    ) async {
        busyProvider = p.id; actionError = nil
        struct In: Encodable { let providerId: String; let config: [String: String]; let credentials: [String: String]? }
        // Tolerant: provider.connect() return shapes vary by provider, so we
        // only need a successful round-trip, not a specific field.
        struct Out: Decodable {}
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "userIntegrations.connect",
                input: In(providerId: p.id, config: configuration, credentials: credentials))
            expandedProvider = nil
            // Clear typed credentials from memory once submitted.
            for field in p.credentialFields {
                credInputs[inputKey(provider: p.id, kind: "credential", field: field.key)] = nil
            }
            for field in p.configurationFields {
                credInputs[inputKey(provider: p.id, kind: "configuration", field: field.key)] = nil
            }
            await refreshConnections()
            await refreshProfileAdaptation()
        } catch let e as EusoTripAPIError {
            actionError = e.errorDescription ?? "Couldn't connect \(cleanLabel(p.displayName))."
        } catch {
            actionError = error.localizedDescription
        }
        busyProvider = nil
    }

    private func disconnect(_ conn: IntegrationConnection?) async {
        guard let conn else { return }
        busyProvider = conn.providerId; actionError = nil
        struct In: Encodable { let connectionId: Int }
        struct Out: Decodable {}
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("userIntegrations.disconnect", input: In(connectionId: conn.id))
            await refreshConnections()
            await refreshProfileAdaptation()
        } catch let e as EusoTripAPIError {
            actionError = e.errorDescription ?? "Couldn't disconnect."
        } catch {
            actionError = error.localizedDescription
        }
        busyProvider = nil
    }

    private func sync(_ conn: IntegrationConnection?) async {
        guard let conn else { return }
        busyProvider = conn.providerId; actionError = nil
        struct In: Encodable { let connectionId: Int }
        struct Out: Decodable {}
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("userIntegrations.sync", input: In(connectionId: conn.id))
            await refreshConnections()
            await refreshProfileAdaptation()
        } catch let e as EusoTripAPIError {
            actionError = e.errorDescription ?? "Sync failed."
        } catch {
            actionError = error.localizedDescription
        }
        busyProvider = nil
    }

    private func issueToken() async {
        issuing = true; actionError = nil; freshlyIssuedKey = nil
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
        revokingKey = keyId; actionError = nil
        struct In: Encodable { let keyId: String }
        struct Out: Decodable { let success: Bool }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("devPortal.apiKeys.revoke", input: In(keyId: keyId))
            await refreshApiKeys()
        } catch let e as EusoTripAPIError {
            actionError = e.errorDescription ?? "Couldn't revoke the token."
        } catch {
            actionError = error.localizedDescription
        }
        revokingKey = nil
    }

    private func refreshConnections() async {
        connections = (try? await EusoTripAPI.shared.queryNoInput("userIntegrations.listConnections")) ?? connections
    }

    private func refreshProfileAdaptation() async {
        if let adaptation = await refreshProfileAdaptationEnvelope() {
            liveAdaptation = adaptation
        }
    }

    private func refreshProfileAdaptationEnvelope() async -> ProfileAdaptation? {
        try? await EusoTripAPI.shared.queryNoInput("userIntegrations.profileAdaptation")
    }

    private func refreshApiKeys() async {
        apiKeys = (try? await EusoTripAPI.shared.queryNoInput("devPortal.apiKeys.list")) ?? apiKeys
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
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              url.host != nil else { return nil }
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
        switch state {
        case "live": return "Live"
        case "stale": return "Stale"
        case "on_demand": return "Ready on demand"
        case "error": return "Sync error"
        case "connecting": return "Connecting"
        case "credentials_required": return "Credentials needed"
        case "disabled": return "Disabled"
        default: return prettyToken(state)
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
        for field in p.credentialFields where field.required {
            if (credInputs[inputKey(provider: p.id, kind: "credential", field: field.key)] ?? "").isEmpty {
                return false
            }
        }
        for field in p.configurationFields where field.required {
            if (credInputs[inputKey(provider: p.id, kind: "configuration", field: field.key)] ?? "").isEmpty {
                return false
            }
        }
        return true
    }
}

private enum IntegrationJourneyPlanner {
    private struct Group {
        let id: String
        let title: String
        let outcome: String
        let icon: String
        let categories: Set<String>
    }

    private struct AdoptionGroup {
        let id: String
        let title: String
        let outcome: String
        let icon: String
        let categories: Set<String>
    }

    private struct NetworkGroup {
        let id: String
        let recipient: String
        let benefit: String
        let icon: String
        let categories: Set<String>
    }

    private static let groups: [Group] = [
        .init(
            id: "market",
            title: "Rates, tenders, and counterparties",
            outcome: "Price lanes, find capacity, and validate partners before a load is committed.",
            icon: "chart.line.uptrend.xyaxis",
            categories: keys(["rateData", "loadBoard", "marketIntel", "carrierVetting"])),
        .init(
            id: "live-ops",
            title: "Live operations",
            outcome: "Keep ETA, assignment, HOS, dispatch, and exception signals aligned with the trip.",
            icon: "dot.radiowaves.left.and.right",
            categories: keys(["visibility", "eld", "dispatch", "dashcam"])),
        .init(
            id: "route-risk",
            title: "Route risk and road spend",
            outcome: "Plan around roads, weather, tolls, fuel, parking, and maintenance conditions.",
            icon: "map",
            categories: keys(["nav", "weather", "toll", "fuelCard", "maintenance"])),
        .init(
            id: "money",
            title: "Money movement",
            outcome: "Tie receivables, payouts, fuel spend, factoring, banking, and coverage to the wallet.",
            icon: "creditcard",
            categories: keys(["payments", "banking", "factoring", "insurance"])),
        .init(
            id: "documents",
            title: "Documents and compliance",
            outcome: "Move BOL, POD, signatures, filings, eligibility, and safety records into the load file.",
            icon: "doc.text.magnifyingglass",
            categories: keys(["docs", "compliance", "customs", "identity", "bgScreening", "training"])),
        .init(
            id: "backoffice",
            title: "Back office systems",
            outcome: "Sync customers, orders, inventory, labor, warehouse, accounting, and TMS records.",
            icon: "building.2",
            categories: keys(["tms", "erp", "crm", "warehouse", "workforce"])),
        .init(
            id: "rail",
            title: "Rail execution",
            outcome: "Coordinate Class I, rail equipment, rail ops, release, crew, and interchange workflows.",
            icon: "tram",
            categories: keys(["railClassI", "railIndustry", "railEquip", "railOps"])),
        .init(
            id: "port-vessel",
            title: "Port and vessel execution",
            outcome: "Coordinate ocean booking, terminal, yard, berth, crane, bunker, vessel, and satellite signals.",
            icon: "ferry",
            categories: keys(["oceanBooking", "oceanCarrier", "oceanIntel", "marine", "bunker", "classSociety", "satcom", "satellite", "terminalAuto", "crane", "yard", "dockSched"]))
    ]

    private static let adoptionGroups: [AdoptionGroup] = [
        .init(
            id: "profile-import",
            title: "Profile and trust packet",
            outcome: "Pull authority, identity, insurance, safety, compliance, and eligibility records into onboarding instead of re-keying them.",
            icon: "person.crop.rectangle.stack",
            categories: keys(["carrierVetting", "compliance", "identity", "insurance", "bgScreening", "training"])),
        .init(
            id: "freight-import",
            title: "Freight setup import",
            outcome: "Bring customers, orders, SKUs, tenders, appointments, warehouse records, and TMS context into the first working session.",
            icon: "tray.and.arrow.down",
            categories: keys(["tms", "erp", "crm", "warehouse", "loadBoard", "oceanBooking", "railClassI", "railIndustry"])),
        .init(
            id: "ops-import",
            title: "Operations data capture",
            outcome: "Seed live location, HOS, equipment, routing, weather, terminal, and dispatch context before the user has to manually build it.",
            icon: "waveform.path.ecg",
            categories: keys(["visibility", "eld", "dispatch", "nav", "weather", "maintenance", "terminalAuto", "yard", "dockSched"])),
        .init(
            id: "money-import",
            title: "Wallet and settlement readiness",
            outcome: "Attach payment, banking, fuel, factoring, toll, and coverage rails so payout and spend workflows are usable quickly.",
            icon: "banknote",
            categories: keys(["payments", "banking", "fuelCard", "factoring", "toll", "insurance"])),
        .init(
            id: "docs-import",
            title: "Document packet readiness",
            outcome: "Connect BOL, POD, signatures, customs, certificates, permits, and audit evidence before a shipment is under pressure.",
            icon: "doc.badge.gearshape",
            categories: keys(["docs", "customs", "compliance", "classSociety"]))
    ]

    private static let networkGroups: [NetworkGroup] = [
        .init(
            id: "shipper-benefit",
            recipient: "Shippers get cleaner execution",
            benefit: "Connected ops, ELD, route, weather, docs, and payment providers reduce blind spots after tender.",
            icon: "shippingbox",
            categories: keys(["visibility", "eld", "dispatch", "nav", "weather", "docs", "payments", "carrierVetting"])),
        .init(
            id: "driver-benefit",
            recipient: "Drivers get less duplicate entry",
            benefit: "TMS, documents, wallet, fuel, route, weather, and compliance integrations pre-fill the work a driver would otherwise chase.",
            icon: "steeringwheel",
            categories: keys(["tms", "erp", "docs", "payments", "banking", "fuelCard", "nav", "weather", "compliance"])),
        .init(
            id: "dispatch-benefit",
            recipient: "Dispatch gets a real command surface",
            benefit: "Visibility, ELD, routing, toll, weather, maintenance, and load-board signals improve assignment quality and exception response.",
            icon: "person.2.wave.2",
            categories: keys(["visibility", "eld", "dispatch", "nav", "toll", "weather", "maintenance", "loadBoard", "carrierVetting"])),
        .init(
            id: "settlement-benefit",
            recipient: "Settlement moves faster",
            benefit: "Payments, banking, factoring, fuel, toll, document, POD, and signature providers shorten proof-to-pay cycles.",
            icon: "checkmark.seal",
            categories: keys(["payments", "banking", "factoring", "fuelCard", "toll", "docs"])),
        .init(
            id: "compliance-benefit",
            recipient: "Compliance sees fewer gaps",
            benefit: "Authority, customs, identity, safety, ELD, training, certification, and document connections keep regulated evidence attached to the trip.",
            icon: "shield.lefthalf.filled",
            categories: keys(["compliance", "customs", "identity", "bgScreening", "training", "eld", "docs", "classSociety"])),
        .init(
            id: "terminal-benefit",
            recipient: "Terminals and ports get smoother handoffs",
            benefit: "Terminal, yard, dock, warehouse, ocean, rail, customs, and workforce providers reduce appointment and release friction.",
            icon: "building.columns",
            categories: keys(["terminalAuto", "yard", "dockSched", "warehouse", "oceanBooking", "oceanCarrier", "railClassI", "railOps", "customs", "workforce"]))
    ]

    static func fallbackJourney(
        providerName: String,
        category: String,
        roleLabel: String,
        requiresCredentials: Bool
    ) -> IntegrationProviderJourney {
        let categoryKeys = resolvedCategoryKeys(category)
        let workflow = groups.first { !$0.categories.isDisjoint(with: categoryKeys) }
        let network = networkGroups.first { !$0.categories.isDisjoint(with: categoryKeys) }
        let adoption = adoptionGroups.first { !$0.categories.isDisjoint(with: categoryKeys) }
        let categoryName = pretty(category)
        return IntegrationProviderJourney(
            persona: roleLabel.lowercased(),
            adoptionStage: adoption != nil ? "onboard" : "operate",
            headline: "\(providerName) makes \(categoryName) part of the \(roleLabel) workspace.",
            setup: adoption?.outcome ?? "Connect the provider account that already owns this \(categoryName.lowercased()) data.",
            operationalUnlock: workflow?.outcome ?? "Adds verified provider data to the user's role-specific dashboard and workflows.",
            crossRoleBenefit: network?.benefit ?? "Connected provider data improves continuity for the counterparties who depend on this role.",
            credentialHint: requiresCredentials
                ? "Use provider-issued credentials dedicated to this RIOS connection; retry the live catalog before connecting if fields differ."
                : "No secret is required when the live provider catalog marks this as a public feed.",
            dataFlow: "Registry fallback until the live integration catalog responds.",
            capabilityTags: [categoryName, "Role mapped", "Retry catalog"])
    }

    static func impacts(for providers: [IntegrationProvider], connections: [IntegrationConnection]) -> [IntegrationJourneyImpact] {
        let liveConnections = liveConnectionIds(connections)

        return groups.compactMap { group in
            let matching = Self.providers(in: providers, matching: group.categories)
            guard !matching.isEmpty else { return nil }
            let connectedCount = matching.filter { liveConnections.contains($0.id.lowercased()) }.count
            return IntegrationJourneyImpact(
                id: group.id,
                title: group.title,
                outcome: group.outcome,
                icon: group.icon,
                providerCount: matching.count,
                connectedCount: connectedCount,
                providerNames: matching.map(\.displayName))
        }
    }

    static func adoptionSignals(for providers: [IntegrationProvider], connections: [IntegrationConnection]) -> [IntegrationAdoptionSignal] {
        let liveConnections = liveConnectionIds(connections)
        return adoptionGroups.compactMap { group in
            let matching = Self.providers(in: providers, matching: group.categories)
            guard !matching.isEmpty else { return nil }
            let connectedCount = matching.filter { liveConnections.contains($0.id.lowercased()) }.count
            return IntegrationAdoptionSignal(
                id: group.id,
                title: group.title,
                outcome: group.outcome,
                icon: group.icon,
                providerCount: matching.count,
                connectedCount: connectedCount,
                providerNames: matching.map(\.displayName))
        }
    }

    static func networkBenefits(for providers: [IntegrationProvider], connections: [IntegrationConnection]) -> [IntegrationNetworkBenefit] {
        let liveConnections = liveConnectionIds(connections)
        return networkGroups.compactMap { group in
            let matching = Self.providers(in: providers, matching: group.categories)
            guard !matching.isEmpty else { return nil }
            let connectedCount = matching.filter { liveConnections.contains($0.id.lowercased()) }.count
            return IntegrationNetworkBenefit(
                id: group.id,
                recipient: group.recipient,
                benefit: group.benefit,
                icon: group.icon,
                providerCount: matching.count,
                connectedCount: connectedCount,
                providerNames: matching.map(\.displayName))
        }
    }

    private static func providers(in providers: [IntegrationProvider], matching categoryKeys: Set<String>) -> [IntegrationProvider] {
        providers.filter { provider in
            guard let category = provider.category, !category.isEmpty else { return false }
            return !resolvedCategoryKeys(category).isDisjoint(with: categoryKeys)
        }
    }

    private static func liveConnectionIds(_ connections: [IntegrationConnection]) -> Set<String> {
        Set(
            connections
                .filter { ($0.status ?? "").lowercased() != "disabled" }
                .map { $0.providerId.lowercased() }
        )
    }

    private static func keys(_ values: [String]) -> Set<String> {
        Set(values.map(key))
    }

    private static func key(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func pretty(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private static func resolvedCategoryKeys(_ value: String) -> Set<String> {
        let rawKey = key(value)
        var keys = Set([rawKey])
        for alias in categoryAliases[rawKey] ?? [] {
            keys.insert(key(alias))
        }
        return keys
    }

    private static let categoryAliases: [String: [String]] = [
        key("rate_market"): ["rateData", "marketIntel"],
        key("macro_economic"): ["marketIntel", "rateData"],
        key("fuel_energy"): ["fuelCard", "marketIntel"],
        key("agricultural"): ["marketIntel"],
        key("safety_compliance"): ["compliance", "carrierVetting", "training", "bgScreening"],
        key("payments_factoring"): ["payments", "banking", "factoring"],
        key("operational_eld"): ["eld"],
        key("operational_fuel_card"): ["fuelCard"],
        key("operational_maintenance"): ["maintenance"],
        key("operational_tolls"): ["toll"],
        key("operational_payroll"): ["payments", "banking"],
        key("terminals_ports_drayage"): ["terminalAuto", "yard", "dockSched", "warehouse"],
        key("tms_load_boards"): ["tms", "loadBoard"],
        key("documents_imaging"): ["docs"],
        key("identity_sso"): ["identity"],
        key("geo_maps"): ["nav"],
        key("observability"): ["visibility"],
        key("rail_class_i"): ["railClassI"],
        key("rail_industry_data"): ["railIndustry"],
        key("rail_locomotive"): ["railOps"],
        key("rail_crew"): ["railOps", "workforce"],
        key("ocean_carrier"): ["oceanCarrier", "oceanBooking"],
        key("ocean_visibility"): ["oceanIntel", "visibility"],
        key("ocean_charter"): ["oceanBooking", "oceanIntel"],
        key("vessel_telematics"): ["marine"],
        key("vessel_bunker"): ["bunker"],
        key("vessel_satcom"): ["satcom", "satellite"],
        key("customs_trade"): ["customs"],
    ]
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
