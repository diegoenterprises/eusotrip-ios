//
//  390_NotificationsInbox.swift
//  EusoTrip — Shipper · Notifications inbox (Arc B+).
//

import SwiftUI

struct NotificationsInboxScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { InboxBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: true),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct InboxItem: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let body: String?
    let category: String?
    let createdAt: String?
    let readAt: String?
    let deepLink: String?
}

private struct InboxBody: View {
    @Environment(\.palette) private var palette
    @State private var items: [InboxItem] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var processing: String? = nil

    private var unread: Int { items.filter { $0.readAt == nil }.count }

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
                Image(systemName: "bell.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · NOTIFICATIONS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if unread > 0 {
                    Text("\(unread) UNREAD").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }
            }
            Text("Inbox").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            if !items.isEmpty {
                Button { Task { await markAllRead() } } label: {
                    Text("Mark all as read").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(palette.tintNeutral).clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading inbox…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if items.isEmpty { EusoEmptyState(systemImage: "bell.slash", title: "No notifications", subtitle: "Pings from carriers, settlements, and ESang land here.") }
        else {
            ForEach(items) { n in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "391", "notificationId": n.id])
                } label: {
                    LifecycleCard(accentGradient: n.readAt == nil) {
                        HStack(alignment: .top) {
                            Image(systemName: iconFor(n.category)).foregroundStyle(LinearGradient.diagonal).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dashIfEmpty(n.title)).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                                Text(dashIfEmpty(n.body)).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
                                Text(humanISO(n.createdAt)).font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                            if n.readAt == nil {
                                Circle().fill(LinearGradient.diagonal).frame(width: 8, height: 8)
                            }
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func iconFor(_ category: String?) -> String {
        switch (category ?? "").lowercased() {
        case "bid_received", "bid_awarded": return "hand.raised.fill"
        case "load_status_changed":         return "shippingbox.fill"
        case "geofence_event":               return "dot.radiowaves.left.and.right"
        case "settlement_paid", "settlement_disputed": return "creditcard.fill"
        case "doc_uploaded":                 return "doc.fill"
        case "compliance_expiring":          return "exclamationmark.triangle.fill"
        default:                              return "bell.fill"
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [InboxItem] = try await EusoTripAPI.shared.queryNoInput("notifications.list")
            items = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func markAllRead() async {
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("notifications.markAllAsRead", input: ["": ""] as [String: String])
            await load()
        } catch { /* surface inline */ }
    }
}

#Preview("390 · Inbox · Night") { NotificationsInboxScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("390 · Inbox · Afternoon") { NotificationsInboxScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
