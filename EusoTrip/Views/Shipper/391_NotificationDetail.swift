//
//  391_NotificationDetail.swift
//  EusoTrip — Shipper · Notification detail (Arc B+).
//

import SwiftUI

struct NotificationDetailScreen: View {
    let theme: Theme.Palette
    let notificationId: String
    var body: some View {
        Shell(theme: theme) { NotifDetailBody(notificationId: notificationId) } nav: { shipperLifecycleNav() }
    }
}

private struct NotifDetail: Decodable, Hashable {
    let id: String
    let title: String?
    let body: String?
    let category: String?
    let createdAt: String?
    let readAt: String?
    let deepLink: String?
    let payload: [String: String]?
}

private struct NotifDetailBody: View {
    @Environment(\.palette) private var palette
    let notificationId: String
    @State private var detail: NotifDetail? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading notification…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let d = detail { mainCard(d); deepLinkRow(d) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bell.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · NOTIFICATION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(detail?.title ?? "—").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func mainCard(_ d: NotifDetail) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: dashIfEmpty(d.category?.uppercased()), icon: "bell")
            Text(dashIfEmpty(d.body)).font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            LifecycleRow(label: "Received", value: humanISO(d.createdAt))
            LifecycleRow(label: "Read",     value: humanISO(d.readAt))
        }
    }

    @ViewBuilder
    private func deepLinkRow(_ d: NotifDetail) -> some View {
        if let link = d.deepLink, !link.isEmpty {
            Button {
                // Most deep links are screenIds. Fall back to URL open.
                if link.allSatisfy(\.isNumber) {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": link])
                } else if let u = URL(string: link) {
                    UIApplication.shared.open(u)
                }
            } label: {
                Text("Open").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let id: String }
        do {
            let d: NotifDetail = try await EusoTripAPI.shared.query("notifications.getById", input: In(id: notificationId))
            detail = d
            // Mark as read on first view.
            struct MarkIn: Encodable { let id: String }
            struct MarkOut: Decodable { let success: Bool }
            let _ : MarkOut = (try? await EusoTripAPI.shared.mutation("notifications.markAsRead", input: MarkIn(id: notificationId))) ?? MarkOut(success: false)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("391 · Notification · Night") { NotificationDetailScreen(theme: Theme.dark, notificationId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("391 · Notification · Afternoon") { NotificationDetailScreen(theme: Theme.light, notificationId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
