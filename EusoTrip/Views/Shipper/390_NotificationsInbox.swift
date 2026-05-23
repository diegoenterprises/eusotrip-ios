//
//  390_NotificationsInbox.swift
//  EusoTrip — Shipper · Notifications inbox (Arc B+).
//
//  Reshaped 2026-05-23 with a single MARK READ drop-zone tile
//  above the inbox list. Drag an unread notification card onto
//  it to fire notifications.markAsRead in one gesture. Items
//  that are already read aren't draggable (no-op drag source).
//  'Mark all as read' button in the header preserved as the
//  bulk path.
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
    @State private var markAllError: String? = nil
    @State private var actionError: String? = nil
    @State private var lastRead: String? = nil
    @State private var dropHover: Bool = false
    @State private var draggingItemId: String? = nil

    private var unread: Int { items.filter { $0.readAt == nil }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let m = lastRead {
                    LifecycleCard(accentGradient: true) {
                        Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                if let e = actionError {
                    LifecycleCard(accentDanger: true) {
                        Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
                if unread > 0 { markReadDropZone }
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
                Image(systemName: "bell.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · NOTIFICATIONS · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if unread > 0 {
                    Text("\(unread) UNREAD")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }
            }
            Text("Inbox")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            if !items.isEmpty {
                Button { Task { await markAllRead() } } label: {
                    Text("Mark all as read")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(palette.tintNeutral).clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    private var markReadDropZone: some View {
        let hoveringItem = draggingItemId.flatMap { id in items.first(where: { $0.id == id }) }
        return HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 38, height: 38)
                .background(palette.bgCardSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("MARK READ")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                if dropHover, let i = hoveringItem {
                    Text("Release to clear \(dashIfEmpty(i.title))")
                        .font(EType.caption)
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(2)
                } else {
                    Text("Drop an unread alert here to mark it read (clears badge on watch + web).")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if processing != nil {
                ProgressView().scaleEffect(0.8)
            } else {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(dropHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    dropHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                    lineWidth: dropHover ? 2 : 1
                )
                .animation(.easeOut(duration: 0.12), value: dropHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let iid = droppedIds.first else { return false }
            guard let item = items.first(where: { $0.id == iid }) else { return false }
            // Only unread items can be marked read — server is
            // idempotent but spare the no-op round-trip.
            guard item.readAt == nil else { return false }
            Task { await markRead(iid) }
            return true
        } isTargeted: { hovering in
            dropHover = hovering
        }
    }

    @ViewBuilder
    private var content: some View {
        if let merr = markAllError {
            LifecycleCard(accentDanger: true) {
                Text(merr).font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if loading { LifecycleCard { Text("Loading inbox…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if items.isEmpty { EusoEmptyState(systemImage: "bell.slash", title: "No notifications", subtitle: "Pings from carriers, settlements, and eSang land here.") }
        else {
            ForEach(items) { n in
                if n.readAt == nil {
                    inboxCard(n)
                        .draggable(n.id) {
                            inboxCard(n)
                                .frame(maxWidth: 320)
                                .opacity(0.92)
                                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                        }
                        .onDrag {
                            draggingItemId = n.id
                            return NSItemProvider(object: n.id as NSString)
                        }
                } else {
                    inboxCard(n)
                }
            }
        }
    }

    private func inboxCard(_ n: InboxItem) -> some View {
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
                    if processing == n.id {
                        ProgressView().scaleEffect(0.5)
                    }
                }
            }
        }.buttonStyle(.plain)
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
        markAllError = nil
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("notifications.markAllAsRead", input: ["": ""] as [String: String])
            await load()
        } catch let apiErr as EusoTripAPIError {
            markAllError = apiErr.errorDescription ?? "Couldn't mark all as read."
        } catch {
            markAllError = error.localizedDescription
        }
    }

    private func markRead(_ id: String) async {
        await MainActor.run { processing = id; actionError = nil }
        let label = items.first(where: { $0.id == id })?.title ?? "notification \(id)"
        struct In: Encodable { let id: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("notifications.markAsRead", input: In(id: id))
            await MainActor.run {
                lastRead = "\(label) → READ"
                draggingItemId = nil
            }
            await load()
        } catch {
            await MainActor.run {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { processing = nil }
    }
}

#Preview("390 · Inbox · Night") { NotificationsInboxScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("390 · Inbox · Afternoon") { NotificationsInboxScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
