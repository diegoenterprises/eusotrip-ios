//
//  InboxView.swift
//  EusoTrip Watch App
//
//  Last-3 conversation threads from messages.list. Tap a thread to push
//  to a minimal thread view with canned replies + voice reply.
//

import SwiftUI

struct InboxThread: Identifiable, Equatable {
    let id: String
    let title: String
    let preview: String
    let at: Date
    let unread: Bool
}

@MainActor
final class InboxStore: ObservableObject {
    static let shared = InboxStore()
    @Published var threads: [InboxThread] = [
        .init(id: "disp-sarah", title: "Sarah (Dispatch)", preview: "You good for an 0700 pickup in Dallas?", at: Date().addingTimeInterval(-300), unread: true),
        .init(id: "broker-pacco", title: "Pacco Logistics", preview: "Rate con attached. Confirm when you can.", at: Date().addingTimeInterval(-3600), unread: false),
        .init(id: "esang-coach", title: "Esang Coach", preview: "Nice run yesterday — 98% on-time.", at: Date().addingTimeInterval(-24 * 3600), unread: false)
    ]

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
                let title: String?
                let preview: String?
                let updatedAt: String?
                let unread: Bool?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            threads = env.result.data.json.prefix(3).map {
                InboxThread(
                    id: $0.id,
                    title: $0.title ?? "Thread",
                    preview: $0.preview ?? "",
                    at: ISO8601DateFormatter.iso.date(from: $0.updatedAt ?? "") ?? Date(),
                    unread: $0.unread ?? false
                )
            }
        } catch {}
    }
}

struct InboxView: View {
    @EnvironmentObject var auth: AuthStore
    @StateObject private var store = InboxStore.shared
    @State private var activeThread: InboxThread?

    var body: some View {
        ScrollView {
            VStack(spacing: S.s1) {
                ForEach(store.threads) { thread in
                    Button {
                        activeThread = thread
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(thread.title).font(.system(size: 12, weight: .bold))
                                Spacer()
                                if thread.unread {
                                    Circle().fill(Color.esangBlue).frame(width: 6, height: 6)
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
            .padding(.vertical, S.s1)
        }
        .navigationTitle("Inbox")
        .task { await store.refresh(auth: auth) }
        .sheet(item: $activeThread) { thread in
            InboxThreadView(thread: thread)
        }
    }
}

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
                            _ = try? await EsangClient(auth: auth).mutateJSON(
                                "messages.send",
                                input: ["threadId": thread.id, "text": reply]
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
    }
}
