//
//  706_DispatchDriverChat.swift
//  EusoTrip — Dispatch · Driver chat (conversations + send message).
//

import SwiftUI

struct DispatchDriverChatScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ChatBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct Conversation: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let lastMessage: String?
    let lastMessageAt: String?
    let unreadCount: Int?
    let participants: [String]?
}

private struct DriverPick: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let load: String?
}

private struct ChatBody: View {
    @Environment(\.palette) private var palette
    // Sheet→push (NAV remediation 2026-05-30): the compose-message form
    // now pushes in-stack via the surface's detail layer + BespokeBackBar
    // instead of presenting as a `.sheet`. Nil outside a role surface
    // that installs RoleDetailLayer.
    @Environment(\.rolePushDetail) private var pushDetail
    @State private var convs: [Conversation] = []
    @State private var drivers: [DriverPick] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var composeFor: DriverPick? = nil
    @State private var composeText: String = ""
    @State private var sending: Bool = false
    @State private var sendError: String? = nil
    @State private var sentEcho: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let m = sentEcho { LifecycleCard(accentGradient: true) { Text(m).font(EType.caption).foregroundStyle(palette.textPrimary) } }
                if let e = sendError { LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) } }
                conversationsSection
                driversSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "message.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · CHAT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Driver chat").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Reach a driver direct. Threads list shows unread counts.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var conversationsSection: some View {
        if loading { LifecycleCard { Text("Loading threads…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if convs.isEmpty {
            EusoEmptyState(systemImage: "message", title: "No active threads", subtitle: "Start one by tapping a driver below.")
        } else {
            VStack(alignment: .leading, spacing: Space.s3) {
                sectionHeader(label: "ACTIVE THREADS", icon: "tray.full")
                VStack(spacing: 0) {
                    ForEach(Array(convs.enumerated()), id: \.element.id) { idx, c in
                        threadRow(c)
                        if idx < convs.count - 1 { rowDivider }
                    }
                }
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    private func threadRow(_ c: Conversation) -> some View {
        let title = c.title ?? "Conversation"
        let unread = (c.unreadCount ?? 0) > 0
        return HStack(spacing: 10) {
            ChatAvatar(kind: .person(initials: initials(from: title), tint: Brand.magenta), size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(c.lastMessage ?? "-")
                    .font(EType.caption)
                    .foregroundStyle(unread ? palette.textPrimary : palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(humanISO(c.lastMessageAt, format: "MMM d"))
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                if let u = c.unreadCount, u > 0 {
                    Text("\(u)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(minWidth: 16)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var driversSection: some View {
        if !drivers.isEmpty {
            VStack(alignment: .leading, spacing: Space.s3) {
                sectionHeader(label: "MESSAGE A DRIVER", icon: "person.3")
                VStack(spacing: 0) {
                    ForEach(Array(drivers.enumerated()), id: \.element.id) { idx, d in
                        Button {
                            composeFor = d; composeText = ""
                            pushDetail?("Message \(d.name)") { AnyView(composeSheet(for: d)) }
                        } label: {
                            driverRow(d)
                        }.buttonStyle(.plain)
                        if idx < drivers.count - 1 { rowDivider }
                    }
                }
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    private func driverRow(_ d: DriverPick) -> some View {
        HStack(spacing: 10) {
            ChatAvatar(kind: .person(initials: initials(from: d.name), tint: Brand.magenta),
                       size: 38,
                       online: d.status.lowercased().contains("online")
                            || d.status.lowercased().contains("active")
                            || d.status.lowercased().contains("driving"))
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("\(d.status.uppercased()) · \(dashIfEmpty(d.load))")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// Shared section header — small gradient icon + tracked label, matching
    /// the kit's typography (replaces the old LifecycleSection chrome).
    private func sectionHeader(label: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var rowDivider: some View {
        palette.borderFaint.frame(height: 1).padding(.leading, Space.s3 + 38 + 10)
    }

    /// Up-to-two-letter initials for the row avatar (e.g. "Mike Usoro" → "MU").
    private func initials(from name: String) -> String {
        let parts = name
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first }
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }

    private func composeSheet(for d: DriverPick) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Message \(d.name)").font(EType.h2).foregroundStyle(palette.textPrimary)
            Text("Goes through dispatch.sendDriverMessage. Driver gets a push + in-app banner.").font(EType.caption).foregroundStyle(palette.textSecondary)
            TextEditor(text: $composeText)
                .font(EType.body)
                .frame(minHeight: 120)
                .padding(8)
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            HStack {
                Button {
                    composeFor = nil
                    NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
                } label: {
                    Text("Cancel").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
                Button { Task { await send(to: d) } } label: {
                    HStack(spacing: 6) {
                        if sending { ProgressView().tint(.white) }
                        Text(sending ? "Sending…" : "Send").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain).disabled(sending || composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Spacer()
        }
        .padding(14)
        .background(palette.bgPage)
    }

    private func loadAll() async {
        loading = true; loadError = nil
        do {
            async let c: [Conversation] = EusoTripAPI.shared.queryNoInput("messages.getConversations")
            async let d: [DriverPick] = EusoTripAPI.shared.queryNoInput("dispatch.getDriverStatuses")
            let (cs, ds) = try await (c, d)
            convs = cs
            drivers = ds
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func send(to d: DriverPick) async {
        sending = true; sendError = nil
        struct In: Encodable { let driverId: String; let message: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("dispatch.sendDriverMessage", input: In(driverId: d.id, message: composeText))
            sentEcho = "Sent to \(d.name)."
            composeFor = nil
            composeText = ""
            // Pop the pushed compose form back to the chat list on success.
            NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
            await loadAll()
        } catch {
            sendError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("706 · Chat · Night") { DispatchDriverChatScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("706 · Chat · Afternoon") { DispatchDriverChatScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }

