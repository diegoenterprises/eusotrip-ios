//
//  346_ConnectedApps.swift
//  EusoTrip — Shipper · Connected apps + API tokens (Arc K).
//

import SwiftUI

struct ConnectedAppsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ConnectedAppsBody() } nav: { shipperLifecycleNav() }
    }
}

private struct ConnectedApp: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let scopes: [String]?
    let lastUsedAt: String?
    let createdAt: String?
}

private struct ConnectedAppsBody: View {
    @Environment(\.palette) private var palette
    @State private var apps: [ConnectedApp] = []
    @State private var tokens: [ConnectedApp] = []
    @State private var loading = true
    @State private var revoking: String? = nil
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading connections…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else { connectedSection; tokensSection }
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
        }
    }

    @ViewBuilder
    private var connectedSection: some View {
        if apps.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "CONNECTED APPS", icon: "rectangle.connected.to.line.below")
                Text("No third-party apps authorized.").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        } else {
            LifecycleCard {
                LifecycleSection(label: "CONNECTED APPS", icon: "rectangle.connected.to.line.below")
                ForEach(apps) { row(app: $0, kind: "app") }
            }
        }
    }

    @ViewBuilder
    private var tokensSection: some View {
        if tokens.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "API TOKENS", icon: "key")
                Text("No API tokens issued. Create them on the web shipper page.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            LifecycleCard {
                LifecycleSection(label: "API TOKENS", icon: "key")
                ForEach(tokens) { row(app: $0, kind: "token") }
            }
        }
    }

    private func row(app: ConnectedApp, kind: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("Last used \(humanISO(app.lastUsedAt))").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    if let scopes = app.scopes, !scopes.isEmpty {
                        Text(scopes.joined(separator: ", ")).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Button { Task { await revoke(app.id, kind: kind) } } label: {
                    HStack {
                        if revoking == app.id { ProgressView().tint(.white) }
                        Text(revoking == app.id ? "Revoking…" : "Revoke").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Brand.danger).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(revoking != nil)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            async let a: [ConnectedApp] = EusoTripAPI.shared.queryNoInput("auth.listConnectedApps")
            async let t: [ConnectedApp] = EusoTripAPI.shared.queryNoInput("auth.listApiTokens")
            apps = (try? await a) ?? []
            tokens = (try? await t) ?? []
        }
        loading = false
    }

    private func revoke(_ id: String, kind: String) async {
        revoking = id
        struct In: Encodable { let id: String }
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation(kind == "app" ? "auth.revokeConnectedApp" : "auth.revokeApiToken", input: In(id: id))
            await load()
        } catch { /* surface inline */ }
        revoking = nil
    }
}

#Preview("346 · Connected apps · Night") { ConnectedAppsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("346 · Connected apps · Afternoon") { ConnectedAppsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
