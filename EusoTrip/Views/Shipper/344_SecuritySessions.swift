//
//  344_SecuritySessions.swift
//  EusoTrip — Shipper · Active sessions (Arc K).
//

import SwiftUI

struct SecuritySessionsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { SessionsBody() } nav: { shipperLifecycleNav() }
    }
}

private struct ActiveSession: Decodable, Identifiable, Hashable {
    let id: String
    let device: String?
    let location: String?
    let lastSeenAt: String?
    let isCurrent: Bool?
    let userAgent: String?
}

private struct SessionsBody: View {
    @Environment(\.palette) private var palette
    @State private var sessions: [ActiveSession] = []
    @State private var loading = true
    @State private var revoking: String? = nil
    @State private var loadError: String? = nil
    /// Inline revoke-error surface (was silently swallowed in the
    /// `/* surface inline */` catch, leaving the user thinking a
    /// stale session was killed when it wasn't).
    @State private var revokeError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · ACTIVE SESSIONS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Active sessions").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Devices currently signed in to this account.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let err = revokeError {
            LifecycleCard(accentDanger: true) {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if loading { LifecycleCard { Text("Loading sessions…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if sessions.isEmpty { LifecycleCard { Text("No active sessions on file.").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else {
            ForEach(sessions) { s in
                LifecycleCard(accentGradient: s.isCurrent == true) {
                    LifecycleSection(label: dashIfEmpty(s.device).uppercased(), icon: "iphone")
                    LifecycleRow(label: "Location",  value: dashIfEmpty(s.location))
                    LifecycleRow(label: "Last seen", value: humanISO(s.lastSeenAt))
                    LifecycleRow(label: "User agent", value: dashIfEmpty(s.userAgent))
                    if s.isCurrent != true {
                        Button { Task { await revoke(s.id) } } label: {
                            HStack {
                                if revoking == s.id { ProgressView().tint(.white) }
                                Text(revoking == s.id ? "Revoking…" : "Revoke session")
                                    .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Brand.danger).clipShape(Capsule())
                        }.buttonStyle(.plain).disabled(revoking != nil)
                    } else {
                        Text("CURRENT DEVICE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(LinearGradient.diagonal).clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [ActiveSession] = try await EusoTripAPI.shared.queryNoInput("auth.listSessions")
            sessions = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func revoke(_ id: String) async {
        revoking = id
        revokeError = nil
        struct In: Encodable { let id: String }
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("auth.revokeSession", input: In(id: id))
            await load()
        } catch let apiErr as EusoTripAPIError {
            revokeError = apiErr.errorDescription ?? "Couldn't revoke this session."
        } catch {
            revokeError = error.localizedDescription
        }
        revoking = nil
    }
}

#Preview("344 · Sessions · Night") { SecuritySessionsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("344 · Sessions · Afternoon") { SecuritySessionsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
