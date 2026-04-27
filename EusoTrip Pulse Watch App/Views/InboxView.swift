//
//  InboxView.swift
//  EusoTrip Pulse Watch App
//
//  Recent conversation threads for the wrist inbox tab. The list hydrates
//  from the live `messages.getConversations` tRPC procedure and renders
//  the last N threads the driver can tap to see a compact thread view
//  with canned replies + voice reply.
//
//  Unread parity with the phone
//  -----------------------------
//  The phone's `UnreadMessageStore` is the authoritative source for the
//  aggregate unread counter; every time it changes on the phone,
//  `WatchAuthBridge.pushUnreadCount` fans a `messaging.unread`
//  applicationContext out to the wrist, and
//  `WatchConnectivityManager.applyContext` lands it in
//  `InboxStore.shared.unreadTotal` + `.unreadByConversation`. The
//  `InboxBadge` view in this file re-renders whenever the store
//  republishes, so the tab label stays in sync even when the watch
//  doesn't have network connectivity of its own.
//
//  Offline messaging
//  -----------------
//  Canned replies route through `messages.sendMessage` (the same tRPC
//  procedure the phone uses) so everything the driver says from the
//  wrist lands in the same conversation row on the server, visible to
//  everyone and counted in the unread totals for the other participant.
//

import SwiftUI
import Combine

struct InboxThread: Identifiable, Equatable {
    let id: String
    let title: String
    let preview: String
    let at: Date
    let unread: Int
}

@MainActor
final class InboxStore: ObservableObject {
    static let shared = InboxStore()

    @Published var threads: [InboxThread] = []

    /// Aggregate unread count mirrored from the phone's
    /// `UnreadMessageStore.total` via `WatchConnectivityManager`. Also
    /// bumped locally on `messages.sendMessage` success / thread open so
    /// the badge decays without waiting for the next phone fan-out.
    @Published var unreadTotal: Int = 0

    /// Per-conversation unread map; the inbox list consults this when
    /// deciding whether to render a dot on a thread row, so the wrist
    /// stays accurate even when the phone-fetched `unread` field on a
    /// `MessagingConversation` row is stale.
    @Published var unreadByConversation: [String: Int] = [:]

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else { return }
        do {
            let client = EsangClient(auth: auth)
            let data = try await client.queryJSON("messages.getConversations")
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable {
                        let json: [RemoteThread]
                    }
                    let data: DataContainer
                }
                let result: Result
            }
            struct RemoteThread: Decodable {
                let id: String
                // Server returns `participantName` for direct threads +
                // `name` for groups/channels; whichever wins we surface
                // as the wrist-row title.
                let participantName: String?
                let name: String?
                let lastMessage: String?
                let lastMessageAt: String?
                let unread: Int?
                let unreadCount: Int?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            let mapped = env.result.data.json.prefix(5).map { t in
                InboxThread(
                    id: t.id,
                    title: t.participantName ?? t.name ?? "Conversation",
                    preview: t.lastMessage ?? "",
                    at: ISO8601DateFormatter.iso.date(from: t.lastMessageAt ?? "") ?? Date(),
                    unread: t.unreadCount ?? t.unread ?? 0
                )
            }
            threads = Array(mapped)

            // Fold the per-thread unread counts from the same payload
            // into the local store so a refresh without a phone-side
            // push still produces an accurate badge.
            var map: [String: Int] = [:]
            var sum = 0
            for t in threads {
                if t.unread > 0 {
                    map[t.id] = t.unread
                    sum += t.unread
                }
            }
            unreadByConversation = map
            // Prefer the phone-pushed total when we have one (it
            // reflects conversations we're a participant in beyond the
            // top-5 we display on the wrist). Only overwrite if we've
            // never seen a phone push.
            if unreadTotal == 0 {
                unreadTotal = sum
            }
        } catch {
            // Keep the existing list — a transient network flake
            // shouldn't clear the inbox.
        }
    }

    /// Called by `WatchConnectivityManager` when the phone fans a
    /// `messaging.unread` op to the wrist. Replaces both the total and
    /// the per-conversation map wholesale so the badge snaps to the
    /// phone-authoritative count.
    func applyRemoteUnread(total: Int, map: [String: Int]) {
        unreadTotal = max(0, total)
        unreadByConversation = map
    }

    /// Locally decrement unread for a thread the wrist just opened so the
    /// badge decays without waiting for the next phone push. The real
    /// mark-as-read hits the backend via `didOpenThread(_:)`.
    func markLocallyRead(_ threadId: String) {
        let current = unreadByConversation[threadId] ?? 0
        if current > 0 {
            unreadByConversation[threadId] = 0
            unreadTotal = max(0, unreadTotal - current)
            if let idx = threads.firstIndex(where: { $0.id == threadId }) {
                let t = threads[idx]
                threads[idx] = InboxThread(
                    id: t.id, title: t.title, preview: t.preview,
                    at: t.at, unread: 0
                )
            }
        }
    }

    /// Fire-and-forget mark-as-read when the driver opens a thread on
    /// the wrist. Mirrors the phone-side
    /// `EusoTripAPI.shared.messaging.markAsRead(...)` call.
    func didOpenThread(_ threadId: String, auth: AuthStore) {
        markLocallyRead(threadId)
        Task {
            _ = try? await EsangClient(auth: auth)
                .mutateJSON("messages.markAsRead", input: ["conversationId": threadId])
        }
    }
}

// MARK: - Badge overlay

/// Stamped over the Inbox tab's content so the driver can see at a
/// glance that there's unread mail without opening the tab. Also re-used
/// as the tiny unread pill on each thread row.
struct InboxBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 16, minHeight: 16)
                .background(Capsule().fill(Color.esangBlue))
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.6))
                .accessibilityLabel("\(count) unread")
        }
    }
}

// MARK: - Inbox tab

struct InboxView: View {
    @EnvironmentObject var auth: AuthStore
    @StateObject private var store = InboxStore.shared
    @State private var activeThread: InboxThread?

    var body: some View {
        ScrollView {
            VStack(spacing: S.s1) {
                // Header with the live unread count — matches the phone
                // top-bar chat glyph so parity reads instantly to the
                // user switching between surfaces.
                HStack(spacing: 6) {
                    Text("Inbox")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    InboxBadge(count: store.unreadTotal)
                }
                .padding(.horizontal, 2)

                if store.threads.isEmpty {
                    VStack(spacing: 6) {
                        Text("No threads yet")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Messages you send from the phone appear here.")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                } else {
                    ForEach(store.threads) { thread in
                        Button {
                            activeThread = thread
                            store.didOpenThread(thread.id, auth: auth)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(thread.title)
                                        .font(.system(size: 12, weight: .bold))
                                        .lineLimit(1)
                                    Spacer()
                                    let threadUnread = store.unreadByConversation[thread.id] ?? thread.unread
                                    if threadUnread > 0 {
                                        InboxBadge(count: threadUnread)
                                    }
                                }
                                Text(thread.preview)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text(thread.at, style: .relative)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, S.s1)
        }
        .navigationTitle("Inbox")
        .task { await store.refresh(auth: auth) }
        .sheet(item: $activeThread) { thread in
            InboxThreadView(thread: thread)
        }
        // Thread cards hug the edges; clip to the bezel shape so the
        // card backgrounds + blue unread badges don't stamp past the
        // rounded corners on overscroll.
        .clipShape(ContainerRelativeShape())
    }
}

// MARK: - Thread detail

struct InboxThreadView: View {
    let thread: InboxThread
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    private let cannedReplies = [
        "On it.",
        "Copy, 10-4.",
        "Running 15 min behind.",
        "Arrived.",
        "Need a minute — I'll call you."
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: S.s2) {
                Text(thread.title).font(.system(size: 14, weight: .bold))
                Text(thread.preview).font(.system(size: 12)).foregroundStyle(.secondary)
                Divider()
                Text("Quick reply").font(.system(size: 10)).foregroundStyle(.tertiary)
                ForEach(cannedReplies, id: \.self) { reply in
                    Button {
                        Task {
                            // The server's real procedure is
                            // `messages.sendMessage` and expects
                            // `conversationId` + `content`. (The legacy
                            // watch code called `messages.send` with
                            // `threadId` / `text` and silently failed —
                            // no thread was ever created.)
                            _ = try? await EsangClient(auth: auth).mutateJSON(
                                "messages.sendMessage",
                                input: [
                                    "conversationId": thread.id,
                                    "content": reply,
                                    "type": "text"
                                ]
                            )
                            dismiss()
                        }
                    } label: {
                        Text(reply)
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(7)
                            .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, S.s2)
        }
        .navigationTitle(thread.title)
        // Canned-reply buttons reach edge to edge; clip to the bezel so
        // the card fills don't show past the rounded corners when the
        // thread sheet presents.
        .clipShape(ContainerRelativeShape())
    }
}
