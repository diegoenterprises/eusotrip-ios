//
//  311_eSangThread.swift
//  EusoTrip — Shipper · eSang AI · Thread (Arc I).
//

import SwiftUI

/// Shared one-shot prefill bus. 313 Voice Listening writes the
/// transcribed audio here before posting `eusoShipperNavSwap` to
/// "311"; 311's body picks it up on `.onAppear` and clears the slot
/// so a stale prefill never leaks into a future ESANG visit. Avoids
/// the SwiftUI race where `onReceive(.eusoShipperNavSwap)` inside
/// 311 misses the post because the view body hasn't run yet by the
/// time RoleSurfaceRouter swaps the screen in.
@MainActor
final class EsangComposerPrefill: ObservableObject {
    static let shared = EsangComposerPrefill()
    var pending: String? = nil
    private init() {}
}

/// Shared one-shot conversation-id bus for load-thread launches.
/// 218 Dispatch Control's "Open chat thread" action resolves the
/// load → conversation via `messages.getOrCreateLoadConversation`,
/// writes the conversationId here, then posts navSwap to "311".
/// The screen registry currently constructs 311 with
/// `conversationId: ""` (no per-route binding), so without this bus
/// 311 would load empty — exactly the founder bug 2026-05-24
/// ("clicking actions opens a random ESANG chat that does nothing").
@MainActor
final class LoadConversationContext: ObservableObject {
    static let shared = LoadConversationContext()
    var pendingConversationId: String? = nil
    var pendingLoadNumber: String? = nil
    private init() {}
}

struct eSangThreadScreen: View {
    let theme: Theme.Palette
    let conversationId: String
    var body: some View {
        Shell(theme: theme) { eSangThreadBody(conversationId: conversationId) } nav: { shipperLifecycleNav() }
    }
}

/// Decodable view of `messages.getMessages` returns. Server fields
/// `content` / `timestamp` / `isOwn` are remapped via CodingKeys so
/// the view code keeps using `m.body` / `m.createdAt` / `m.isMine`.
/// Migrating to the canonical `messages` router fixed two bugs:
/// (1) `messaging.getMessages` returned `{items:[...]}` (shape mismatch
/// with the flat-array decoder here); (2) the `body` field name on
/// the wire was always `content` so decoding was failing silently.
private struct eSangChatMessage: Decodable, Identifiable, Hashable {
    let id: String
    let senderId: String?
    let senderName: String?
    let body: String
    let createdAt: String
    let isMine: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case senderId
        case senderName
        case body = "content"
        case createdAt = "timestamp"
        case isMine = "isOwn"
    }
}

private struct eSangThreadBody: View {
    @Environment(\.palette) private var palette
    let conversationId: String
    /// Resolved conversationId — overrides the registry-supplied
    /// empty string when `LoadConversationContext` has a pending
    /// value (218 Dispatch Control flow). Defaults to the param.
    @State private var resolvedConversationId: String = ""
    @State private var loadNumberLabel: String? = nil
    @State private var messages: [eSangChatMessage] = []
    @State private var draft: String = ""
    @State private var sending: Bool = false
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Inline send error. Was `catch { /* surface inline */ }` —
    /// the comment promised but the impl swallowed; founder bug
    /// 2026-05-24 (tapped send, nothing visible happened).
    @State private var sendError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 56)
            ScrollView { VStack(alignment: .leading, spacing: 8) { messagesList }.padding(.horizontal, 14).padding(.top, Space.s2) }
            composer
        }
        .task {
            // Resolve conversationId first — the registry constructs
            // 311 with an empty conversationId, so we have to drain
            // LoadConversationContext (set by 218 Dispatch Control
            // before nav-swap) before firing load(). Without this
            // load() bails with the empty-conversation error every
            // time the user arrives via the Dispatch Control flow.
            if conversationId.isEmpty, let pending = LoadConversationContext.shared.pendingConversationId, !pending.isEmpty {
                resolvedConversationId = pending
                loadNumberLabel = LoadConversationContext.shared.pendingLoadNumber
                LoadConversationContext.shared.pendingConversationId = nil
                LoadConversationContext.shared.pendingLoadNumber = nil
            } else {
                resolvedConversationId = conversationId
            }
            await load()
        }
        .onAppear {
            // 313 ESANG Voice Listening writes the Gemini-transcribed
            // audio into the shared `EsangComposerPrefill` bus before
            // posting navSwap to 311. The notification fires before
            // this view exists, so a per-view onReceive misses it —
            // hence the shared bus. Drain on appear, clear so the
            // next ESANG visit starts blank.
            if let p = EsangComposerPrefill.shared.pending, !p.isEmpty {
                draft = p
                EsangComposerPrefill.shared.pending = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                // Rebranded 2026-05-24: founder mandate — Messages is
                // for load conversations between shipper / catalyst /
                // driver. ESANG AI is a separate surface (orb-accessed).
                // The old "SHIPPER · ESANG · THREAD" header made users
                // think they were chatting with the AI; this header
                // makes it clear they're messaging the people on the
                // load.
                Text("SHIPPER · LOAD MESSAGE THREAD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            if let label = loadNumberLabel, !label.isEmpty {
                Text("Load \(label)").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            }
        }
    }

    @ViewBuilder
    private var messagesList: some View {
        if loading { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        else if let err = loadError {
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn't load messages").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                Button("Retry") { Task { await load() } }
                    .font(EType.caption)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        else if messages.isEmpty {
            // Founder bug 2026-05-24: empty state was a literal blank
            // scrollview — looked indistinguishable from a broken
            // screen. This empty state hints what to do next.
            VStack(alignment: .leading, spacing: 6) {
                Text("No messages yet").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("Send the first message to start the conversation with the carrier or driver on this load.").font(EType.caption).foregroundStyle(palette.textSecondary)
            }.padding(.top, Space.s4)
        }
        else {
            ForEach(messages) { m in bubble(m) }
        }
    }

    private func bubble(_ m: eSangChatMessage) -> some View {
        HStack {
            if m.isMine == true { Spacer(minLength: 40) }
            VStack(alignment: m.isMine == true ? .trailing : .leading, spacing: 2) {
                Text(dashIfEmpty(m.senderName)).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Text(m.body).font(EType.body).foregroundStyle(m.isMine == true ? .white : palette.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(m.isMine == true ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(m.isMine == true ? .clear : palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(humanISO(m.createdAt, format: "HH:mm")).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            if m.isMine != true { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        VStack(spacing: 4) {
            if let err = sendError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    Spacer()
                    Button("Dismiss") { sendError = nil }
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
            }
            HStack(spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical).lineLimit(1...4).textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button { Task { await send() } } label: {
                    if sending { ProgressView().tint(.white).frame(width: 36, height: 36).background(LinearGradient.diagonal).clipShape(Circle()) }
                    else {
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(LinearGradient.diagonal).clipShape(Circle())
                    }
                }.buttonStyle(.plain).disabled(sending || draft.isEmpty || resolvedConversationId.isEmpty)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(palette.bgCard.opacity(0.95))
    }

    private func load() async {
        loading = true; loadError = nil
        // 311 is reused as the in-place destination for both 310's
        // row taps (real conversationId) and for direct nav-swaps
        // (which legacy callers used to push with conversationId="").
        // An empty conversationId surfaces as "No conversation
        // selected" so the user gets a real signal instead of an
        // empty page that the founder bug 2026-05-24 flagged as
        // "doesnt work".
        guard !resolvedConversationId.isEmpty else {
            loadError = "No conversation selected. Open a load thread from the dispatch board or the messages list."
            loading = false
            return
        }
        // Canonical `messages.getMessages` requires `limit` (default 50
        // server-side, but the procedure marks it required in Zod).
        struct In: Encodable { let conversationId: String; let limit: Int }
        do {
            let m: [eSangChatMessage] = try await EusoTripAPI.shared.query(
                "messages.getMessages",
                input: In(conversationId: resolvedConversationId, limit: 50)
            )
            messages = m
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func send() async {
        sending = true
        sendError = nil
        // Guard: empty conversationId means we have no thread to send
        // to. Surface a real error instead of firing into the void.
        guard !resolvedConversationId.isEmpty else {
            sendError = "No conversation selected — open a load thread first."
            sending = false
            return
        }
        // Server-side schema is `{conversationId, content, type}` —
        // not `body`. Old `messaging.sendMessage` route accepted
        // `body` only as a deprecation shim; canonical
        // `messages.sendMessage` is strict so we send `content`.
        // Out: the server returns the full message envelope
        // {id, conversationId, senderId, senderName, content, …} —
        // NOT {success:Bool}. The old `Out{success:Bool}` decoder
        // failed every call, silent-caught the error, and the
        // founder saw "nothing happens when I tap send". Lenient
        // decoder accepts whatever fields are present.
        struct In: Encodable { let conversationId: String; let content: String; let type: String }
        struct Out: Decodable {
            let id: String?
            let conversationId: String?
        }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "messages.sendMessage",
                input: In(conversationId: resolvedConversationId, content: draft, type: "text")
            )
            draft = ""
            await load()
        } catch {
            sendError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("311 · Thread · Night") {
    eSangThreadScreen(theme: Theme.dark, conversationId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("311 · Thread · Afternoon") {
    eSangThreadScreen(theme: Theme.light, conversationId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
