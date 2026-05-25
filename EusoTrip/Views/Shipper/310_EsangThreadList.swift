//
//  310_eSangThreadList.swift
//  EusoTrip — Shipper · eSang AI · Thread list (Arc I).
//  Backed by `messaging.getConversations`.
//

import SwiftUI

struct eSangThreadListScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ThreadListBody() } nav: { shipperLifecycleNav() }
    }
}

/// Decodable view of `messages.getConversations` returns. Server fields
/// are remapped via CodingKeys so the existing view code keeps reading
/// `c.title` / `c.kind` while the wire format uses the canonical
/// `name` / `type` keys. Migrating to the canonical `messages` router
/// (away from the deprecated `messaging` router) restored the unread
/// counter on the inbox row — `messaging.getConversations` did NOT
/// surface unreadCount; `messages.getConversations` does.
private struct Conversation: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let lastMessage: String?
    let lastMessageAt: String?
    let unreadCount: Int?
    let kind: String?  // "direct", "group", etc. (server returns `type`)

    enum CodingKeys: String, CodingKey {
        case id
        case title = "name"
        case lastMessage
        case lastMessageAt
        case unreadCount
        case kind = "type"
    }
}

private struct ThreadListBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [Conversation] = []
    @State private var loading = true
    @State private var loadError: String? = nil

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
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                // Rebranded 2026-05-24: founder mandate — this screen is
                // the load + dispatch + broker + peer inbox, NOT the
                // ESANG AI surface. ESANG AI lives at the orb. Calling
                // it "eSang chat" made every conversation here look
                // like an AI thread, which is what triggered the
                // "what's the difference between Messages and ESANG"
                // confusion.
                Text("SHIPPER · MESSAGES · INBOX").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Messages").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Conversations with dispatch, carriers, brokers, and load participants.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading threads…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty {
            EusoEmptyState(systemImage: "message", title: "No conversations", subtitle: "Start a chat with a carrier, dispatcher, or eSang from a load detail.")
        } else {
            ForEach(rows) { c in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "311", "conversationId": c.id])
                } label: {
                    LifecycleCard {
                        HStack {
                            Image(systemName: c.kind == "esang_ai" ? "sparkles" : "person.2.fill")
                                .foregroundStyle(LinearGradient.diagonal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dashIfEmpty(c.title)).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                                Text(dashIfEmpty(c.lastMessage)).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(humanISO(c.lastMessageAt, format: "HH:mm")).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                                if let n = c.unreadCount, n > 0 {
                                    Text("\(n)").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(LinearGradient.diagonal).clipShape(Capsule())
                                }
                            }
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            // Canonical messaging router. Was `messaging.getConversations`
            // which returned `{items:[...]}` shape — incompatible with the
            // `[Conversation]` decoder here. `messages.getConversations`
            // returns the flat array AND the `unreadCount` field the
            // inbox row badge needs.
            struct In: Encodable { let search: String? }
            let r: [Conversation] = try await EusoTripAPI.shared.query(
                "messages.getConversations",
                input: In(search: nil)
            )
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("310 · eSang threads · Night") {
    eSangThreadListScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("310 · eSang threads · Afternoon") {
    eSangThreadListScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
