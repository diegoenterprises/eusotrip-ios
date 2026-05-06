//
//  MessagesScreen.swift
//  EusoTrip — Full-screen messaging surface (driver + shipper + every role)
//
//  Replaces the old `DriverMessagesSheet` pull-up modal with a real
//  top-level page: header → inbox → push to conversation, mirroring the
//  web platform's messaging surface. Founder mandate 2026-05-05:
//  "no more pull up page it needs to go to the full page with the
//   message threads i have and conversations i have and start new
//   messages etc."
//
//  Same screen is presented by Driver Home (010) AND Shipper Home (200)
//  via `.fullScreenCover(isPresented: $showMessages)`. The screen owns
//  its own back chevron + close affordance so both call sites get the
//  same chrome — the underlying tab state isn't disturbed; dismissing
//  the cover returns the user exactly where they were.
//
//  Backend wiring (live):
//    • messages.getConversations  — inbox list
//    • messages.searchUsers       — compose flow contact search
//    • messages.createConversation — start new thread
//    • messages.deleteConversation — swipe-to-delete (soft, per-caller)
//    • UnreadMessageStore         — single source of truth for the
//                                   top-bar badge; ingests every refresh
//    • .eusoMessageReceived       — re-fetch on inbound WebSocket fan-out
//
//  Shared types reused from `DriverTabPanes.swift`:
//    • InboxThread                 — one inbox row
//    • DriverConversationView      — per-thread bubbles + composer +
//                                    photo share + (peer threads only)
//                                    P2P money transfer
//    • NewMessageSheet             — compose flow (direct / group)
//

import SwiftUI

// MARK: - MessagesScreen

/// Full-screen messaging page. Pushed via `.fullScreenCover` from
/// 010 DriverHome / 200 ShipperHome. Internally a NavigationStack so
/// thread → conversation drill is native push (right-to-left slide,
/// system swipe-back gesture, real chevron in the header).
struct MessagesScreen: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    /// Inbox state. `path` drives the NavigationStack — pushing an
    /// `InboxThread` slides up the conversation surface.
    @State private var path: [InboxThread] = []
    @State private var threads: [InboxThread] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String? = nil
    @State private var didFirstLoad: Bool = false

    /// Compose flow.
    @State private var showNewMessage: Bool = false
    @State private var pendingOpenThread: InboxThread? = nil

    /// Swipe-to-delete confirmation state.
    @State private var pendingDelete: InboxThread? = nil
    @State private var lastDeletedSnapshot: (thread: InboxThread, index: Int)? = nil

    /// NotificationCenter token so we can tear down the inbound-message
    /// observer on dismiss.
    @State private var refreshObserver: NSObjectProtocol? = nil

    var body: some View {
        NavigationStack(path: $path) {
            inboxRoot
                .navigationDestination(for: InboxThread.self) { thread in
                    DriverConversationView(thread: thread)
                        .environment(\.palette, palette)
                        .navigationBarBackButtonHidden(true)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    if !path.isEmpty { path.removeLast() }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 16, weight: .heavy))
                                        Text("Messages")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundStyle(palette.textPrimary)
                                }
                                .accessibilityLabel("Back to messages")
                            }
                        }
                        .onDisappear {
                            // Returning from the conversation — re-pull
                            // so the row's preview + unread reflect the
                            // last reply / read-mark.
                            Task { @MainActor in await loadInbox(force: false) }
                        }
                }
        }
        .background(palette.bgPage.ignoresSafeArea())
        .task {
            if !didFirstLoad { await loadInbox(force: true) }
        }
        .onAppear {
            let token = NotificationCenter.default.addObserver(
                forName: .eusoMessageReceived, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in await loadInbox(force: false) }
            }
            refreshObserver = token
        }
        .onDisappear {
            if let refreshObserver {
                NotificationCenter.default.removeObserver(refreshObserver)
            }
            refreshObserver = nil
        }
        .sheet(isPresented: $showNewMessage) {
            NewMessageSheet { thread in
                pendingOpenThread = thread
            }
            .environment(\.palette, palette)
        }
        .onChange(of: showNewMessage) { _, isShown in
            guard !isShown, let thread = pendingOpenThread else { return }
            pendingOpenThread = nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                path.append(thread)
                await loadInbox(force: false)
            }
        }
        .confirmationDialog(
            pendingDelete.map { "Delete conversation with \($0.title)?" } ?? "Delete conversation?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { thread in
            Button("Delete", role: .destructive) {
                Task { @MainActor in await deleteThread(thread) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This removes the thread from your inbox. The other participant's copy is unaffected.")
        }
    }

    // MARK: - Inbox root

    private var inboxRoot: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            IridescentHairline()
            inboxBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.s2) {
            // Back chevron — dismisses the full-screen cover. Founder
            // mandate: every screen has a back button. We render it as
            // its own affordance instead of relying on the system nav
            // bar so the chrome is consistent across roles + plays well
            // with the iridescent hairline below.
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text("Messages")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("DISPATCH · ESANG · BROKERS · PEERS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()

            // Compose — opens NewMessageSheet (search / direct or group)
            Button {
                showNewMessage = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(LinearGradient.diagonal.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(LinearGradient.diagonal, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start a new conversation")
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    // MARK: Body

    @ViewBuilder
    private var inboxBody: some View {
        if !didFirstLoad && isLoading {
            ScrollView { inboxSkeleton.padding(Space.s5) }
        } else if threads.isEmpty {
            ScrollView { emptyState.padding(Space.s5) }
                .refreshable { await loadInbox(force: true) }
        } else {
            List {
                Section {
                    ForEach(threads) { t in
                        Button {
                            path.append(t)
                        } label: {
                            threadRow(t)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(t.title)")
                        .listRowBackground(palette.bgCard)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparatorTint(palette.borderFaint)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = t
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .accessibilityLabel("Delete conversation with \(t.title)")
                        }
                    }
                } footer: {
                    if let loadError, !threads.isEmpty {
                        Text(loadError)
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, Space.s2)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(palette.bgPage)
            .refreshable { await loadInbox(force: true) }
        }
    }

    // MARK: - Inbox loader

    private func loadInbox(force: Bool) async {
        if isLoading && !force { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await EusoTripAPI.shared.messaging.getConversations()
            threads = fetched.map(InboxThread.init(fromConversation:))
            loadError = nil
            didFirstLoad = true
            UnreadMessageStore.shared.ingest(conversations: fetched)
        } catch EusoTripAPIError.unauthenticated {
            loadError = "Please sign in to load messages."
            didFirstLoad = true
        } catch {
            loadError = "Couldn't refresh messages — \(error.localizedDescription)"
            didFirstLoad = true
        }
    }

    // MARK: - Swipe-to-delete

    @MainActor
    private func deleteThread(_ thread: InboxThread) async {
        pendingDelete = nil
        guard let idx = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        lastDeletedSnapshot = (thread, idx)
        _ = withAnimation(.easeInOut(duration: 0.2)) {
            threads.remove(at: idx)
        }
        // If the deleted thread is open in the stack, pop it.
        if let topId = path.last?.id, topId == thread.id {
            path.removeLast()
        }
        do {
            _ = try await EusoTripAPI.shared.messaging.deleteConversation(
                conversationId: thread.id
            )
            lastDeletedSnapshot = nil
            await loadInbox(force: false)
        } catch {
            if let snapshot = lastDeletedSnapshot {
                withAnimation(.easeInOut(duration: 0.2)) {
                    let insertAt = min(snapshot.index, threads.count)
                    threads.insert(snapshot.thread, at: insertAt)
                }
                lastDeletedSnapshot = nil
            }
            loadError = "Couldn't delete — \(error.localizedDescription)"
        }
    }

    // MARK: - Empty + skeleton

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(palette.textTertiary)
            Text("No conversations yet")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("Start a direct chat with dispatch, a broker, or another driver — or spin up a group for your lane.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s4)

            Button {
                showNewMessage = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Start a conversation")
                        .font(EType.bodyStrong)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, 10)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, Space.s2)
            .accessibilityLabel("Start a conversation")

            if let loadError {
                Text(loadError)
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s6)
    }

    @ViewBuilder private var inboxSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(alignment: .top, spacing: Space.s3) {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(palette.tintNeutral)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(palette.tintNeutral)
                            .frame(width: 180, height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(palette.tintNeutral.opacity(0.6))
                            .frame(width: 240, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
            }
        }
        .eusoCard(radius: Radius.lg)
        .redacted(reason: .placeholder)
    }

    @ViewBuilder
    private func threadRow(_ t: InboxThread) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral)
                Image(systemName: t.glyph)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(t.title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(t.time)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Text(t.preview)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }

            if t.unread > 0 {
                Text("\(t.unread)")
                    .font(EType.micro)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient.diagonal)
                    )
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .contentShape(Rectangle())
    }
}

#Preview("Messages · Night") {
    MessagesScreen()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("Messages · Day") {
    MessagesScreen()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
