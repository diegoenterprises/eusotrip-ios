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
}

/// `userIntegrations.listConnections` row — one per (user, provider).
private struct IntegrationConnection: Decodable, Identifiable, Hashable {
    let id: Int
    let providerId: String
    let status: String?
    let lastSyncedAt: String?
    let lastError: String?
    let enabledAt: String?
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

private struct ConnectedAppsBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    // Catalog + connections (the role-based integration system).
    @State private var providers: [IntegrationProvider] = []
    @State private var connections: [IntegrationConnection] = []
    @State private var usedRegistryFallback = false

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
    private var roleOwnsIntegrations: Bool {
        let r = role.uppercased()
        if r.isEmpty { return false }
        if r == "ADMIN" || r == "SUPER_ADMIN" { return true }
        return r.contains("SHIPPER") || r.contains("CATALYST") || r.contains("BROKER")
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
                    connectedSection
                    adaptationSection
                    tokensSection
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.connected.to.line.below").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CONNECTED APPS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
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
            Text("Account-level API integrations are managed by your shipper, carrier, or broker account. Your current role doesn't own these connections.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Connected apps / role-based integration catalog

    @ViewBuilder
    private var connectedSection: some View {
        LifecycleCard {
            LifecycleSection(label: "CONNECTED APPS", icon: "rectangle.connected.to.line.below")

            let connectedCount = connections.filter { ($0.status ?? "").lowercased() != "disabled" }.count
            Text(connectedCount == 0
                 ? "No integrations connected yet. Pick a provider below to connect."
                 : "\(connectedCount) connected · \(providers.count) available for your role")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if usedRegistryFallback {
                Text("Showing the provider catalog for your role. Connect a provider to begin syncing.")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if providers.isEmpty {
                Text("No providers are mapped to your role yet.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                ForEach(providers) { providerRow($0) }
            }
        }
    }

    @ViewBuilder
    private func providerRow(_ p: IntegrationProvider) -> some View {
        let conn = connections.first { $0.providerId == p.id && ($0.status ?? "").lowercased() != "disabled" }
        let isConnected = conn != nil
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
                    if isConnected {
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
    private func connectedStatusLine(_ conn: IntegrationConnection?) -> some View {
        let status = (conn?.status ?? "active").lowercased()
        let isError = status == "error" || (conn?.lastError?.isEmpty == false)
        HStack(spacing: 5) {
            Circle().fill(isError ? Brand.danger : Brand.success).frame(width: 6, height: 6)
            Text(isError ? "Connected · sync error" : "Connected")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(isError ? Brand.danger : Brand.success)
            if let synced = conn?.lastSyncedAt, !synced.isEmpty {
                Text("· last sync \(humanISO(synced))").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
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
                pillButton(title: busy ? "Syncing…" : "Sync", filled: false, busy: busy) {
                    Task { await sync(conn) }
                }
                pillButton(title: busy ? "…" : "Disconnect", filled: false, danger: true, busy: false) {
                    Task { await disconnect(conn) }
                }
            } else {
                pillButton(title: isExpanded ? "Cancel" : "Connect", filled: !isExpanded, busy: false) {
                    if isExpanded {
                        expandedProvider = nil
                    } else if (p.requiresCredentials ?? false) {
                        expandedProvider = p.id
                    } else {
                        // Public provider — connect with no credentials.
                        Task { await connect(p, credentials: nil) }
                    }
                }
            }
        }
    }

    /// Inline credential entry (push-nav style in-flow disclosure — not a slide-up sheet).
    @ViewBuilder
    private func connectForm(_ p: IntegrationProvider, busy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter the credentials \(cleanLabel(p.displayName)) issued you. They're stored encrypted and never shown again.")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(credentialFields(for: p), id: \.self) { field in
                credField(provider: p.id, field: field)
            }

            // Provider reference. The registry/catalog records deep doc
            // paths (…/api, …/developers, …/api-portal) that frequently 404
            // because providers don't host docs at those exact constructed
            // URLs. Rather than ship a link we can't verify resolves, we open
            // ONLY the provider's root domain (scheme + host) — which reliably
            // loads — and label it honestly as the provider's site. When no
            // host can be parsed, we drop the link entirely and show an inline
            // note so the user is never sent to a 404.
            if let host = providerHost(from: p.docsUrl), let url = URL(string: "https://\(host)") {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "safari").font(.system(size: 9, weight: .semibold))
                        Text("Open \(host)").font(.system(size: 10, weight: .semibold))
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
                        for field in credentialFields(for: p) {
                            let v = credInputs["\(p.id).\(field.key)"] ?? ""
                            if !v.isEmpty { creds[field.key] = v }
                        }
                        await connect(p, credentials: creds.isEmpty ? nil : creds)
                    }
                }
                .disabled(!connectFormReady(p) || busy)
                .opacity(connectFormReady(p) ? 1 : 0.5)
            }
        }
        .padding(.top, 4)
    }

    private func credField(provider: String, field: CredentialField) -> some View {
        let bindingKey = "\(provider).\(field.key)"
        return VStack(alignment: .leading, spacing: 3) {
            Text(field.label.uppercased())
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                if field.secure {
                    SecureField(field.placeholder, text: Binding(
                        get: { credInputs[bindingKey] ?? "" },
                        set: { credInputs[bindingKey] = $0 }))
                } else {
                    TextField(field.placeholder, text: Binding(
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
        let items = session.user?.integrationMenuItems ?? []
        let caps = session.user?.profileAdaptation?.capabilities ?? []
        let surfaces = session.user?.profileAdaptation?.roleSurfaces ?? []
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
        loading = true; loadError = nil
        let api = EusoTripAPI.shared

        async let cat: [IntegrationProvider] = api.queryNoInput("userIntegrations.listCatalog")
        async let cons: [IntegrationConnection] = api.queryNoInput("userIntegrations.listConnections")
        async let keys: [ApiKeyRow] = api.queryNoInput("devPortal.apiKeys.list")
        async let scopeRows: [ApiScope] = api.queryNoInput("devPortal.mcpTools.getScopes")

        let catalog = (try? await cat) ?? []
        connections = (try? await cons) ?? []
        apiKeys = (try? await keys) ?? []
        scopes = (try? await scopeRows) ?? []

        if catalog.isEmpty && roleOwnsIntegrations {
            // Honest fallback: surface the doc-verified registry catalog for the
            // role so an integration-owning user is never shown a blank screen.
            providers = RoleIntegrationRegistry.providers(for: role).map { reg in
                IntegrationProvider(
                    id: reg.slug,
                    displayName: reg.name,
                    vendor: reg.function,
                    category: reg.category.rawValue,
                    description: reg.function,
                    docsUrl: reg.docs,
                    authType: "credentials",
                    status: nil,
                    capabilities: nil,
                    requiresCredentials: true)
            }
            usedRegistryFallback = !providers.isEmpty
        } else {
            providers = catalog
            usedRegistryFallback = false
        }

        loading = false
    }

    private func connect(_ p: IntegrationProvider, credentials: [String: String]?) async {
        busyProvider = p.id; actionError = nil
        struct In: Encodable { let providerId: String; let config: [String: String]; let credentials: [String: String]? }
        // Tolerant: provider.connect() return shapes vary by provider, so we
        // only need a successful round-trip, not a specific field.
        struct Out: Decodable {}
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "userIntegrations.connect",
                input: In(providerId: p.id, config: [:], credentials: credentials))
            expandedProvider = nil
            // Clear typed credentials from memory once submitted.
            for field in credentialFields(for: p) { credInputs["\(p.id).\(field.key)"] = nil }
            await refreshConnections()
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
        // Note: the INTEGRATION UNLOCKS card reads the profileAdaptation envelope
        // folded into auth.me; it re-composes on the next identity refresh
        // (app relaunch / next auth.me round-trip). Connection state above
        // updates immediately so connect/disconnect/sync feel live.
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

    /// Reduce a recorded doc URL to its bare host (no scheme, no path) so we
    /// only ever link to the provider's root domain — which resolves — instead
    /// of a constructed deep path (…/api, …/developers) that 404s. Returns nil
    /// when the value has no parseable host (so the caller shows an inline note
    /// instead of a dead link). Display-layer only; never invents a host.
    private func providerHost(from raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let comps = URLComponents(string: raw),
              let host = comps.host, !host.isEmpty else { return nil }
        return host.lowercased()
    }

    /// Turn a raw machine token ("FUEL_BUYER", "bulk-liquid") into a readable label.
    private func prettyToken(_ s: String) -> String {
        let spaced = s.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return spaced.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
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
        ]
        return map[raw] ?? prettyToken(raw)
    }

    // MARK: Credential field inference

    private struct CredentialField: Hashable {
        let key: String
        let label: String
        let placeholder: String
        let secure: Bool
    }

    /// Best-effort credential prompt set per provider auth type. The server's
    /// provider.connect() is the authority on what it needs; this surfaces the
    /// common shapes (API key / OAuth client / basic) so the user can supply
    /// real credentials in-app rather than being told to "use the web."
    private func credentialFields(for p: IntegrationProvider) -> [CredentialField] {
        switch (p.authType ?? "credentials").lowercased() {
        case "oauth", "oauth2":
            return [
                .init(key: "clientId", label: "Client ID", placeholder: "Client ID", secure: false),
                .init(key: "clientSecret", label: "Client secret", placeholder: "Client secret", secure: true),
            ]
        case "basic":
            return [
                .init(key: "username", label: "Username", placeholder: "Username", secure: false),
                .init(key: "password", label: "Password", placeholder: "Password", secure: true),
            ]
        default:
            return [
                .init(key: "apiKey", label: "API key", placeholder: "Paste your API key", secure: true),
            ]
        }
    }

    private func connectFormReady(_ p: IntegrationProvider) -> Bool {
        for field in credentialFields(for: p) {
            if (credInputs["\(p.id).\(field.key)"] ?? "").isEmpty { return false }
        }
        return true
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
