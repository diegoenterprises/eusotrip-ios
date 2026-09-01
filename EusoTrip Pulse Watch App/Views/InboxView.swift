//
//  InboxView.swift
//  EusoTrip Pulse Watch App
//
//  Identity-scoped conversations, real transcript reads, durable replies,
//  and exact continuation into the matching iPhone thread.
//

import SwiftUI
import Combine

struct InboxThread: Identifiable, Equatable {
    let id: String
    let title: String
    let preview: String
    let at: Date?
    let unread: Int
}

struct InboxMessage: Identifiable, Equatable {
    enum Delivery: Equatable {
        case received
        case confirmed
        case queued
    }

    let id: String
    let senderName: String?
    let content: String
    let at: Date?
    let isOwn: Bool
    let delivery: Delivery
}

struct InboxUnreadEvidence: Equatable {
    enum Source: Equatable {
        case none
        case server(Date)
        case phone(Date)
        #if targetEnvironment(simulator)
        case visualQA
        #endif
    }

    var userId: String?
    var total = 0
    var byConversation: [String: Int] = [:]
    var source: Source = .none

    mutating func reset(for userId: String?) {
        self.userId = userId
        total = 0
        byConversation = [:]
        source = .none
    }

    @discardableResult
    mutating func applyServer(
        map: [String: Int],
        userId: String,
        observedAt: Date
    ) -> Bool {
        guard self.userId == userId else { return false }
        if case .phone = source { return false }
        let clean = Self.sanitized(map)
        byConversation = clean
        total = clean.values.reduce(0, +)
        source = .server(observedAt)
        return true
    }

    @discardableResult
    mutating func applyPhone(
        total: Int,
        map: [String: Int],
        userId: String,
        observedAt: Date
    ) -> Bool {
        if self.userId == nil { reset(for: userId) }
        guard self.userId == userId else { return false }
        byConversation = Self.sanitized(map)
        self.total = max(0, total)
        source = .phone(observedAt)
        return true
    }

    mutating func confirmRead(_ conversationId: String) {
        let unread = byConversation[conversationId] ?? 0
        byConversation[conversationId] = 0
        total = max(0, total - unread)
    }

    func unread(for conversationId: String, serverFallback: Int) -> Int {
        switch source {
        case .none:
            return max(0, serverFallback)
        case .server, .phone:
            return max(0, byConversation[conversationId] ?? 0)
        #if targetEnvironment(simulator)
        case .visualQA:
            return max(0, byConversation[conversationId] ?? 0)
        #endif
        }
    }

    private static func sanitized(_ map: [String: Int]) -> [String: Int] {
        map.reduce(into: [:]) { result, item in
            guard !item.key.isEmpty, item.value > 0 else { return }
            result[item.key] = item.value
        }
    }
}

enum InboxReadSyncState: Equatable {
    case syncing
    case confirmed
    case failed(String)
}

enum InboxDeliveryPolicy {
    static func shouldQueue(_ error: Error) -> Bool {
        if let esangError = error as? EsangError {
            switch esangError {
            case .badResponse, .notConnected, .decoding:
                return true
            case .server(let status, _):
                return status == 408 || status == 425 || status == 429 || status >= 500
            case .unauthorized, .audioRouteUnavailable:
                return false
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled, .badURL, .unsupportedURL,
                 .userAuthenticationRequired, .userCancelledAuthentication,
                 .appTransportSecurityRequiresSecureConnection:
                return false
            default:
                return true
            }
        }
        return false
    }
}

@MainActor
final class InboxStore: ObservableObject {
    static let shared = InboxStore()

    @Published private(set) var threads: [InboxThread] = []
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var unread = InboxUnreadEvidence()
    @Published private(set) var readSync: [String: InboxReadSyncState] = [:]

    private(set) var boundUserId: String?
    private var requestGeneration = 0

    var unreadTotal: Int { unread.total }

    func unreadCount(for thread: InboxThread) -> Int {
        unread.unread(for: thread.id, serverFallback: thread.unread)
    }

    func resetForIdentity(_ userId: String?) {
        requestGeneration += 1
        boundUserId = userId
        threads = []
        hasLoadedOnce = false
        isRefreshing = false
        lastError = nil
        lastRefreshAt = nil
        readSync = [:]
        unread.reset(for: userId)
    }

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn, let userId = auth.userId, !userId.isEmpty else {
            resetForIdentity(nil)
            lastError = "Sign in on iPhone to load conversations."
            return
        }
        if boundUserId != userId {
            resetForIdentity(userId)
        }

        requestGeneration += 1
        let generation = requestGeneration
        isRefreshing = true
        lastError = nil

        do {
            let data = try await EsangClient(auth: auth).queryJSON("messages.getConversations")
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable { let json: [RemoteThread] }
                    let data: DataContainer
                }
                let result: Result
            }
            struct RemoteThread: Decodable {
                let id: String
                let participantName: String?
                let name: String?
                let lastMessage: String?
                let lastMessageAt: String?
                let unread: Int?
                let unreadCount: Int?
            }

            let rows = try JSONDecoder().decode(Envelope.self, from: data).result.data.json
            let mapped = rows.prefix(8).map { row in
                let candidateTitle = row.participantName ?? row.name ?? ""
                let title = candidateTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let preview = (row.lastMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return InboxThread(
                    id: row.id,
                    title: title.isEmpty ? "Unnamed conversation" : title,
                    preview: preview,
                    at: Self.parseTimestamp(row.lastMessageAt),
                    unread: max(0, row.unreadCount ?? row.unread ?? 0)
                )
            }
            guard generation == requestGeneration,
                  auth.userId == userId,
                  boundUserId == userId else { return }

            threads = Array(mapped)
            var serverUnread: [String: Int] = [:]
            for thread in threads where thread.unread > 0 {
                serverUnread[thread.id] = thread.unread
            }
            let receivedAt = Date()
            unread.applyServer(map: serverUnread, userId: userId, observedAt: receivedAt)
            lastRefreshAt = receivedAt
            hasLoadedOnce = true
            isRefreshing = false
        } catch {
            guard generation == requestGeneration, boundUserId == userId else { return }
            isRefreshing = false
            lastError = Self.compactError(error, fallback: "Can't load conversations from EusoTrip.")
        }
    }

    func applyRemoteUnread(
        total: Int,
        map: [String: Int],
        userId: String,
        observedAt: Date
    ) {
        if boundUserId == nil {
            boundUserId = userId
            unread.reset(for: userId)
        }
        guard boundUserId == userId else { return }
        unread.applyPhone(total: total, map: map, userId: userId, observedAt: observedAt)
    }

    func markReadAfterOpen(_ threadId: String, auth: AuthStore) {
        guard auth.isSignedIn,
              let userId = auth.userId,
              userId == boundUserId,
              !threadId.isEmpty else { return }
        readSync[threadId] = .syncing

        Task {
            do {
                let data = try await EsangClient(auth: auth).mutateJSON(
                    "messages.markAsRead",
                    input: ["conversationId": threadId]
                )
                struct Envelope: Decodable {
                    struct Result: Decodable {
                        struct DataContainer: Decodable { let json: Receipt }
                        let data: DataContainer
                    }
                    let result: Result
                }
                struct Receipt: Decodable { let success: Bool }
                let success = try JSONDecoder().decode(Envelope.self, from: data).result.data.json.success
                guard auth.userId == userId, boundUserId == userId else { return }
                guard success else {
                    readSync[threadId] = .failed("Read status was not accepted by EusoTrip.")
                    return
                }
                unread.confirmRead(threadId)
                if let index = threads.firstIndex(where: { $0.id == threadId }) {
                    let thread = threads[index]
                    threads[index] = InboxThread(
                        id: thread.id,
                        title: thread.title,
                        preview: thread.preview,
                        at: thread.at,
                        unread: 0
                    )
                }
                readSync[threadId] = .confirmed
            } catch {
                readSync[threadId] = .failed(
                    Self.compactError(error, fallback: "Read status will retry from iPhone.")
                )
            }
        }
    }

    func evidenceLabel(at now: Date) -> String {
        #if targetEnvironment(simulator)
        if case .visualQA = unread.source {
            return "LAYOUT QA · SIMULATOR FIXTURE"
        }
        #endif
        switch unread.source {
        case .phone(let observedAt):
            return "PHONE UNREAD · \(Self.age(observedAt, at: now))"
        case .server(let observedAt):
            return "SERVER THREADS · \(Self.age(observedAt, at: now))"
        case .none:
            if isRefreshing { return "REQUESTING CONVERSATIONS" }
            return "NO MESSAGE EVIDENCE"
        #if targetEnvironment(simulator)
        case .visualQA:
            return "LAYOUT QA · SIMULATOR FIXTURE"
        #endif
        }
    }

    static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return ISO8601DateFormatter.iso.date(from: raw)
    }

    static func compactError(_ error: Error, fallback: String) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > 96 ? fallback : trimmed
    }

    static func age(_ date: Date, at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "NOW" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)M AGO" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)H AGO" }
        return "\(hours / 24)D AGO"
    }

    static func compactAge(_ date: Date, at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "NOW" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)M" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)H" }
        return "\(hours / 24)D"
    }

    #if targetEnvironment(simulator)
    func installVisualQA() {
        let userId = "visual-inbox-user"
        resetForIdentity(userId)
        let now = Date()
        threads = [
            InboxThread(
                id: "visual-thread-dispatch",
                title: "Aurora Dispatch",
                preview: "Gate 7 is open. Use the north approach.",
                at: now.addingTimeInterval(-180),
                unread: 2
            ),
            InboxThread(
                id: "visual-thread-shipper",
                title: "Phoenix Cold DC",
                preview: "Dock moved to 4B. Reefer plug is ready.",
                at: now.addingTimeInterval(-1_740),
                unread: 1
            ),
            InboxThread(
                id: "visual-thread-esang",
                title: "ESANG Operations",
                preview: "Route risk cleared after the I-10 wind check.",
                at: now.addingTimeInterval(-5_400),
                unread: 0
            ),
        ]
        unread = InboxUnreadEvidence(
            userId: userId,
            total: 3,
            byConversation: [
                "visual-thread-dispatch": 2,
                "visual-thread-shipper": 1,
            ],
            source: .visualQA
        )
        hasLoadedOnce = true
        lastRefreshAt = now
    }
    #endif
}

struct InboxBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 16, minHeight: 16)
                .background(Color.esangBlue, in: Capsule())
                .accessibilityLabel("\(count) unread")
        }
    }
}

struct InboxView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @StateObject private var store = InboxStore.shared
    @State private var activeThread: InboxThread?
    @State private var phoneDispatch: PhoneActivationDispatch?

    private var isVisualQA: Bool {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["EUSOTRIP_PULSE_VISUAL_STATE"]?.hasPrefix("inbox") == true
        #else
        return false
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                inboxHeader
                inboxContent
            }
            .padding(.horizontal, S.s2)
            .padding(.vertical, 2)
        }
        .navigationTitle("Inbox")
        .task {
            #if targetEnvironment(simulator)
            if isVisualQA {
                store.installVisualQA()
                return
            }
            #endif
            await store.refresh(auth: auth)
        }
        .onChange(of: auth.userId) { _, newUserId in
            guard !isVisualQA else { return }
            store.resetForIdentity(newUserId)
            Task { await store.refresh(auth: auth) }
        }
        .sheet(item: $activeThread) { thread in
            InboxThreadView(thread: thread)
        }
        .clipShape(ContainerRelativeShape())
    }

    private var inboxHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "message.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.esangBlue)
                Text("CONVERSATIONS")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                InboxBadge(count: store.unreadTotal)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(store.evidenceLabel(at: context.date))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(store.lastError == nil ? Color.esangBlue : Color.esangAmber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var inboxContent: some View {
        if let error = store.lastError, !store.hasLoadedOnce {
            messageState(
                icon: "exclamationmark.triangle.fill",
                title: "Inbox unavailable",
                detail: error,
                tint: .esangAmber,
                showPhoneAction: true
            )
        } else if store.isRefreshing && !store.hasLoadedOnce {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.75)
                Text("Loading conversations")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else if store.threads.isEmpty {
            messageState(
                icon: "tray",
                title: "No conversations",
                detail: "EusoTrip returned no threads for this identity.",
                tint: .esangBlue,
                showPhoneAction: true
            )
        } else {
            ForEach(store.threads) { thread in
                threadRow(thread)
            }
        }
    }

    private func threadRow(_ thread: InboxThread) -> some View {
        let unread = store.unreadCount(for: thread)
        return Button {
            activeThread = thread
            store.markReadAfterOpen(thread.id, auth: auth)
        } label: {
            HStack(alignment: .top, spacing: 7) {
                ZStack {
                    Circle()
                        .fill(unread > 0 ? Color.esangBlue.opacity(0.2) : Color.white.opacity(0.06))
                    Text(initials(thread.title))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(unread > 0 ? Color.esangBlue : .secondary)
                }
                .frame(width: 27, height: 27)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(thread.title)
                            .font(.system(size: 11, weight: unread > 0 ? .bold : .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 3)
                        if let at = thread.at {
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                Text(InboxStore.compactAge(at, at: context.date))
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        } else {
                            Image(systemName: "clock.badge.questionmark")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.esangAmber)
                                .accessibilityLabel("Message time unavailable")
                        }
                    }
                    Text(thread.preview.isEmpty ? "No message preview supplied" : thread.preview)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if case .failed = store.readSync[thread.id] {
                        Text("Read status not synchronized")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color.esangAmber)
                    }
                }
                if unread > 0 {
                    InboxBadge(count: unread)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(
                unread > 0 ? Color.esangBlue.opacity(0.08) : Color.esangCard,
                in: RoundedRectangle(cornerRadius: R.sm)
            )
        }
        .buttonStyle(.plain)
    }

    private func messageState(
        icon: String,
        title: String,
        detail: String,
        tint: Color,
        showPhoneAction: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .bold))
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if showPhoneAction {
                Button {
                    phoneDispatch = connectivity.requestPhoneActivation(
                        transcript: "open messages",
                        reply: "Opening your EusoTrip inbox on iPhone.",
                        destination: .messages
                    )
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "iphone.and.arrow.forward")
                        Text("Open Inbox on iPhone")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .foregroundStyle(.white)
                    .background(LinearGradient.esangPrimary, in: RoundedRectangle(cornerRadius: R.sm))
                }
                .buttonStyle(.plain)
            }
            if let phoneDispatch {
                Text(phoneReceipt(phoneDispatch))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(phoneDispatch == .unavailable ? Color.esangDanger : Color.esangAmber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(9)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.md))
        .overlay(RoundedRectangle(cornerRadius: R.md).stroke(tint.opacity(0.5), lineWidth: 1))
    }

    private func initials(_ title: String) -> String {
        let result = title.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return result.isEmpty ? "?" : result.uppercased()
    }

    private func phoneReceipt(_ dispatch: PhoneActivationDispatch) -> String {
        switch dispatch {
        case .sent: return "Inbox request sent to iPhone."
        case .queued: return "Inbox request queued until iPhone reconnects."
        case .unavailable: return "iPhone bridge unavailable. Open EusoTrip on iPhone."
        }
    }
}

struct InboxThreadView: View {
    let thread: InboxThread
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @StateObject private var inbox = InboxStore.shared
    @State private var messages: [InboxMessage] = []
    @State private var hasLoaded = false
    @State private var isSending = false
    @State private var lastError: String?
    @State private var sendNote: String?
    @State private var sendFailed = false
    @State private var phoneDispatch: PhoneActivationDispatch?
    @State private var showingQuickReplies = false

    private let quickReplies = [
        "On it.",
        "Copy, 10-4.",
        "Running 15 min behind.",
        "Arrived.",
    ]

    private var isVisualQA: Bool {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["EUSOTRIP_PULSE_VISUAL_STATE"] == "inbox-active"
        #else
        return false
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                threadHeader
                transcript
                replyRail
                openOnPhoneButton
                if let note = sendNote {
                    Text(note)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(
                            sendFailed
                                ? Color.esangDanger
                                : (note.contains("queued") ? Color.esangAmber : Color.esangGreen)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, S.s2)
            .padding(.vertical, 2)
        }
        .navigationTitle(thread.title)
        .task {
            #if targetEnvironment(simulator)
            if isVisualQA {
                installVisualMessages()
                return
            }
            #endif
            await loadTranscript()
        }
        .onChange(of: auth.userId) { _, _ in
            dismiss()
        }
        .sheet(isPresented: $showingQuickReplies) {
            InboxQuickReplyPicker(replies: quickReplies) { reply in
                Task { await send(reply) }
            }
        }
        .clipShape(ContainerRelativeShape())
    }

    private var threadHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if targetEnvironment(simulator)
            if isVisualQA {
                Text("LAYOUT QA · SIMULATOR FIXTURE")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.esangBlue)
            } else {
                readStateLabel
            }
            #else
            readStateLabel
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readStateLabel: some View {
        Group {
            switch inbox.readSync[thread.id] {
            case .syncing:
                Text("SYNCING READ STATUS")
                    .foregroundStyle(Color.esangBlue)
            case .confirmed:
                Text("READ STATUS CONFIRMED")
                    .foregroundStyle(Color.esangGreen)
            case .failed:
                Text("READ STATUS NOT SYNCED")
                    .foregroundStyle(Color.esangAmber)
            case nil:
                Text("CONVERSATION EVIDENCE")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 7, weight: .bold))
        .tracking(0.7)
    }

    @ViewBuilder
    private var transcript: some View {
        if !hasLoaded {
            HStack(spacing: 5) {
                ProgressView().scaleEffect(0.7)
                Text("Loading messages")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
        } else if let lastError {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.esangAmber)
                Text(lastError)
                    .font(.system(size: 9, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(7)
            .background(Color.esangAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: R.sm))
        } else if messages.isEmpty {
            Text("EusoTrip returned no messages in this conversation.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
        } else {
            ForEach(messages.suffix(8)) { message in
                messageBubble(message)
            }
        }
    }

    private func messageBubble(_ message: InboxMessage) -> some View {
        HStack {
            if message.isOwn { Spacer(minLength: 22) }
            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 2) {
                if !message.isOwn {
                    Text(message.senderName ?? "Sender name unavailable")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Text(message.content)
                    .font(.system(size: 10, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    if let at = message.at {
                        Text(at, style: .time)
                    } else {
                        Text("TIME UNAVAILABLE")
                    }
                    if message.delivery == .queued {
                        Text("QUEUED")
                            .foregroundStyle(Color.esangAmber)
                    }
                }
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                message.isOwn ? Color.esangBlue.opacity(0.22) : Color.esangCard,
                in: RoundedRectangle(cornerRadius: R.sm)
            )
            if !message.isOwn { Spacer(minLength: 22) }
        }
    }

    private var replyRail: some View {
        HStack(spacing: 5) {
            TextFieldLink(prompt: Text("Reply")) {
                HStack(spacing: 5) {
                    Image(systemName: "mic.fill")
                    Text(isSending ? "Sending" : "Speak reply")
                }
                .font(.system(size: 10, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 28)
                .foregroundStyle(.white)
                .background(LinearGradient.esangPrimary, in: RoundedRectangle(cornerRadius: R.sm))
            } onSubmit: { text in
                Task { await send(text) }
            }
            .disabled(isSending)

            Button {
                showingQuickReplies = true
            } label: {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 34, height: 28)
                    .foregroundStyle(Color.esangBlue)
                    .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
            }
            .disabled(isSending)
            .accessibilityLabel("Quick replies")
        }
    }

    private var openOnPhoneButton: some View {
        Button {
            phoneDispatch = connectivity.requestPhoneActivation(
                transcript: "open conversation \(thread.id)",
                reply: "Opening this conversation on your iPhone.",
                destination: .messages,
                conversationId: thread.id
            )
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "iphone.and.arrow.forward")
                Text(phoneButtonLabel)
            }
            .font(.system(size: 9, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 25)
            .foregroundStyle(phoneDispatch == .unavailable ? Color.esangAmber : Color.white)
            .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
            .overlay(
                RoundedRectangle(cornerRadius: R.sm)
                    .stroke(
                        phoneDispatch == .unavailable
                            ? Color.esangAmber.opacity(0.7)
                            : Color.esangBlue.opacity(0.45),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var phoneButtonLabel: String {
        switch phoneDispatch {
        case .sent: return "Sent to iPhone"
        case .queued: return "Queued for iPhone"
        case .unavailable: return "iPhone bridge unavailable"
        case nil: return "Continue on iPhone"
        }
    }

    private func loadTranscript() async {
        guard auth.isSignedIn,
              let requestedUserId = auth.userId,
              inbox.boundUserId == requestedUserId else {
            hasLoaded = true
            lastError = "Sign in on iPhone to load this conversation."
            return
        }
        do {
            let data = try await EsangClient(auth: auth).queryJSON(
                "messages.getMessages",
                input: ["conversationId": thread.id, "limit": 12]
            )
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable { let json: [RemoteMessage] }
                    let data: DataContainer
                }
                let result: Result
            }
            struct RemoteMessage: Decodable {
                let id: String
                let senderName: String?
                let content: String
                let type: String?
                let timestamp: String?
                let isOwn: Bool?
            }
            let rows = try JSONDecoder().decode(Envelope.self, from: data).result.data.json
            guard auth.userId == requestedUserId,
                  inbox.boundUserId == requestedUserId else { return }
            messages = rows.map { row in
                let content = row.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let type = (row.type ?? "message").replacingOccurrences(of: "_", with: " ")
                return InboxMessage(
                    id: row.id,
                    senderName: row.senderName,
                    content: content.isEmpty ? "\(type.capitalized) content unavailable" : content,
                    at: InboxStore.parseTimestamp(row.timestamp),
                    isOwn: row.isOwn ?? false,
                    delivery: row.isOwn == true ? .confirmed : .received
                )
            }
            hasLoaded = true
            lastError = nil
        } catch {
            guard auth.userId == requestedUserId,
                  inbox.boundUserId == requestedUserId else { return }
            hasLoaded = true
            lastError = InboxStore.compactError(
                error,
                fallback: "Can't load this conversation from EusoTrip."
            )
        }
    }

    private func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !isSending,
              auth.isSignedIn,
              let requestedUserId = auth.userId,
              inbox.boundUserId == requestedUserId else { return }
        isSending = true
        defer { isSending = false }
        sendNote = nil
        sendFailed = false
        let idempotencyKey = UUID().uuidString

        do {
            let data = try await EsangClient(auth: auth).mutateJSON(
                "messages.sendMessage",
                input: [
                    "conversationId": thread.id,
                    "content": text,
                    "type": "text",
                    "idempotencyKey": idempotencyKey,
                ]
            )
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable { let json: Receipt }
                    let data: DataContainer
                }
                let result: Result
            }
            struct Receipt: Decodable {
                let id: String
                let senderName: String?
                let content: String?
                let timestamp: String?
            }
            let receipt = try JSONDecoder().decode(Envelope.self, from: data).result.data.json
            guard auth.userId == requestedUserId,
                  inbox.boundUserId == requestedUserId else { return }
            messages.append(InboxMessage(
                id: receipt.id,
                senderName: receipt.senderName,
                content: receipt.content ?? text,
                at: InboxStore.parseTimestamp(receipt.timestamp),
                isOwn: true,
                delivery: .confirmed
            ))
            sendNote = "Reply confirmed by EusoTrip."
        } catch {
            guard auth.userId == requestedUserId,
                  inbox.boundUserId == requestedUserId else { return }
            guard InboxDeliveryPolicy.shouldQueue(error) else {
                sendFailed = true
                sendNote = InboxStore.compactError(
                    error,
                    fallback: "Reply was not accepted by EusoTrip."
                )
                return
            }
            let queueKey = OfflineQueue.shared.enqueueMessage(
                loadId: nil,
                to: thread.id,
                text: text,
                idempotencyKey: idempotencyKey
            )
            messages.append(InboxMessage(
                id: queueKey,
                senderName: auth.userName,
                content: text,
                at: Date(),
                isOwn: true,
                delivery: .queued
            ))
            sendNote = "Reply queued for server delivery."
        }
    }

    #if targetEnvironment(simulator)
    private func installVisualMessages() {
        let now = Date()
        messages = [
            InboxMessage(
                id: "visual-message-1",
                senderName: "Aurora Dispatch",
                content: "Gate 7 is open. Use the north approach.",
                at: now.addingTimeInterval(-240),
                isOwn: false,
                delivery: .received
            ),
            InboxMessage(
                id: "visual-message-2",
                senderName: "Michael Reyes",
                content: "Copy. Turning in from I-55 now.",
                at: now.addingTimeInterval(-180),
                isOwn: true,
                delivery: .confirmed
            ),
            InboxMessage(
                id: "visual-message-3",
                senderName: "Aurora Dispatch",
                content: "Your dock assignment is 4B.",
                at: now.addingTimeInterval(-90),
                isOwn: false,
                delivery: .received
            ),
        ]
        hasLoaded = true
        lastError = nil
    }
    #endif
}

private struct InboxQuickReplyPicker: View {
    @Environment(\.dismiss) private var dismiss
    let replies: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                Text("QUICK REPLY")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(Color.esangBlue)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(replies, id: \.self) { reply in
                    Button {
                        dismiss()
                        onSelect(reply)
                    } label: {
                        HStack(spacing: 5) {
                            Text(reply)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(2)
                            Spacer(minLength: 3)
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.esangBlue)
                        }
                        .padding(.horizontal, 7)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, S.s2)
            .padding(.vertical, 4)
        }
        .navigationTitle("Reply")
    }
}
