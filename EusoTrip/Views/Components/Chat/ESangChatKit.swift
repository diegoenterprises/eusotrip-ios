//
//  ESangChatKit.swift
//  EusoTrip — Shared bespoke chat design system.
//
//  One source of truth for every conversational surface in the app:
//  the ESANG AI chats (driver dispatch, shipper coach, …) AND the
//  user-to-user message threads. Extracted from the 053 ESANG Dispatch
//  Chat reference frame (2026-06-03 AFTER render) so each surface stays
//  pixel-consistent while keeping its own real send/load wiring.
//
//  Pieces:
//    • ChatAvatar        — ESANG orb or person initials, optional live dot
//    • ChatHeaderESang   — breadcrumb · AI pill · ONLINE·DISPATCH LINKED · kebab
//    • ChatHeaderPerson  — counterpart identity for message threads
//    • ChatDayDivider    — centered "TODAY" separator
//    • ChatStatusChip    — filled status pill (optional live dot)
//    • ChatPresencePill  — centered "ESANG watching … · live"
//    • ChatInlineCard    — icon-tile attachment card (dock staging style)
//    • ChatBubbleReceived/ChatBubbleSent — message bubbles
//    • ChatQuickChip     — quick-reply rail chip
//    • ChatComposer      — input bar: upload + voice-to-text + send
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Avatar

enum ChatAvatarKind: Equatable {
    /// The gradient ESANG orb with a sparkle glyph.
    case esang
    /// A person tile — initials over a tinted disc.
    case person(initials: String, tint: Color)
}

struct ChatAvatar: View {
    @Environment(\.palette) private var palette
    let kind: ChatAvatarKind
    var size: CGFloat = 28
    var online: Bool = false

    var body: some View {
        ZStack {
            switch kind {
            case .esang:
                Circle().fill(LinearGradient.diagonal)
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            case let .person(initials, tint):
                Circle().fill(tint.opacity(0.18))
                Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1)
                Text(initials)
                    .font(.system(size: size * 0.40, weight: .heavy))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if online {
                Circle()
                    .fill(Brand.success)
                    .frame(width: max(8, size * 0.26), height: max(8, size * 0.26))
                    .overlay(Circle().strokeBorder(palette.bgPrimary, lineWidth: 2))
                    .offset(x: 1, y: 1)
            }
        }
    }
}

// MARK: - Headers

/// ESANG AI chat header — orb + breadcrumb + AI pill + presence + overflow.
/// `accessory` slots in next to the title (e.g. a LoadModeBadge); `overflow`
/// is the trailing control (a kebab Menu).
struct ChatHeaderESang<Accessory: View, Overflow: View>: View {
    @Environment(\.palette) private var palette
    var breadcrumb: String
    var statusText: String
    var online: Bool = true
    var onBack: (() -> Void)? = nil
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var overflow: () -> Overflow

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let onBack {
                ChatBackButton(action: onBack)
            }
            ChatAvatar(kind: .esang, size: 38, online: online)
            VStack(alignment: .leading, spacing: 1) {
                Text(breadcrumb)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                HStack(spacing: 5) {
                    Text("ESANG")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("AI")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                    accessory()
                }
                HStack(spacing: 4) {
                    Circle().fill(online ? Brand.success : palette.textTertiary).frame(width: 5, height: 5)
                    Text(statusText)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
            overflow()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Space.s3)
        .overlay(alignment: .bottom) {
            LinearGradient.diagonal.opacity(0.5).frame(height: 1)
        }
    }
}

extension ChatHeaderESang where Accessory == EmptyView {
    init(breadcrumb: String, statusText: String, online: Bool = true,
         onBack: (() -> Void)? = nil, @ViewBuilder overflow: @escaping () -> Overflow) {
        self.init(breadcrumb: breadcrumb, statusText: statusText, online: online,
                  onBack: onBack, accessory: { EmptyView() }, overflow: overflow)
    }
}
extension ChatHeaderESang where Overflow == EmptyView {
    init(breadcrumb: String, statusText: String, online: Bool = true,
         onBack: (() -> Void)? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.init(breadcrumb: breadcrumb, statusText: statusText, online: online,
                  onBack: onBack, accessory: accessory, overflow: { EmptyView() })
    }
}
extension ChatHeaderESang where Accessory == EmptyView, Overflow == EmptyView {
    init(breadcrumb: String, statusText: String, online: Bool = true, onBack: (() -> Void)? = nil) {
        self.init(breadcrumb: breadcrumb, statusText: statusText, online: online,
                  onBack: onBack, accessory: { EmptyView() }, overflow: { EmptyView() })
    }
}

/// Person-to-person message thread header — counterpart identity + presence.
struct ChatHeaderPerson<Overflow: View>: View {
    @Environment(\.palette) private var palette
    var name: String
    var subtitle: String
    var initials: String
    var tint: Color = Brand.magenta
    var online: Bool = false
    var onBack: (() -> Void)? = nil
    @ViewBuilder var overflow: () -> Overflow

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let onBack {
                ChatBackButton(action: onBack)
            }
            ChatAvatar(kind: .person(initials: initials, tint: tint), size: 38, online: online)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if online { Circle().fill(Brand.success).frame(width: 5, height: 5) }
                    Text(subtitle)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            overflow()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Space.s3)
        .overlay(alignment: .bottom) {
            palette.borderFaint.frame(height: 1)
        }
    }
}

extension ChatHeaderPerson where Overflow == EmptyView {
    init(name: String, subtitle: String, initials: String, tint: Color = Brand.magenta,
         online: Bool = false, onBack: (() -> Void)? = nil) {
        self.init(name: name, subtitle: subtitle, initials: initials, tint: tint,
                  online: online, onBack: onBack, overflow: { EmptyView() })
    }
}

/// Shared circular back chevron used by both headers.
struct ChatBackButton: View {
    @Environment(\.palette) private var palette
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

// MARK: - Day divider

struct ChatDayDivider: View {
    @Environment(\.palette) private var palette
    var label: String = "TODAY"
    var body: some View {
        HStack {
            Spacer()
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(palette.bgCardSoft)
                .clipShape(Capsule())
            Spacer()
        }
    }
}

// MARK: - Status chips

struct ChatStatusChip: View {
    @Environment(\.palette) private var palette
    let label: String
    var color: Color
    var live: Bool = false
    var body: some View {
        HStack(spacing: 4) {
            if live { Circle().fill(color).frame(width: 6, height: 6) }
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(palette.bgCardSoft)
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
        .clipShape(Capsule())
    }
}

/// Horizontally-scrolling row of status chips.
struct ChatStatusRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { content() }
        }
    }
}

// MARK: - Presence pill

struct ChatPresencePill: View {
    @Environment(\.palette) private var palette
    let text: String
    var color: Color = Brand.success
    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(text)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(palette.bgCardSoft)
            .clipShape(Capsule())
            Spacer()
        }
    }
}

// MARK: - Inline attachment card

struct ChatInlineCard: View {
    @Environment(\.palette) private var palette
    var icon: String
    var title: String
    var subtitle: String
    var badge: String? = nil
    var badgeColor: Color = Brand.success
    var onTap: (() -> Void)? = nil

    var body: some View {
        let card = HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(palette.bgCard)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(EType.caption.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 4)
            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(badgeColor.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(8)
        .background(palette.bgPrimary)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

        if let onTap {
            Button(action: onTap) { card }.buttonStyle(.plain)
        } else {
            card
        }
    }
}

// MARK: - Bubbles

struct ChatBubbleReceived<Attachment: View>: View {
    @Environment(\.palette) private var palette
    var avatar: ChatAvatarKind = .esang
    var senderName: String? = nil
    let text: String
    var time: String? = nil
    @ViewBuilder var attachment: () -> Attachment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ChatAvatar(kind: avatar, size: 28)
            VStack(alignment: .leading, spacing: 8) {
                if let senderName, !senderName.isEmpty {
                    Text(senderName)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                }
                if !text.isEmpty {
                    Text(text)
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                attachment()
                if let time {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Text(time)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            Spacer(minLength: 36)
        }
    }
}

extension ChatBubbleReceived where Attachment == EmptyView {
    init(avatar: ChatAvatarKind = .esang, senderName: String? = nil,
         text: String, time: String? = nil) {
        self.init(avatar: avatar, senderName: senderName, text: text, time: time) { EmptyView() }
    }
}

struct ChatBubbleSent: View {
    @Environment(\.palette) private var palette
    let text: String
    var time: String? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Spacer(minLength: 36)
            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .font(EType.body)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.s3)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                if let time {
                    Text(time)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }
}

// MARK: - Quick chip

struct ChatQuickChip: View {
    @Environment(\.palette) private var palette
    let label: String
    var highlighted: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(EType.caption.weight(.bold))
                .foregroundStyle(highlighted ? AnyShapeStyle(LinearGradient.diagonal)
                                              : AnyShapeStyle(palette.textPrimary))
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 8)
                .background(highlighted ? palette.bgCardSoft : palette.bgCard)
                .overlay(
                    Capsule().strokeBorder(
                        highlighted ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.55))
                                     : AnyShapeStyle(palette.borderSoft),
                        lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Composer

/// The shared input bar: optional upload (document-intelligence), a live
/// text field that binds to the voice transcript while recording, an
/// in-field dictation toggle, the prominent SFSpeech voice button, and the
/// gradient send button. The owning surface supplies the `voice` controller
/// (via `@StateObject`) and the `onSend` / `onUpload` actions.
struct ChatComposer: View {
    @Environment(\.palette) private var palette
    @Binding var draft: String
    @ObservedObject var voice: eSangVoiceInputController
    var placeholder: String = "Ask ESANG…"
    var showUpload: Bool = true
    var showVoice: Bool = true
    var sending: Bool = false
    var onUpload: () -> Void = {}
    var onSend: () -> Void
    var onToggleVoice: () -> Void = {}

    private var trimmedEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                if showUpload {
                    Button(action: onUpload) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Attach document")
                }

                TextField(placeholder,
                          text: voice.isRecording ? $voice.transcript : $draft,
                          axis: .vertical)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .disabled(voice.isRecording)
                    .onSubmit { onSend() }

                if showVoice {
                    Button {
                        onToggleVoice()
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

            if showVoice {
                eSangVoiceInputButton(controller: voice)
            }

            Button(action: onSend) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 40, height: 40)
                        .opacity(trimmedEmpty || sending ? 0.45 : 1)
                    if sending {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(trimmedEmpty || sending)
        }
    }
}
