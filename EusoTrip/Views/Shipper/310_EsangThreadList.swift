//
//  310_EsangThreadList.swift
//  EusoTrip — Shipper · ESang AI · Thread list (Arc I).
//  Backed by `messaging.getConversations`.
//

import SwiftUI

struct EsangThreadListScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ThreadListBody() } nav: { shipperLifecycleNav() }
    }
}

private struct Conversation: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let lastMessage: String?
    let lastMessageAt: String?
    let unreadCount: Int?
    let kind: String?  // "carrier", "dispatch", "esang_ai", etc.
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
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · ESANG · THREADS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("ESang chat").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading threads…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty {
            EusoEmptyState(systemImage: "message", title: "No conversations", subtitle: "Start a chat with a carrier, dispatcher, or ESang from a load detail.")
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
            let r: [Conversation] = try await EusoTripAPI.shared.queryNoInput("messaging.getConversations")
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("310 · ESang threads · Night") {
    EsangThreadListScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("310 · ESang threads · Afternoon") {
    EsangThreadListScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
