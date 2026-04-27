//
//  UnreadMessageStore.swift
//  EusoTrip — Aggregate unread-message counter for the chat glyph badge.
//
//  Why this exists:
//  -----------------
//  The Driver top-bar chat glyph (and Shipper/Broker parity surfaces)
//  shows a small numeric badge whenever there are unread messages in
//  ANY conversation. That number has two authoritative sources:
//
//     1. `messages.getUnreadCount` (tRPC) — the source of truth, but
//        costs a network round-trip so we only refresh on app wake,
//        when a message:new socket event lands, or when the user marks
//        a thread as read.
//
//     2. WebSocket `message:new` — incremental fan-out. When the
//        RealtimeService posts `.eusoMessageReceived` we bump the
//        optimistic total by 1 (for the conversation that isn't
//        currently open) and fire a re-fetch in the background to
//        stay consistent with the server.
//
//  Top-bar observers just read `UnreadMessageStore.shared.total` and
//  rebind when `.eusoUnreadCountChanged` fires.
//

import Foundation
import SwiftUI

@MainActor
final class UnreadMessageStore: ObservableObject {

    static let shared = UnreadMessageStore()

    /// Total unread across every conversation the user participates in.
    @Published private(set) var total: Int = 0

    /// Per-conversation unread (mirrors `messages.getUnreadCount`'s
    /// `byConversation` map). Consumed by `DriverMessagesSheet` so
    /// inbox rows show an accurate dot even when the row itself has
    /// a stale `unread` count from `getConversations`.
    @Published private(set) var byConversation: [String: Int] = [:]

    /// The id of the conversation currently foregrounded by the user.
    /// Any `message:new` for THIS conversation is NOT counted towards
    /// the badge — the active DriverConversationView already reads it
    /// on-screen, so bumping the badge would feel wrong.
    private var activeConversationId: String?

    private var refreshTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private init() {
        installObservers()
    }

    deinit {
        let observers = self.observers
        let center = NotificationCenter.default
        for token in observers { center.removeObserver(token) }
    }

    // MARK: Public API

    /// Pull the authoritative count from the backend. Safe to call
    /// liberally — coalesced via `refreshTask`.
    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await EusoTripAPI.shared.messaging.getUnreadCount()
                await MainActor.run {
                    self.total = snapshot.total
                    self.byConversation = snapshot.byConversation
                    NotificationCenter.default.post(
                        name: .eusoUnreadCountChanged, object: nil
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                #if DEBUG
                print("[UnreadMessageStore] refresh failed: \(error)")
                #endif
            }
        }
    }

    /// Called when the user opens a conversation. While a conversation
    /// is active we zero its local count AND suppress optimistic bumps
    /// for `message:new` events on that thread.
    func didOpenConversation(_ conversationId: String) {
        activeConversationId = conversationId
        let local = byConversation[conversationId] ?? 0
        if local > 0 {
            byConversation[conversationId] = 0
            total = max(0, total - local)
            NotificationCenter.default.post(
                name: .eusoUnreadCountChanged, object: nil
            )
        }
    }

    func didCloseConversation(_ conversationId: String) {
        if activeConversationId == conversationId {
            activeConversationId = nil
        }
    }

    /// The conversation list fetched a fresh snapshot — fold its
    /// per-conversation counts into our store so the top-bar badge
    /// lines up with what the inbox is showing.
    func ingest(conversations: [MessagingConversation]) {
        var map: [String: Int] = [:]
        var sum = 0
        for c in conversations {
            let u = c.effectiveUnread
            if u > 0 {
                map[c.id] = u
                sum += u
            }
        }
        byConversation = map
        total = sum
        NotificationCenter.default.post(
            name: .eusoUnreadCountChanged, object: nil
        )
    }

    // MARK: Private

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: .eusoMessageReceived, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor [weak self] in
                    self?.handleIncoming(note)
                }
            }
        )
    }

    private func handleIncoming(_ note: Notification) {
        guard let info = note.userInfo else { return }
        // Backend payload keys: conversationId, messageId, senderId, ...
        let convId = (info["conversationId"] as? String)
            ?? (info["conversationId"] as? Int).map(String.init)
            ?? ""
        guard !convId.isEmpty else { return }
        if convId == activeConversationId { return }

        let current = byConversation[convId] ?? 0
        byConversation[convId] = current + 1
        total += 1
        NotificationCenter.default.post(
            name: .eusoUnreadCountChanged, object: nil
        )

        // Background refresh to stay consistent with the server (handles
        // e.g. the user having the thread open on another device).
        refresh()
    }
}
