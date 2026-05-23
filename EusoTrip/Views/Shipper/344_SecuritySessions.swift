//
//  344_SecuritySessions.swift
//  EusoTrip — Shipper · Active sessions (Arc K).
//
//  Reshaped 2026-05-23 with a single REVOKE drop tile above the
//  session list. Drag any non-current session card onto the tile
//  to fire auth.revokeSession in one gesture. The CURRENT-DEVICE
//  card is non-draggable (you can't revoke the session you're
//  using; same constraint the per-card button enforces).
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
    @State private var lastRevoked: String? = nil
    @State private var dropHover: Bool = false
    @State private var draggingSessionId: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let m = lastRevoked {
                    LifecycleCard(accentGradient: true) {
                        Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                if !sessions.isEmpty { revokeDropZone }
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · ACTIVE SESSIONS · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Active sessions")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Drag a non-current session card onto REVOKE to kill it. Current device can't be revoked from itself.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var revokeDropZone: some View {
        let hoveringSession = draggingSessionId.flatMap { id in sessions.first(where: { $0.id == id }) }
        return HStack(spacing: 10) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Brand.danger)
                .frame(width: 38, height: 38)
                .background(palette.bgCardSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("REVOKE SESSION")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
                if dropHover, let s = hoveringSession {
                    Text("Release to kill \(s.device ?? "this device")")
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .lineLimit(2)
                } else {
                    Text("Drop a session card here to terminate it immediately.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if revoking != nil {
                ProgressView().scaleEffect(0.8)
            } else {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(dropHover ? Brand.danger : palette.textTertiary)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    dropHover ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(Brand.danger.opacity(0.3)),
                    lineWidth: dropHover ? 2 : 1
                )
                .animation(.easeOut(duration: 0.12), value: dropHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let sid = droppedIds.first else { return false }
            guard let session = sessions.first(where: { $0.id == sid }) else { return false }
            guard session.isCurrent != true else { return false }
            Task { await revoke(sid) }
            return true
        } isTargeted: { hovering in
            dropHover = hovering
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
                if s.isCurrent == true {
                    sessionCard(s)
                } else {
                    sessionCard(s)
                        .draggable(s.id) {
                            sessionCard(s)
                                .frame(maxWidth: 320)
                                .opacity(0.92)
                                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                        }
                        .onDrag {
                            draggingSessionId = s.id
                            return NSItemProvider(object: s.id as NSString)
                        }
                }
            }
        }
    }

    private func sessionCard(_ s: ActiveSession) -> some View {
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
                            .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Brand.danger).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(revoking != nil)
            } else {
                Text("CURRENT DEVICE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
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
        await MainActor.run { revoking = id; revokeError = nil }
        let label = sessions.first(where: { $0.id == id })?.device ?? "session \(id)"
        struct In: Encodable { let id: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("auth.revokeSession", input: In(id: id))
            await MainActor.run {
                lastRevoked = "\(label) → REVOKED"
                draggingSessionId = nil
            }
            await load()
        } catch let apiErr as EusoTripAPIError {
            await MainActor.run { revokeError = apiErr.errorDescription ?? "Couldn't revoke this session." }
        } catch {
            await MainActor.run { revokeError = error.localizedDescription }
        }
        await MainActor.run { revoking = nil }
    }
}

#Preview("344 · Sessions · Night") { SecuritySessionsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("344 · Sessions · Afternoon") { SecuritySessionsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
