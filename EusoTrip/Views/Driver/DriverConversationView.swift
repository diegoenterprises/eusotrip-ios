//
//  DriverConversationView.swift
//  EusoTrip — Full in-thread conversation surface.
//
//  Presented when the driver taps a row in `DriverMessagesSheet`. Renders
//  the in-thread transcript (left/right bubbles, timestamps, read receipts)
//  and a composer that supports:
//
//    • Text messages
//    • Image attachments (PhotosPicker — BOL snap, dashboard light,
//      reefer gauge evidence, DVIR photo, etc.)
//    • P2P EusoWallet money transfers (backed by Stripe Connect on the
//      server — driver-to-driver settle for team partners, shared fuel,
//      tolls, etc.). Only visible when the thread's recipient has an
//      EusoWallet peer profile (InboxThread.allowsTransfer == true).
//
//  Design invariants (kept in sync with DriverTabPanes.swift conventions):
//    • §2: no custom chrome — the sheet's own presentation owns nav.
//    • §4.3: hairline under the top bar, chat surface lives on bgPage.
//    • §7: breathe density — Space.s3/s4/s5 spacing, ActiveCard grouping
//          where appropriate.
//
//  All transcript state is in-memory for this wave. Wave-6 swaps the
//  seed messages + `send(_:)` handler for the live `messages.send` tRPC
//  procedure without touching the UI (same pattern used in
//  `DrivereSangCoachSheet`).
//

import SwiftUI
import PhotosUI

struct DriverConversationView: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    let thread: InboxThread

    // ──────────── Transcript state ────────────

    @State private var messages: [ChatMessage] = []
    @State private var draft: String = ""
    @FocusState private var composerFocused: Bool

    // ──────────── Attachment + transfer state ────────────

    @State private var pickedPhoto: PhotosPickerItem? = nil
    /// Inline preview of the photo the driver picked but hasn't sent yet —
    /// sits above the composer like a sticky thumbnail until they hit
    /// send or discard it.
    @State private var pendingImage: Data? = nil
    @State private var showAttachMenu: Bool = false
    @State private var showTransferSheet: Bool = false

    // ──────────── Backend + realtime state ────────────

    /// Flipped to true once `messages.getMessages` lands the first page.
    /// While `false` the transcript shows a skeleton placeholder so the
    /// UI doesn't appear empty on open.
    @State private var didLoad: Bool = false
    /// In-flight send — disables the composer send button and keeps the
    /// optimistic bubble in a pending state until the tRPC mutation
    /// returns (or fails).
    @State private var isSending: Bool = false
    /// Surfaces transient errors from send/upload/transfer mutations so
    /// the driver knows to retry. Cleared on the next successful send.
    @State private var lastErrorMessage: String? = nil
    /// WebSocket observer handle for `.eusoMessageReceived`. Registered
    /// in `.onAppear` and torn down in `.onDisappear`.
    @State private var realtimeObserver: NSObjectProtocol? = nil

    // ──────────── Unsend message state ────────────
    //
    // A long-press on an outbound bubble surfaces a context menu with an
    // "Unsend" option. We stage the target message on `pendingUnsend` and
    // raise a confirmation dialog — unsend is destructive and pulls the
    // message on the recipient's side too, so we want an explicit
    // opt-in before firing `messages.unsendMessage`.
    @State private var pendingUnsend: ChatMessage? = nil

    // ──────────── Derived ────────────

    /// Short initials for the peer avatar bubble in the header.
    private var initials: String {
        thread.title
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            IridescentHairline()
            if let err = lastErrorMessage {
                errorBanner(err)
            }
            transcript
            if let data = pendingImage {
                pendingImageStrip(data)
            }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.bgPage)
        .contentShape(Rectangle())
        .onTapGesture { composerFocused = false }
        // Uniform cafe-door entrance the way every other screen lands.
        .screenTileRoot()
        // Hydrate the transcript from `messages.getMessages`, join the
        // `conversation:<id>` WebSocket room, mark everything read, and
        // register the `.eusoMessageReceived` observer.
        .task {
            await loadTranscript()
        }
        .onAppear {
            RealtimeService.shared.joinConversation(thread.id)
            UnreadMessageStore.shared.didOpenConversation(thread.id)
            let token = NotificationCenter.default.addObserver(
                forName: .eusoMessageReceived, object: nil, queue: .main
            ) { note in
                Task { @MainActor in
                    handleInbound(note)
                }
            }
            realtimeObserver = token
        }
        .onDisappear {
            if let realtimeObserver {
                NotificationCenter.default.removeObserver(realtimeObserver)
            }
            realtimeObserver = nil
            RealtimeService.shared.leaveConversation(thread.id)
            UnreadMessageStore.shared.didCloseConversation(thread.id)
        }
        // Incoming PhotosPicker selection → load the raw image data so we
        // can both preview it inline + ship it on send.
        .onChange(of: pickedPhoto) { _, newValue in
            Task {
                if let item = newValue,
                   let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run { pendingImage = data }
                }
            }
        }
        .sheet(isPresented: $showTransferSheet) {
            ChatMoneyTransferSheet(
                recipientName: thread.title,
                onConfirm: { payload in
                    Task { await sendTransfer(payload) }
                }
            )
            .environment(\.palette, palette)
            .presentationDetents([.medium])
            .eusoCloseX()
        }
        // Unsend confirmation. Long-press on an outbound bubble stages
        // `pendingUnsend`; the dialog fires the actual mutation.
        .confirmationDialog(
            "Unsend this message?",
            isPresented: Binding(
                get: { pendingUnsend != nil },
                set: { if !$0 { pendingUnsend = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingUnsend
        ) { target in
            Button("Unsend", role: .destructive) {
                Task { @MainActor in
                    await performUnsend(target)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingUnsend = nil
            }
        } message: { _ in
            Text("This removes it on both sides. The recipient will see \"Message unsent\" in its place.")
        }
    }

    // MARK: Error banner

    @ViewBuilder
    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Button {
                lastErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.s5)
        .padding(.vertical, Space.s2)
        .background(palette.bgCardSoft)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Brand.danger.opacity(0.4)).frame(height: 1)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.s3) {
            // Avatar
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral)
                Text(initials)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(thread.title)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(thread.subtitle)
                    .font(EType.micro).tracking(0.5)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close conversation")
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if !didLoad {
                    transcriptSkeleton
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)
                } else if messages.isEmpty {
                    emptyTranscript
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s5)
                } else {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        ForEach(messages) { m in
                            bubble(m).id(m.id)
                        }
                    }
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)
                    .padding(.bottom, Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .refreshable {
                await loadTranscript()
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Placeholder bubbles rendered before `messages.getMessages` lands.
    /// Matches the final bubble layout so the transition is less jarring.
    @ViewBuilder
    private var transcriptSkeleton: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            skeletonBubble(outbound: false, width: 220)
            skeletonBubble(outbound: true, width: 160)
            skeletonBubble(outbound: false, width: 250)
            skeletonBubble(outbound: true, width: 120)
        }
        .redacted(reason: .placeholder)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func skeletonBubble(outbound: Bool, width: CGFloat) -> some View {
        HStack {
            if outbound { Spacer(minLength: 40) }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral)
                .frame(width: width, height: 34)
            if !outbound { Spacer(minLength: 40) }
        }
    }

    /// Empty-state for a brand-new conversation — nudges the driver to
    /// break the ice without feeling prescriptive.
    @ViewBuilder
    private var emptyTranscript: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(palette.textTertiary)
            Text("No messages yet")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("Say hi to \(thread.title.components(separatedBy: " ").first ?? "them") below — they'll get a push the moment it lands.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s6)
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: Space.s2) {
            if m.from == .me { Spacer(minLength: 40) }
            VStack(alignment: m.from == .me ? .trailing : .leading, spacing: 4) {
                bubbleBody(m)
                    .frame(maxWidth: 280, alignment: m.from == .me ? .trailing : .leading)
                HStack(spacing: 4) {
                    Text(m.time, format: .dateTime.hour().minute())
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                    if m.from == .me {
                        Image(systemName: m.read ? "checkmark.circle.fill" : "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            // Doctrine §2.1: brand accent on "read" state must be the
                            // gradient, not a flat Brand.info tint. §2.3: ternary shape-style
                            // branches wrapped in AnyShapeStyle so SwiftUI compiles on iOS 17.
                            .foregroundStyle(m.read
                                             ? AnyShapeStyle(LinearGradient.diagonal)
                                             : AnyShapeStyle(palette.textTertiary))
                    }
                }
            }
            if m.from == .other { Spacer(minLength: 40) }
        }
        // Long-press menu on outbound bubbles → "Unsend" (destructive)
        // + "Copy" for both sides when the message is plain text. We
        // gate Unsend on `serverId != nil` so optimistic-only bubbles
        // that haven't been ACKed by the server can't trigger a
        // mutation with no id to aim at.
        .contextMenu {
            if m.from == .me && !m.unsent && m.serverId != nil {
                Button(role: .destructive) {
                    pendingUnsend = m
                } label: {
                    Label("Unsend", systemImage: "arrow.uturn.backward")
                }
            }
            if !m.unsent && !m.text.isEmpty && m.transfer == nil {
                Button {
                    UIPasteboard.general.string = m.text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }

    @ViewBuilder
    private func bubbleBody(_ m: ChatMessage) -> some View {
        if m.unsent {
            // Sender pulled the message. Neutral italic placeholder so
            // the thread stays chronological without leaking content.
            Text("Message unsent")
                .font(EType.body)
                .italic()
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(palette.borderFaint)
                        )
                )
        } else if let payload = m.transfer {
            // Money transfer card — styled distinct from plain chat bubbles
            // so the driver can spot a transaction in the scroll at a glance.
            transferCard(payload, outbound: m.from == .me)
        } else if let data = m.imageData, let ui = uiImage(from: data) {
            // Image attachment (local preview for the optimistic path
            // before the server ACK). Constrain the preview width so the
            // bubble doesn't blow past the 280pt chat column.
            imageBubble(outbound: m.from == .me, caption: m.text) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            }
        } else if let urlStr = m.imageURL,
                  let url = URL(string: urlStr) {
            // Remote image attachment (from the server transcript).
            // `data:` URLs decode in-memory; plain https URLs pull
            // over the network. `AsyncImage` handles both.
            imageBubble(outbound: m.from == .me, caption: m.text) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(palette.tintNeutral)
                            .overlay(
                                ProgressView().controlSize(.small)
                            )
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(palette.tintNeutral)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(palette.textTertiary)
                            )
                    @unknown default:
                        Color.clear
                    }
                }
            }
        } else {
            // Plain text bubble.
            Text(m.text)
                .font(EType.body)
                .foregroundStyle(m.from == .me ? .white : palette.textPrimary)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .background(
                    Group {
                        if m.from == .me {
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .fill(LinearGradient.diagonal)
                        } else {
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .fill(palette.bgCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                        .strokeBorder(palette.borderFaint)
                                )
                        }
                    }
                )
        }
    }

    /// Shared image-bubble shell so both local-preview and AsyncImage paths
    /// render with the same chrome (caption, outbound gradient, border).
    @ViewBuilder
    private func imageBubble<Content: View>(
        outbound: Bool,
        caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            content()
                .frame(maxWidth: 240, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
            if !caption.isEmpty {
                Text(caption)
                    .font(EType.body)
                    .foregroundStyle(outbound ? .white : palette.textPrimary)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(outbound ? AnyShapeStyle(LinearGradient.diagonal)
                                : AnyShapeStyle(palette.bgCard))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(outbound ? Color.clear : palette.borderFaint)
        )
    }

    /// EusoWallet transfer card. Reused by both inbound and outbound —
    /// the gradient/green tint flips based on direction.
    @ViewBuilder
    private func transferCard(_ payload: ChatTransferPayload, outbound: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(outbound ? .white : Brand.success)
                VStack(alignment: .leading, spacing: 1) {
                    Text(outbound ? "You sent" : "You received")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(outbound ? Color.white.opacity(0.8) : palette.textSecondary)
                    Text(payload.formattedAmount)
                        .font(EType.numeric)
                        .foregroundStyle(outbound ? .white : palette.textPrimary)
                }
                Spacer()
                statusBadge(payload.status, outbound: outbound)
            }
            if let memo = payload.memo, !memo.isEmpty {
                Text(memo)
                    .font(EType.caption)
                    .foregroundStyle(outbound ? Color.white.opacity(0.9) : palette.textSecondary)
            }
            Text("EusoWallet · powered by Stripe")
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(outbound ? Color.white.opacity(0.7) : palette.textTertiary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(width: 260, alignment: .leading)
        .background(
            Group {
                if outbound {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(LinearGradient.diagonal)
                } else {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(Brand.success.opacity(0.35), lineWidth: 1.2)
                        )
                }
            }
        )
    }

    @ViewBuilder
    private func statusBadge(_ status: ChatTransferPayload.Status, outbound: Bool) -> some View {
        switch status {
        case .pending:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                    .tint(outbound ? .white : palette.textSecondary)
                Text("Pending")
                    .font(EType.micro)
                    .foregroundStyle(outbound ? .white : palette.textSecondary)
            }
        case .sent:
            Label("Sent", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(EType.micro)
                .foregroundStyle(outbound ? .white : Brand.success)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(EType.micro)
                .foregroundStyle(Brand.danger)
        }
    }

    // MARK: Pending image strip

    @ViewBuilder
    private func pendingImageStrip(_ data: Data) -> some View {
        if let ui = uiImage(from: data) {
            HStack(spacing: Space.s3) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Attached photo")
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                    Text("Tap send to share with \(thread.title.components(separatedBy: " ").first ?? "them").")
                        .font(EType.micro)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Button {
                    pendingImage = nil
                    pickedPhoto = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove attached photo")
            }
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s2)
            .background(palette.bgCardSoft)
            .overlay(alignment: .top) { Divider().overlay(palette.borderFaint) }
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Space.s2) {
            // `+` attach menu. PhotosPicker wraps the photo option so the
            // picker owns its own presentation; the send-money option pops
            // a confirmation sheet.
            Menu {
                // PhotosPicker drives the picked item via a binding.
                Button {
                    showAttachMenu = false
                    // Trigger programmatically using `showPhotoPicker`
                    // via delayed toggle pattern so the menu dismisses
                    // before the picker presents.
                } label: {
                    Label("Photo", systemImage: "photo.on.rectangle")
                }
                if thread.allowsTransfer {
                    Button {
                        showTransferSheet = true
                    } label: {
                        Label("Send money", systemImage: "dollarsign.circle")
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .accessibilityLabel("Attach")

            // Direct PhotosPicker — offered alongside the menu as a
            // single-tap photo shortcut. This avoids the menu-then-picker
            // round-trip for the most common case.
            PhotosPicker(selection: $pickedPhoto,
                         matching: .images,
                         photoLibrary: .shared()) {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .accessibilityLabel("Add photo")

            if thread.allowsTransfer {
                Button {
                    showTransferSheet = true
                } label: {
                    Image(systemName: "dollarsign")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Brand.success)
                        .frame(width: 40, height: 40)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(Brand.success.opacity(0.35))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send money via EusoWallet")
            }

            TextField("Message \(thread.title.components(separatedBy: " ").first ?? "")…",
                      text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($composerFocused)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )

            Button {
                sendComposed()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(LinearGradient.diagonal)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.55)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, Space.s5)
        .padding(.bottom, Space.s4 + Device.safeBottom)
        .padding(.top, Space.s2)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImage != nil
    }

    // MARK: Actions (live backend)

    /// Fetch the first page of transcript from `messages.getMessages`,
    /// then mark the whole thread read. Called from `.task` on mount
    /// and also from the refresh hook.
    private func loadTranscript() async {
        do {
            let fetched = try await EusoTripAPI.shared.messaging.getMessages(
                conversationId: thread.id,
                limit: 60
            )
            messages = fetched.map(toChat)
            didLoad = true
            lastErrorMessage = nil

            // Mark-as-read once the transcript is visible. Fire-and-forget
            // so the UI doesn't wait on the mutation.
            Task {
                _ = try? await EusoTripAPI.shared.messaging.markAsRead(
                    conversationId: thread.id
                )
                UnreadMessageStore.shared.refresh()
            }
        } catch EusoTripAPIError.unauthenticated {
            lastErrorMessage = "Please sign in to view this conversation."
            didLoad = true
        } catch {
            lastErrorMessage = "Couldn't load messages — \(error.localizedDescription)"
            didLoad = true
        }
    }

    /// Send the current composer draft (+ optional image attachment).
    /// Optimistically appends a local bubble, then reconciles with the
    /// server ACK by stamping the real `serverId` onto the ghost.
    private func sendComposed() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = pendingImage
        guard !text.isEmpty || image != nil else { return }
        if isSending { return }

        let localId = UUID()
        let optimistic = ChatMessage(
            from: .me,
            text: text,
            imageData: image,
            time: Date()
        )
        // ChatMessage's `id` is auto-generated; use the struct's id as
        // the local anchor we reconcile against.
        let anchor = optimistic.id
        messages.append(optimistic)
        draft = ""
        pendingImage = nil
        pickedPhoto = nil
        composerFocused = false

        isSending = true
        Task {
            defer { isSending = false }
            do {
                if let imageData = image {
                    // Attachment path — uploadAttachment inserts a row of
                    // messageType "image" with the data URL embedded in
                    // the attachments table. We ignore the returned
                    // `messageId` here because the WebSocket fan-out will
                    // land the same row and reconcile via serverId dedupe.
                    let result = try await EusoTripAPI.shared.messaging.uploadAttachment(
                        conversationId: thread.id,
                        data: imageData,
                        fileName: "photo-\(Int(Date().timeIntervalSince1970)).jpg",
                        mimeType: "image/jpeg"
                    )
                    stampServerId(result.messageId, onLocalId: anchor)

                    // If the driver also typed a caption, send it as a
                    // follow-up text row so the transcript has both.
                    if !text.isEmpty {
                        _ = try await EusoTripAPI.shared.messaging.sendMessage(
                            conversationId: thread.id,
                            content: text,
                            type: "text"
                        )
                    }
                } else {
                    let ack = try await EusoTripAPI.shared.messaging.sendMessage(
                        conversationId: thread.id,
                        content: text,
                        type: "text"
                    )
                    stampServerId(ack.id, onLocalId: anchor)
                }
                _ = localId // keep the localId alive for future debug
                lastErrorMessage = nil
            } catch {
                // Roll the optimistic bubble back and surface the error.
                messages.removeAll { $0.id == anchor }
                lastErrorMessage = "Send failed — \(error.localizedDescription)"
                // Put the draft back so the driver can retry.
                if !text.isEmpty { draft = text }
                if let img = image { pendingImage = img }
            }
        }
    }

    /// Fire a typed transfer card through `messages.sendPayment`. The
    /// backend debits the caller's EusoWallet, credits the recipient,
    /// and posts a `payment_sent` row — we optimistically surface the
    /// pending card and flip it to `.sent` or `.failed` on ACK.
    private func sendTransfer(_ payload: ChatTransferPayload) async {
        let optimistic = ChatMessage(
            from: .me,
            text: "",
            transfer: payload,
            time: Date()
        )
        let anchor = optimistic.id
        messages.append(optimistic)

        do {
            let amountDollars = Double(payload.amountCents) / 100.0
            let ack = try await EusoTripAPI.shared.messaging.sendPayment(
                conversationId: thread.id,
                amount: amountDollars,
                currency: "USD",
                note: payload.memo,
                type: "send"
            )
            if let idx = messages.firstIndex(where: { $0.id == anchor }) {
                var updated = messages[idx]
                updated.serverId = ack.id
                let newStatus: ChatTransferPayload.Status =
                    (ack.status == "completed" || ack.status == "sent") ? .sent : .pending
                updated.transfer = ChatTransferPayload(
                    amountCents: payload.amountCents,
                    recipientName: payload.recipientName,
                    memo: payload.memo,
                    status: newStatus
                )
                messages[idx] = updated
            }
            lastErrorMessage = nil
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == anchor }) {
                var updated = messages[idx]
                updated.transfer = ChatTransferPayload(
                    amountCents: payload.amountCents,
                    recipientName: payload.recipientName,
                    memo: payload.memo,
                    status: .failed
                )
                messages[idx] = updated
            }
            lastErrorMessage = "Transfer failed — \(error.localizedDescription)"
        }
    }

    /// WebSocket event handler — reconcile inbound `message:new` events
    /// against the local transcript. Duplicates (messages we sent that
    /// echo back via the socket) are dropped by `serverId` match.
    private func handleInbound(_ note: Notification) {
        guard let info = note.userInfo else { return }
        let convId = (info["conversationId"] as? String)
            ?? (info["conversationId"] as? Int).map(String.init)
            ?? ""
        guard convId == thread.id else { return }

        let remoteId = (info["messageId"] as? String)
            ?? (info["messageId"] as? Int).map(String.init)
            ?? ""
        if !remoteId.isEmpty,
           messages.contains(where: { $0.serverId == remoteId }) {
            return
        }

        // Refetch to get canonical ordering + the full server payload
        // (readBy, metadata, attachments). This is the simplest reliable
        // path — the transcript is small (<=60 rows) so the extra hit
        // is cheap, and it keeps the dedupe logic minimal.
        Task { await loadTranscript() }
    }

    // MARK: Unsend

    /// Fires `messages.unsendMessage` for the target bubble. Optimistically
    /// flips `unsent = true` on the local copy so the bubble swaps to the
    /// neutral "Message unsent" placeholder immediately; if the mutation
    /// fails we restore the original content and surface the error in the
    /// banner so the driver can retry.
    @MainActor
    private func performUnsend(_ message: ChatMessage) async {
        pendingUnsend = nil
        guard let serverId = message.serverId else {
            lastErrorMessage = "Can't unsend — message still sending."
            return
        }
        guard let idx = messages.firstIndex(where: { $0.id == message.id }) else { return }
        // Snapshot for rollback.
        let original = messages[idx]
        withAnimation(.easeInOut(duration: 0.18)) {
            messages[idx].unsent = true
        }
        do {
            _ = try await EusoTripAPI.shared.messaging.unsendMessage(messageId: serverId)
            lastErrorMessage = nil
        } catch {
            // Mutation failed — restore the original content and surface
            // the error inline so the driver knows to retry.
            if let currentIdx = messages.firstIndex(where: { $0.id == message.id }) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    messages[currentIdx] = original
                }
            }
            lastErrorMessage = "Couldn't unsend — \(error.localizedDescription)"
        }
    }

    // MARK: Reconciliation

    /// Stamp the real server id onto an optimistic message once the
    /// mutation returns. This lets the WebSocket echo dedupe against
    /// our local copy instead of appending a duplicate bubble.
    private func stampServerId(_ serverId: String, onLocalId anchor: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == anchor }) else { return }
        var updated = messages[idx]
        updated.serverId = serverId
        updated.read = true
        messages[idx] = updated
    }

    /// Translate a backend `MessagingMessage` into the local
    /// `ChatMessage` the bubble renderer consumes.
    private func toChat(_ m: MessagingMessage) -> ChatMessage {
        let sender: ChatMessage.Sender = (m.isOwn == true) ? .me : .other
        let ts = isoDate(m.timestamp) ?? Date()

        var chat = ChatMessage(
            from: sender,
            text: m.content,
            time: ts,
            read: (m.read ?? false)
        )
        chat.serverId = m.id

        switch (m.type ?? "text").lowercased() {
        case "image":
            if let url = m.metadata?.fileUrl, !url.isEmpty {
                chat.imageURL = url
                // The backend stores "[image] filename.jpg" as the
                // content placeholder; don't render that as a caption
                // because it's noise — use an empty string instead so
                // the bubble shows just the image.
                chat.text = ""
            }
        case "payment_sent", "payment_request":
            if let amount = m.metadata?.amount {
                let cents = Int((amount * 100.0).rounded())
                let status: ChatTransferPayload.Status = {
                    switch (m.metadata?.status ?? "").lowercased() {
                    case "completed", "sent", "paid": return .sent
                    case "failed", "declined":         return .failed
                    default:                            return .pending
                    }
                }()
                chat.transfer = ChatTransferPayload(
                    amountCents: cents,
                    recipientName: thread.title,
                    memo: m.metadata?.note,
                    status: status
                )
                chat.text = ""
            }
        default:
            break
        }
        return chat
    }

    private func isoDate(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    // MARK: Helpers

    private func uiImage(from data: Data) -> UIImage? {
        #if canImport(UIKit)
        return UIImage(data: data)
        #else
        return nil
        #endif
    }
}

// MARK: - ChatMoneyTransferSheet (EusoWallet P2P)

/// Compact P2P transfer sheet. Scoped to a single recipient (the active
/// thread participant) so the driver can't accidentally fire money into
/// the wrong conversation. Amount, optional memo, and a single commit
/// action. Presenting this sheet is the "explicit user permission"
/// checkpoint per safety rules — the caller executes the transfer only
/// when `onConfirm` fires.
struct ChatMoneyTransferSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    let recipientName: String
    /// Invoked when the driver hits the confirm CTA. Caller is responsible
    /// for surfacing the resulting transfer card in the conversation.
    let onConfirm: (ChatTransferPayload) -> Void

    @State private var amountText: String = ""
    @State private var memo: String = ""
    @FocusState private var amountFocused: Bool

    private var amountCents: Int {
        let cleaned = amountText
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let dollars = Double(cleaned), dollars > 0 else { return 0 }
        return Int((dollars * 100).rounded())
    }

    private var amountIsValid: Bool {
        amountCents > 0 && amountCents <= 1_000_000 // $10,000 upper bound
    }

    /// Friendly first-name pull so the confirmation copy doesn't read like
    /// a database row.
    private var firstName: String {
        recipientName.components(separatedBy: " ").first ?? recipientName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            amountField
            memoField
            Spacer(minLength: 0)
            ctaButton
            disclaimer
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.bgPage)
        .onAppear { amountFocused = true }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Send money")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("TO \(recipientName.uppercased()) · EUSOWALLET")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("AMOUNT")
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            // Quick-pick chips for common peer-settle amounts.
            HStack(spacing: Space.s2) {
                ForEach([25, 50, 100, 200], id: \.self) { preset in
                    Button {
                        amountText = String(preset)
                    } label: {
                        Text("$\(preset)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, Space.s2)
                            .background(palette.bgCardSoft)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .strokeBorder(palette.borderFaint)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var memoField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("MEMO (OPTIONAL)")
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
            TextField("Fuel stop · Tyler", text: $memo)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s3)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private var ctaButton: some View {
        Button {
            guard amountIsValid else { return }
            let payload = ChatTransferPayload(
                amountCents: amountCents,
                recipientName: recipientName,
                memo: memo.trimmingCharacters(in: .whitespaces).isEmpty ? nil : memo,
                status: .pending
            )
            onConfirm(payload)
            dismiss()
        } label: {
            HStack {
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .bold))
                Text(amountIsValid
                     ? "Send \(formattedPreview) to \(firstName)"
                     : "Enter an amount")
                    .font(EType.bodyStrong)
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.vertical, Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(amountIsValid
                          ? AnyShapeStyle(LinearGradient.diagonal)
                          : AnyShapeStyle(palette.bgCardSoft))
            )
        }
        .buttonStyle(.plain)
        .disabled(!amountIsValid)
        .opacity(amountIsValid ? 1 : 0.55)
    }

    private var formattedPreview: String {
        Double(amountCents) / 100.0 > 0
            ? (Double(amountCents) / 100.0).formatted(.currency(code: "USD"))
            : "$0.00"
    }

    private var disclaimer: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Transfers clear via EusoWallet on Stripe. Peer must have an active wallet to receive.")
                .font(EType.micro)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(3)
        }
    }
}

#Preview("DriverConversationView · Dark") {
    DriverConversationView(thread: InboxThread(
        id: "driver-marco",
        glyph: "person.crop.square",
        title: "Marco (team partner)",
        subtitle: "Team driver · owner-op",
        preview: "Thx for covering the fuel in Tyler — I'll settle tonight.",
        time: "42m",
        unread: 1,
        allowsTransfer: true
    ))
    .frame(width: 390, height: 844)
    .background(Theme.dark.bgPage)
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("ChatMoneyTransferSheet · Dark") {
    ChatMoneyTransferSheet(
        recipientName: "Marco Rivera",
        onConfirm: { _ in }
    )
    .frame(width: 390, height: 560)
    .background(Theme.dark.bgPage)
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}
