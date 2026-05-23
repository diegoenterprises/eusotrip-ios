//
//  ShippereSangCoachSheet.swift
//  EusoTrip — ESANG copilot sheet for SHIPPER users.
//
//  Sister of `DrivereSangCoachSheet` (DriverTabPanes.swift:4200) but
//  with shipper-context greetings, quick-action chips, and prompt
//  context. Same backend (`esang.chat`) — server-side ESANG reads the
//  `currentPage` hint and tunes its system prompt accordingly so a
//  shipper question lands different ESANG knowledge than a driver
//  question would.
//
//  Why a separate sheet (vs. branching `DrivereSangCoachSheet`)
//    The driver sheet ships ~600 lines of HOS / fuel / parking /
//    detention logic that's specific to the in-cab role. Forking a
//    leaner shipper-only surface keeps the driver code untouched
//    (frozen per [Bottom nav frozen] doctrine for the driver track)
//    and gives the shipper its own canonical greetings + chip set
//    aligned to the shipper mental model (post / bid / carrier vet
//    / settlement / spend).
//
//  Doctrine ([feedback_esang_canonical_voice]): every voice path
//  ends at `esang.chat`. This sheet is the in-app entry point for
//  shipper voice + text questions; AppIntents and the watch share
//  the same backend.
//

import SwiftUI

struct ShippereSangCoachSheet: View {
    var onClose: (() -> Void)? = nil

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: EusoTripSession
    @FocusState private var composerFocused: Bool

    /// Push-to-talk voice pipeline — Speech + AVAudioEngine. Shared
    /// controller with the driver sheet so the shipper's voice path
    /// terminates at the same `esang.chat` mutation. Final transcript
    /// is handed back via `onFinalTranscript` (wired in `.onAppear`)
    /// and shipped through the same `send(_:)` used by the text
    /// composer. Closes the parity gap the founder called out:
    ///   > YOU TOOK AWAY THE VOICE SPEECH TO TEXT CAPABILTIES IN
    ///   > ESANG CHAT. IM IN SHIPPER AND ITS MISSING. IT NEEDS TO BE
    ///   > FOR ALL USERS.
    @StateObject private var voice = eSangVoiceInputController()

    struct Msg: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        let text: String
        var time: Date = .init()
        enum Role: String { case esang, shipper }
    }

    @State private var messages: [Msg] = [
        .init(role: .esang, text: ShippereSangGreeting.pick())
    ]
    @State private var draft: String = ""
    @State private var sending: Bool = false
    @State private var sendError: String? = nil

    /// Quick-action chips — every label / prompt pair is shipper-
    /// context. The visible label is what the user sees on the chip;
    /// the prompt is what gets sent through `esang.chat`. Server
    /// reads `currentPage = "shipper.coach"` and tunes its system
    /// prompt so a question about "bids" lands in the bid-vetting
    /// knowledge slice rather than the driver-side HOS slice.
    private let chips: [(String, String)] = [
        ("Active bids",     "Which of my posted loads has the most bids right now?"),
        ("Carrier vet",     "Which carriers should I avoid based on recent on-time and DOT scores?"),
        ("Settlement",      "What's in my settlement queue this week?"),
        ("Spend YTD",       "How much have I spent on freight year-to-date?"),
        ("Post a load",     "Help me post a load — walk me through the form."),
        ("Best lane rate",  "What's a good rate per mile for my busiest lane?"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            IridescentHairline()
            transcript
            chipRow
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.bgPage)
        .contentShape(Rectangle())
        .onTapGesture { composerFocused = false }
        // Wire the voice pipeline's final transcript through the same
        // `send(_:)` used by the text composer. Voice + text converge
        // on one backend call, so `esang.chat` doesn't care which path
        // the user took to get there.
        .onAppear {
            voice.onFinalTranscript = { transcript in
                Task { @MainActor in
                    send(transcript)
                }
            }
        }
        // Cancel any in-flight recording cleanly on dismiss so the mic
        // and audio session release without a leak.
        .onDisappear {
            voice.cancel()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            OrbeSang(state: sending ? .thinking : .idle, diameter: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("ESANG")
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Your AI copilot · online")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Button {
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(messages) { m in
                        bubble(for: m).id(m.id)
                    }
                    if let e = sendError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(Brand.danger)
                            Text(e)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                        .padding(.horizontal, Space.s4)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(for m: Msg) -> some View {
        let isShipper = m.role == .shipper
        HStack {
            if isShipper { Spacer(minLength: 40) }
            Text(m.text)
                .font(EType.body)
                .foregroundStyle(isShipper ? .white : palette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isShipper
                    ? AnyShapeStyle(LinearGradient.diagonal)
                    : AnyShapeStyle(palette.bgCardSoft)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity, alignment: isShipper ? .trailing : .leading)
            if !isShipper { Spacer(minLength: 40) }
        }
    }

    // MARK: Chip row

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.0) { chip in
                    Button {
                        send(chip.1)
                    } label: {
                        Text(chip.0)
                            .font(EType.caption).bold()
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(palette.bgCardSoft)
                            .overlay(
                                Capsule().strokeBorder(palette.borderFaint, lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(sending)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s2)
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: Space.s2) {
            HStack(spacing: 8) {
                // While the mic is hot we bind the field to the live
                // partial transcript so the shipper SEES what ESANG is
                // about to receive. Driver parity (DriverTabPanes:4672).
                TextField("Ask ESANG…", text: voice.isRecording ? $voice.transcript : $draft, axis: .vertical)
                    .focused($composerFocused)
                    .font(EType.body)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit { sendDraft() }
                    .disabled(voice.isRecording)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(voice.isRecording ? Brand.magenta.opacity(0.55) : Color.clear,
                                  lineWidth: voice.isRecording ? 1.2 : 0)
            )

            // Push-to-talk mic — shared component with the driver sheet.
            // Tap to start; tap again to stop. Final transcript is shipped
            // through `send(_:)` via the `onFinalTranscript` closure wired
            // in `.onAppear` above.
            eSangVoiceInputButton(controller: voice)

            Button(action: sendDraft) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
        }
        .padding(.horizontal, Space.s4)
        .padding(.bottom, Space.s4)
    }

    // MARK: Send

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        send(text)
        draft = ""
    }

    private func send(_ text: String) {
        let userMsg = Msg(role: .shipper, text: text)
        messages.append(userMsg)
        sending = true
        sendError = nil
        Task {
            do {
                let resp = try await EusoTripAPI.shared.esang.chat(
                    message: text,
                    currentPage: "shipper.coach",
                    loadId: nil
                )
                await MainActor.run {
                    messages.append(Msg(role: .esang, text: resp.message))
                    sending = false
                }
            } catch {
                await MainActor.run {
                    sendError = "ESANG couldn't reach the server. Try again."
                    sending = false
                }
            }
        }
    }
}

// MARK: - Greeting bank (shipper-context)

/// Same shape as the driver-side `eSangGreeting` bank but with
/// shipper-context openers. Every variant is corridor-agnostic and
/// references shipper artifacts (lanes, bids, carriers, ledger) —
/// never driver artifacts (HOS, fuel, parking).
enum ShippereSangGreeting {
    enum DayPart { case morning, day, evening, night

        static func from(_ d: Date = .init()) -> DayPart {
            let h = Calendar.current.component(.hour, from: d)
            switch h {
            case 5..<12:  return .morning
            case 12..<17: return .day
            case 17..<22: return .evening
            default:      return .night
            }
        }
    }

    static let variants: [DayPart: [String]] = [
        .morning: [
            "Morning. I've got your overnight bid sweep ready — want a quick rundown?",
            "Morning, shipper. Three lanes need posting before the 10AM cutoff. Where do you want to start?",
            "Hey — early start. I'm tracking carrier capacity on your top lanes. What can I tee up?",
            "Morning. Settlement queue cleared overnight. Any new lanes you want to post?",
        ],
        .day: [
            "Hey — afternoon. Two of your loads need attention; want me to surface them?",
            "Hey, shipper. Catalysts are bidding live on your active posts. What do you need?",
            "Afternoon. I'm watching your spend run-rate vs. budget. What's on your mind?",
            "Hey. Ready to post a load, vet a carrier, or check settlements?",
        ],
        .evening: [
            "Evening — bid windows on three loads close by midnight. Want me to summarize?",
            "Evening, shipper. Carriers are staging for tomorrow's pickups. Anything to adjust?",
            "Hey. End of day — I can pull your dashboard or queue tomorrow's posts. What helps?",
            "Evening. Settlement, agreements, or fresh load posts — where do we go?",
        ],
        .night: [
            "Hey — running late. I've got bids stacking on your overnight posts. What do you need?",
            "Quiet hours, but the carrier marketplace is awake. Want me to walk through the queue?",
            "Hey. ESANG is on the night watch — load status, exception triage, settlement. What's first?",
            "Late one. Your active loads are tracking; I'll flag any that drift. What can I get for you?",
        ],
    ]

    static func pick(at date: Date = .init()) -> String {
        let part = DayPart.from(date)
        let bank = variants[part] ?? variants[.day]!
        return bank[Int.random(in: 0..<bank.count)]
    }
}
