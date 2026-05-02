// SHELVED 2026-05-01 — pre-existing build errors against an older
// design-system version (Theme.Palette.background, EType.h3,
// OrbESang.State.alert, etc.). Dispatch role currently routes to
// SFSafariViewController(app.eusotrip.com/dispatch) via
// RoleSurfaceRouter; this file ships the next time we knock down
// the Dispatch role per the founder's role-by-role cadence. Wrapped
// in `#if false` so the file references stay in the Xcode target
// (project.pbxproj) but the body doesn't enter compilation.
#if false
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
        .sheet(item: $composeFor) { d in composeSheet(for: d) }
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
            LifecycleCard {
                LifecycleSection(label: "ACTIVE THREADS", icon: "tray.full")
                ForEach(convs) { c in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title ?? "Conversation").font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                            Text(c.lastMessage ?? "—").font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if let u = c.unreadCount, u > 0 {
                            Text("\(u)").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Brand.danger).clipShape(Capsule())
                        }
                        Text(humanISO(c.lastMessageAt, format: "MMM d")).font(EType.caption).foregroundStyle(palette.textTertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var driversSection: some View {
        if !drivers.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "MESSAGE A DRIVER", icon: "person.3")
                ForEach(drivers) { d in
                    Button { composeFor = d; composeText = "" } label: {
                        HStack {
                            Image(systemName: "person.fill").foregroundStyle(LinearGradient.diagonal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                                Text("\(d.status.uppercased()) · \(dashIfEmpty(d.load))").font(EType.caption).foregroundStyle(palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                        }
                        .padding(.vertical, 6)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func composeSheet(for d: DriverPick) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Message \(d.name)").font(EType.h3).foregroundStyle(palette.textPrimary)
            Text("Goes through dispatch.sendDriverMessage. Driver gets a push + in-app banner.").font(EType.caption).foregroundStyle(palette.textSecondary)
            TextEditor(text: $composeText)
                .font(EType.body)
                .frame(minHeight: 120)
                .padding(8)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            HStack {
                Button { composeFor = nil } label: {
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
        .background(palette.background)
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
            await loadAll()
        } catch {
            sendError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("706 · Chat · Night") { DispatchDriverChatScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("706 · Chat · Afternoon") { DispatchDriverChatScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }

#endif
