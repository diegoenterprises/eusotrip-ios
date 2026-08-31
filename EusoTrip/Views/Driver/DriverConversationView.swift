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

    // ──────────── Voice-to-text ────────────
    //
    // Real Speech.framework dictation, same controller the ESANG coach +
    // 053 dispatch chat drive. Bound live into the composer field while
    // recording so the text the driver SEES is the text that ships.
    @StateObject private var voice = eSangVoiceInputController()

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

    // ──────────── Attachment document-intelligence state ────────────
    //
    // Before the picked photo ships via `uploadAttachment`, we run it
    // through the homegrown document-intelligence vision spine
    // (`documentRouter.classifyAndRoute`) so the capture point KNOWS
    // what the attachment is (BOL / POD / manifest / damage photo / …)
    // instead of pushing a raw image. The detected type is surfaced on
    // the pending-attachment chip so the driver — and the recipient,
    // since the type rides along as the caption — sees an honest label.
    //
    // `attachmentScan` holds the classifier verdict for the photo the
    // driver is about to send. `attachmentScanning` flips while the
    // round-trip is in flight so the chip can show a spinner rather than
    // a stale/empty label. Both reset when the photo is cleared or sent.
    @State private var attachmentScan: AttachmentClassification? = nil
    @State private var attachmentScanning: Bool = false

    /// Normalized classifier verdict for a pending photo attachment.
    /// Mirrors the load-bearing fields of `DocumentRouterAPI.ClassifyResponse`
    /// the chip renders — kept local so the view owns its own display state.
    private struct AttachmentClassification: Equatable {
        let type: String          // raw `classifiedType` (e.g. "bill_of_lading", "unknown")
        let confidence: Double    // 0…1
        let summary: String
        let warnings: [String]

        /// Explicit whitelist of classifier types that may claim a label —
        /// mirrors the `humanType` switch below EXACTLY. The classifier's
        /// catch-alls (`other`, `unknown`, empty) must NEVER ship a
        /// "Detected: …" auto-caption or a confident chip (I3 2026-06-10:
        /// the founder's thread showed a junk "Detected: Other" caption).
        private static let knownTypes: Set<String> = [
            "bill_of_lading", "proof_of_delivery", "manifest", "cargo_manifest",
            "damage_report", "damage_photo", "cargo_damage", "rate_confirmation",
            "load_tender", "weight_ticket", "scale_ticket", "run_ticket",
            "lumper_receipt", "dvir", "inspection_report"
        ]

        /// Low-confidence / unrecognized docs must read honestly — never
        /// claim a type the classifier isn't sure of. Confidence alone is
        /// not enough: the type must be in the explicit whitelist, so
        /// `other`/unknown/catch-alls render the neutral chip and ship
        /// NO caption.
        var isConfident: Bool { Self.knownTypes.contains(type) && confidence >= 0.6 }

        /// Human-facing label for the chip. Covers the common driver
        /// message attachments (BOL / POD / manifest / damage) and falls
        /// back to a title-cased version of any other classifier type.
        var humanType: String {
            switch type {
            case "bill_of_lading":            return "Bill of Lading"
            case "proof_of_delivery":         return "Proof of Delivery"
            case "manifest", "cargo_manifest": return "Manifest"
            case "damage_report", "damage_photo", "cargo_damage": return "Damage Photo"
            case "rate_confirmation":         return "Rate Confirmation"
            case "load_tender":               return "Load Tender"
            case "weight_ticket", "scale_ticket": return "Weight Ticket"
            case "run_ticket":                return "Run Ticket"
            case "lumper_receipt":            return "Lumper Receipt"
            case "dvir", "inspection_report": return "Inspection Report"
            default:
                return type.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }

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
    /// Unified Outbox observer handle for `.eusoOutboxReplayed`. Reconciles
    /// any `queuedOffline` bubble once the queue replays it on reconnect.
    @State private var outboxObserver: NSObjectProtocol? = nil

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
            // `header` (ChatHeaderPerson) draws its own bottom hairline.
            header
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

            // Unified Outbox — reconcile queued-offline bubbles when the
            // queue replays them on reconnect.
            let outboxToken = NotificationCenter.default.addObserver(
                forName: .eusoOutboxReplayed, object: nil, queue: .main
            ) { note in
                Task { @MainActor in
                    handleOutboxReplayed(note)
                }
            }
            outboxObserver = outboxToken

            // Hand the finalized dictation transcript back into the draft.
            // Append so a dictation can extend a half-typed message rather
            // than clobber it.
            voice.onFinalTranscript = { transcript in
                let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                draft = trimmed.isEmpty ? transcript : "\(trimmed) \(transcript)"
            }
        }
        .onDisappear {
            if let realtimeObserver {
                NotificationCenter.default.removeObserver(realtimeObserver)
            }
            realtimeObserver = nil
            if let outboxObserver {
                NotificationCenter.default.removeObserver(outboxObserver)
            }
            outboxObserver = nil
            RealtimeService.shared.leaveConversation(thread.id)
            UnreadMessageStore.shared.didCloseConversation(thread.id)
            voice.cancel()
        }
        // Incoming PhotosPicker selection → load the raw image data so we
        // can both preview it inline + ship it on send. Alongside, run the
        // photo through the document-intelligence vision spine so we KNOW
        // what the attachment is (BOL / POD / manifest / damage) before it
        // uploads — the verdict surfaces on the pending chip.
        .onChange(of: pickedPhoto) { _, newValue in
            Task {
                if let item = newValue,
                   let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        pendingImage = data
                        attachmentScan = nil
                    }
                    await classifyPendingAttachment(data)
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
        // Shared person-thread header — counterpart identity + presence +
        // a trailing close control (this surface is presented as a sheet
        // and as a nav push; `dismiss()` resolves correctly for both, and
        // the nav-push case also keeps its own toolbar back button).
        ChatHeaderPerson(
            name: thread.title,
            subtitle: thread.subtitle.uppercased(),
            initials: initials,
            tint: Brand.magenta,
            online: false,
            onBack: { dismiss() },
            overflow: {
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
        )
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
                            // Day separator above the first message of each
                            // calendar day so a thread that spans days reads
                            // chronologically (matches the 053 TODAY divider).
                            if shouldShowDayDivider(before: m) {
                                ChatDayDivider(label: dayLabel(for: m.time))
                                    .padding(.vertical, Space.s2)
                            }
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
            Text("Say hi to \(thread.title.components(separatedBy: " ").first ?? "them") below. They'll get a push the moment it lands.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s6)
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        Group {
            if m.from == .me {
                sentBubble(m)
            } else {
                receivedBubble(m)
            }
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

    /// Short clock label (e.g. "09:34") for the timestamp shown inside /
    /// beneath each bubble.
    private func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    // MARK: Day dividers

    /// True when `m` is the first message of a new calendar day (or the very
    /// first message in the transcript) — i.e. a `ChatDayDivider` should be
    /// rendered above it.
    private func shouldShowDayDivider(before m: ChatMessage) -> Bool {
        guard let idx = messages.firstIndex(where: { $0.id == m.id }) else { return false }
        if idx == 0 { return true }
        let prev = messages[idx - 1]
        return !Calendar.current.isDate(prev.time, inSameDayAs: m.time)
    }

    /// "TODAY" / "YESTERDAY" / a short date label for the divider sitting
    /// above the first message of a day.
    private func dayLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "TODAY" }
        if cal.isDateInYesterday(date) { return "YESTERDAY" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            .uppercased()
    }

    // MARK: Received bubble (peer)
    //
    // Rendered through the shared `ChatBubbleReceived` so the look matches
    // the 053 reference: a person-initials avatar, an optional sender name
    // (group threads only), the message text, the timestamp INSIDE the
    // card, and an attachment slot that carries the image / transfer card /
    // unsent placeholder. No read receipt on inbound messages.
    @ViewBuilder
    private func receivedBubble(_ m: ChatMessage) -> some View {
        ChatBubbleReceived(
            avatar: .person(initials: initials, tint: Brand.magenta),
            senderName: senderName(for: m),
            text: bubbleText(m),
            time: clock(m.time)
        ) {
            bubbleAttachment(m, outbound: false)
        }
    }

    // MARK: Sent bubble (me)
    //
    // Plain text routes through the shared `ChatBubbleSent` gradient bubble;
    // attachments / transfers / unsent keep their bespoke shells (re-skinned
    // consistently). In every case we append the timestamp + read-receipt
    // row beneath, preserving the double-check "read" glyph.
    @ViewBuilder
    private func sentBubble(_ m: ChatMessage) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 36)
            VStack(alignment: .trailing, spacing: 4) {
                if m.unsent || m.transfer != nil || m.imageData != nil || m.imageURL != nil || m.attachmentUnavailable {
                    // Non-text outbound content keeps its bespoke shell.
                    bubbleBody(m)
                        .frame(maxWidth: 280, alignment: .trailing)
                } else {
                    // Plain text → shared gradient sent bubble (no inner time;
                    // we render the time + receipt together just below).
                    ChatBubbleSent(text: m.text)
                }
                if m.queuedOffline {
                    // Unified Outbox state — sent while offline, persisted
                    // for replay. Honest footer instead of a read receipt
                    // the message hasn't earned yet.
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Brand.warning)
                        Text("Queued · will send when you reconnect")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(Brand.warning)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(clock(m.time))
                            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                        // Doctrine §2.1: brand accent on "read" state must be the
                        // gradient, not a flat Brand.info tint. §2.3: ternary
                        // shape-style branches wrapped in AnyShapeStyle so
                        // SwiftUI compiles on iOS 17.
                        Image(systemName: m.read ? "checkmark.circle.fill" : "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(m.read
                                             ? AnyShapeStyle(LinearGradient.diagonal)
                                             : AnyShapeStyle(palette.textTertiary))
                    }
                }
            }
        }
    }

    /// Group threads show the sender's name above an inbound bubble;
    /// 1:1 threads don't. `InboxThread` carries no per-message sender, so
    /// we suppress the name unless the subtitle marks this as a group.
    private func senderName(for m: ChatMessage) -> String? {
        guard m.from == .other else { return nil }
        let isGroup = thread.subtitle.lowercased().contains("group")
            || thread.title.lowercased().contains("group")
        return isGroup ? thread.title : nil
    }

    /// Text the bubble body should render. Image / transfer rows carry an
    /// empty caption string by design (see `toChat`), so the kit bubble's
    /// own text line collapses and the attachment slot owns the content.
    private func bubbleText(_ m: ChatMessage) -> String {
        if m.unsent { return "" }
        if m.transfer != nil { return "" }
        if m.imageData != nil || m.imageURL != nil { return m.text }
        return m.text
    }

    /// Attachment slot for the shared received bubble — carries the unsent
    /// placeholder, the transfer card, or the image (local blob or remote
    /// AsyncImage). Empty for plain text.
    @ViewBuilder
    private func bubbleAttachment(_ m: ChatMessage, outbound: Bool) -> some View {
        if m.unsent {
            Text("Message unsent")
                .font(EType.body)
                .italic()
                .foregroundStyle(palette.textTertiary)
        } else if let payload = m.transfer {
            transferCard(payload, outbound: outbound)
        } else if let data = m.imageData, let ui = uiImage(from: data) {
            attachmentImage {
                Image(uiImage: ui).resizable().scaledToFill()
            }
        } else if let urlStr = m.imageURL, let url = URL(string: urlStr) {
            attachmentImage {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(palette.tintNeutral)
                            .overlay(ProgressView().controlSize(.small))
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
        } else if m.attachmentUnavailable {
            attachmentUnavailableTile
        } else {
            EmptyView()
        }
    }

    /// I3 render floor — placeholder tile for an attachment row whose
    /// fileUrl didn't resolve (same chrome as the AsyncImage `.failure`
    /// branch). The driver sees an honest "photo we can't show yet",
    /// never the raw "[image] filename" marker as bubble text.
    private var attachmentUnavailableTile: some View {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(palette.tintNeutral)
            .frame(width: 200, height: 132)
            .overlay(
                VStack(spacing: Space.s2) {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(palette.textTertiary)
                    Text("Attachment unavailable")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
    }

    /// Bare clipped image used inside a bubble's attachment slot. Caption
    /// (if any) is rendered by the bubble's own text line, so this shell is
    /// just the framed, bordered image.
    @ViewBuilder
    private func attachmentImage<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: 240, maxHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
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
        } else if m.attachmentUnavailable {
            // I3 render floor — attachment row with no resolvable fileUrl.
            // Honest placeholder tile, never the raw "[image] …" marker.
            attachmentUnavailableTile
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
                VStack(alignment: .leading, spacing: 3) {
                    // Detected-document chip — the document-intelligence
                    // verdict for the photo about to be sent.
                    attachmentTypeChip
                    Text("Tap send to share with \(thread.title.components(separatedBy: " ").first ?? "them").")
                        .font(EType.micro)
                        .foregroundStyle(palette.textSecondary)
                    // Surface the classifier's first warning honestly so
                    // the driver can fix a bad capture before sending.
                    if let warning = attachmentScan?.warnings.first, !warning.isEmpty {
                        Text("⚠ \(warning)")
                            .font(EType.micro)
                            .foregroundStyle(Brand.warning)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button {
                    pendingImage = nil
                    pickedPhoto = nil
                    attachmentScan = nil
                    attachmentScanning = false
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

    /// The detected-document chip on the pending-attachment strip. Renders
    /// one of three honest states:
    ///   • scanning      → spinner + "Identifying document…"
    ///   • confident hit → the gradient type pill + confidence %
    ///   • low/unknown   → neutral "Couldn't confidently identify" so we
    ///                     never claim a type the classifier isn't sure of.
    @ViewBuilder
    private var attachmentTypeChip: some View {
        if attachmentScanning {
            HStack(spacing: Space.s2) {
                ProgressView().controlSize(.mini).tint(palette.textSecondary)
                Text("Identifying document…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        } else if let scan = attachmentScan, scan.isConfident {
            HStack(spacing: Space.s2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(scan.humanType.uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textPrimary)
                Text("\(Int((scan.confidence * 100).rounded()))%")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(scan.confidence >= 0.85 ? Brand.success : Brand.warning)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(
                        Capsule().fill((scan.confidence >= 0.85 ? Brand.success : Brand.warning).opacity(0.14))
                    )
            }
        } else if attachmentScan != nil {
            // Ran, but low confidence or "unknown" — stay neutral and honest.
            HStack(spacing: Space.s2) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("Couldn't confidently identify - please confirm")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
        } else {
            // Classification didn't run (e.g. errored or not yet started).
            Text("Attached photo")
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Composer
    //
    // Restyled to the shared chat kit's capsule language (matching the 053
    // composer) while KEEPING this surface's richer affordances that the
    // stock `ChatComposer` doesn't carry: the `+` attach menu, the one-tap
    // PhotosPicker, and the optional EusoWallet P2P transfer button. Voice-
    // to-text is added via the shared `eSangVoiceInputController`: an
    // in-field mic toggle (the field binds live to `voice.transcript` while
    // recording) plus the prominent SFSpeech voice button — none of the
    // existing photo / transfer / send wiring is removed.

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
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
                composerIconChrome("plus", tint: palette.textPrimary)
            }
            .accessibilityLabel("Attach")

            // Direct PhotosPicker — offered alongside the menu as a
            // single-tap photo shortcut. This avoids the menu-then-picker
            // round-trip for the most common case.
            PhotosPicker(selection: $pickedPhoto,
                         matching: .images,
                         photoLibrary: .shared()) {
                composerIconChrome("photo", tint: palette.textPrimary, size: 16)
            }
            .accessibilityLabel("Add photo")

            if thread.allowsTransfer {
                Button {
                    showTransferSheet = true
                } label: {
                    composerIconChrome("dollarsign", tint: Brand.success, size: 16,
                                       border: Brand.success.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send money via EusoWallet")
            }

            // Capsule text-field pill with an in-field dictation toggle. The
            // field binds live to the voice transcript while recording so
            // the text the driver SEES is what ships.
            HStack(spacing: 8) {
                TextField("Message \(thread.title.components(separatedBy: " ").first ?? "")…",
                          text: voice.isRecording ? $voice.transcript : $draft,
                          axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .disabled(voice.isRecording)
                    .submitLabel(.send)
                    .onSubmit { sendComposed() }

                Button {
                    MeAction.fire("driver-conversation.voice-toggled",
                                  userInfo: ["conversationId": thread.id,
                                             "recording": !voice.isRecording])
                    voice.toggle()
                } label: {
                    Image(systemName: voice.isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(voice.isRecording ? Brand.magenta : palette.textSecondary)
                        .symbolEffect(.variableColor.iterative.hideInactiveLayers,
                                      options: .repeating, isActive: voice.isRecording)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(voice.isRecording ? "Stop dictation" : "Dictate")
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 10)
            .background(palette.bgCard)
            .overlay(
                Capsule().strokeBorder(
                    voice.isRecording ? Brand.magenta.opacity(0.55) : palette.borderFaint,
                    lineWidth: 1)
            )
            .clipShape(Capsule())

            // Prominent SFSpeech voice button (shared component).
            eSangVoiceInputButton(controller: voice)

            Button {
                sendComposed()
            } label: {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 40, height: 40)
                        .opacity(canSend ? 1 : 0.55)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, Space.s5)
        .padding(.bottom, Space.s4 + Device.safeBottom)
        .padding(.top, Space.s2)
    }

    /// Shared rounded chrome for the composer's leading icon buttons (attach
    /// `+`, photo, transfer `$`) so they stay visually consistent with the
    /// kit's pill language.
    @ViewBuilder
    private func composerIconChrome(_ systemName: String,
                                    tint: Color,
                                    size: CGFloat = 18,
                                    border: Color? = nil) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(palette.bgCardSoft)
            .overlay(Circle().strokeBorder(border ?? palette.borderFaint))
            .clipShape(Circle())
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

            // Mark as read once the transcript is visible. Local unread
            // evidence clears only after the server confirms the write.
            Task {
                if let receipt = try? await EusoTripAPI.shared.messaging.markAsRead(
                    conversationId: thread.id
                ), receipt.success {
                    UnreadMessageStore.shared.didConfirmRead(thread.id)
                }
                UnreadMessageStore.shared.refresh()
            }
        } catch EusoTripAPIError.unauthenticated {
            lastErrorMessage = "Please sign in to view this conversation."
            didLoad = true
        } catch {
            lastErrorMessage = "Couldn't load messages - \(error.localizedDescription)"
            didLoad = true
        }
    }

    /// Run the picked photo through the document-intelligence vision spine
    /// so the capture point KNOWS what's attached (BOL / POD / manifest /
    /// damage) before it uploads. Best-effort + non-blocking: if the
    /// classifier errors or times out we silently fall back to a plain
    /// "Attached photo" chip and the existing `uploadAttachment` path is
    /// completely unaffected — we never gate the send on the verdict.
    @MainActor
    private func classifyPendingAttachment(_ data: Data) async {
        attachmentScanning = true
        defer { attachmentScanning = false }

        // Compress + detect mime so the vision payload stays small and we
        // hand the classifier the right content type (PNG vs JPEG).
        let mime: DocumentRouterAPI.MimeType = isPNG(data) ? .png : .jpeg
        let payload = compressedAttachment(data, mime: mime)
        let base64 = payload.base64EncodedString()

        do {
            let resp = try await EusoTripAPI.shared.documentRouter.classifyAndRoute(
                documentBase64: base64,
                mimeType: mime,
                callerContext: "driver message attachment"
            )
            // Only keep the verdict if it's still the photo on deck — the
            // driver may have swapped or cleared it mid-flight.
            guard pendingImage != nil else { return }
            attachmentScan = AttachmentClassification(
                type: resp.classifiedType,
                confidence: resp.confidence,
                summary: resp.summary,
                warnings: resp.warnings
            )
        } catch {
            // Honest fallback: surface nothing fabricated. The chip shows a
            // plain "Attached photo" and the upload proceeds untouched. We
            // log the real error so it isn't swallowed silently.
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            print("[DriverConversationView] attachment classify failed: \(detail)")
            attachmentScan = nil
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

        // Snapshot the document-intelligence verdict for this attachment so
        // the send path can carry an honest "Detected: <type>" caption to
        // the recipient when the driver didn't type one. Only the confident
        // verdict rides along — low-confidence/unknown is never labelled.
        let scan = (image != nil) ? attachmentScan : nil
        let detectedLabel: String? = (scan?.isConfident == true) ? scan?.humanType : nil

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
        attachmentScan = nil
        attachmentScanning = false
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
                    //
                    // I3 (client half of 0327/S3): NEVER ship raw
                    // PhotosPicker bytes — normalize through the JPEG
                    // ladder so a 12MP photo lands well under 1MB base64
                    // instead of detonating the server column cap.
                    let result = try await EusoTripAPI.shared.messaging.uploadAttachment(
                        conversationId: thread.id,
                        data: uploadPayload(imageData),
                        fileName: "photo-\(Int(Date().timeIntervalSince1970)).jpg",
                        mimeType: "image/jpeg"
                    )
                    stampServerId(result.messageId, onLocalId: anchor)

                    // Caption follow-up. Priority: the driver's typed
                    // caption wins; otherwise, if the vision spine
                    // confidently identified the document, ship that honest
                    // label so the recipient knows it's a BOL/POD/manifest/
                    // damage photo rather than an anonymous image. We never
                    // synthesize a label the classifier wasn't sure of.
                    let caption: String? = {
                        if !text.isEmpty { return text }
                        if let label = detectedLabel { return "Detected: \(label)" }
                        return nil
                    }()
                    if let caption {
                        _ = try await EusoTripAPI.shared.messaging.sendMessage(
                            conversationId: thread.id,
                            content: caption,
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
            } catch EusoTripAPIError.queuedForOfflineReplay {
                // Offline — EusoTripAPI persisted this send to the Unified
                // Outbox. KEEP the optimistic bubble (don't roll it back),
                // flip it to the `.queuedOffline` state so it shows a
                // "Queued · will send when you reconnect" footer, and link
                // it to the queued action's idempotency key so the
                // `.eusoOutboxReplayed` observer can reconcile it on
                // reconnect. Only plain-text sends reach this branch — the
                // attachment path uploads bytes and isn't enqueue-eligible.
                if let idx = messages.firstIndex(where: { $0.id == anchor }) {
                    messages[idx].queuedOffline = true
                    messages[idx].outboxKey = OfflineQueue.shared.keyForPendingMessage(
                        conversationId: thread.id, content: text
                    )
                }
                lastErrorMessage = nil
            } catch {
                // Roll the optimistic bubble back and surface the error.
                messages.removeAll { $0.id == anchor }
                lastErrorMessage = "Send failed - \(error.localizedDescription)"
                // Put the draft + attachment (and its detected verdict) back
                // so the driver can retry without re-picking or re-scanning.
                if !text.isEmpty { draft = text }
                if let img = image {
                    pendingImage = img
                    attachmentScan = scan
                }
            }
        }
    }

    // MARK: Outbox reconciliation

    /// Reconcile a queued-offline bubble once the Unified Outbox replays
    /// it on reconnect. The `.eusoOutboxReplayed` notification carries the
    /// replayed action's idempotency `key`; we match it to the bubble's
    /// `outboxKey` and clear the queued state. As a belt-and-suspenders
    /// step we also reload the transcript so the bubble picks up its real
    /// serverId / read state from the server's canonical copy.
    @MainActor
    private func handleOutboxReplayed(_ note: Notification) {
        guard let key = note.userInfo?["key"] as? String else { return }
        var matched = false
        if let idx = messages.firstIndex(where: { $0.outboxKey == key }) {
            messages[idx].queuedOffline = false
            matched = true
        }
        // If the key wasn't linked (enqueue/throw ordering race) but this
        // thread has any queued bubbles, refetch to reconcile them all.
        if matched || messages.contains(where: { $0.queuedOffline }) {
            Task { await loadTranscript() }
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
            lastErrorMessage = "Transfer failed - \(error.localizedDescription)"
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
            lastErrorMessage = "Can't unsend, message still sending."
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
            lastErrorMessage = "Couldn't unsend - \(error.localizedDescription)"
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
        case "image", "document", "file":
            // I3 render floor (2026-06-10): an attachment row renders as an
            // ATTACHMENT, never as its raw "[image] filename.jpg" DB-marker
            // content. With a resolvable fileUrl we render the real image
            // bubble; without one (the pre-S3 server never joined
            // message_attachments into getMessages) we render the
            // photo-placeholder tile. Either way the marker text is dropped
            // — it must NEVER reach a bubble.
            chat.text = ""
            if let url = m.metadata?.fileUrl, !url.isEmpty {
                chat.imageURL = url
            } else {
                chat.attachmentUnavailable = true
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

    /// PNG magic-number sniff so we hand the classifier the right mime.
    /// Everything else (JPEG, HEIC, …) is normalized to JPEG on the way out.
    private func isPNG(_ data: Data) -> Bool {
        data.count > 4 && data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47
    }

    /// Keep the vision payload small (~<900KB). PNGs pass through; anything
    /// else is JPEG-recompressed down the quality ladder. Mirrors the
    /// compression used by the canonical classifier surfaces.
    private func compressedAttachment(_ data: Data, mime: DocumentRouterAPI.MimeType) -> Data {
        if mime == .png || data.count <= 900_000 { return data }
        return jpegLadder(data, budget: 900_000) ?? data
    }

    /// I3 upload payload (client half of the 0327/S3 widen): bytes shipped
    /// through `uploadAttachment` are ALWAYS normalized to JPEG via the
    /// same ladder the classifier uses — never raw PhotosPicker bytes.
    /// Budgeted at 700KB raw so the base64 data URL stays under ~1MB
    /// (base64 inflates 4/3) — far below the 16MB MEDIUMTEXT cap, and PNG/
    /// HEIC sources become real JPEG so the declared `image/jpeg` mime and
    /// `.jpg` filename are honest.
    private func uploadPayload(_ data: Data) -> Data {
        jpegLadder(data, budget: 700_000) ?? data
    }

    /// Shared JPEG budget ladder (classifier + upload). Walks quality down
    /// first, then steps the longest edge down — a 12MP frame can't fit a
    /// sub-MB budget on quality alone. Returns nil only when the bytes
    /// don't decode as an image at all.
    private func jpegLadder(_ data: Data, budget: Int) -> Data? {
        #if canImport(UIKit)
        guard let img = UIImage(data: data) else { return nil }
        for q in [CGFloat(0.85), 0.75, 0.65, 0.55, 0.45] {
            if let d = img.jpegData(compressionQuality: q), d.count <= budget { return d }
        }
        var work = img
        for maxDim in [CGFloat(2048), 1600, 1280, 1024] {
            work = downscaled(work, maxDimension: maxDim) ?? work
            for q in [CGFloat(0.7), 0.55, 0.45] {
                if let d = work.jpegData(compressionQuality: q), d.count <= budget { return d }
            }
        }
        return work.jpegData(compressionQuality: 0.45)
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    /// Aspect-preserving downscale to `maxDimension` on the longest edge.
    private func downscaled(_ img: UIImage, maxDimension: CGFloat) -> UIImage? {
        let longest = max(img.size.width, img.size.height)
        guard longest > 0 else { return nil }
        guard longest > maxDimension else { return img }
        let scale = maxDimension / longest
        let size = CGSize(width: (img.size.width * scale).rounded(),
                          height: (img.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    #endif
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
        preview: "Thx for covering the fuel in Tyler. I'll settle tonight.",
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
