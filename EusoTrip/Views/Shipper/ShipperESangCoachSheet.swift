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
    /// Autopilot dispatcher injected by `ShipperSurface`. When ESANG's
    /// reply carries `<<<ACTION:…>>>` tokens we parse them out and fire
    /// each through this closure so a spoken/typed command actually
    /// drives the Shipper push-nav surface. Was previously MISSING —
    /// the Shipper sheet appended the raw reply and never parsed the
    /// tag, so every autopilot command was a no-op (E1/E2). Nil in
    /// previews — the parser still cleans the visible text.
    @Environment(\.esangActionHandler) private var autopilot

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
    /// Drives the document-router sheet. The composer's paperclip
    /// opens it; on `onApplySingle` we surface the REAL classifier
    /// result (type + summary + key fields + any warnings) into the
    /// transcript and seed the input so the shipper sends ESANG a
    /// document it already understands — not a blind upload. Same
    /// affordance the ESANG dispatch chat carries (053).
    @State private var showDocClassifier: Bool = false

    /// Quick-action chips — every label / prompt pair is shipper-
    /// context. The visible label is what the user sees on the chip;
    /// the prompt is what gets sent through `esang.chat`. Server
    /// reads `currentPage = "shipper.coach"` and tunes its system
    /// prompt so a question about "bids" lands in the bid-vetting
    /// knowledge slice rather than the driver-side HOS slice.
    private let chips: [(String, String)] = [
        ("Active bids",     "Which of my posted loads has the most bids right now?"),
        ("Carrier vet",     "Which carriers should I avoid based on recent on-time and DOT scores?"),
        ("Market intel",    "Open market intelligence and summarize live commodity and lane-rate signals."),
        ("Settlement",      "What's in my settlement queue this week?"),
        ("Spend YTD",       "How much have I spent on freight year-to-date?"),
        ("Post a load",     "Help me post a load, walk me through the form."),
        ("Best lane rate",  "What's a good rate per mile for my busiest lane?"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            chipRow
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Full-bleed page background. Presented as a `.fullScreenCover`
        // (ASC AOd5xzXVfU6CF6hyijTDwgk) — without the safe-area ignore the
        // status-bar band showed the presenting screen's labels through.
        .background(palette.bgPage.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { composerFocused = false }
        // Wire the voice pipeline's final transcript back into the
        // composer draft (append so dictation extends a half-typed
        // line rather than clobbering it). The shipper then taps send
        // — voice + text converge on the same `send(_:)` backend call,
        // so `esang.chat` doesn't care which path the user took.
        .onAppear {
            voice.onFinalTranscript = { transcript in
                let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                draft = trimmed.isEmpty ? transcript : "\(trimmed) \(transcript)"
            }
        }
        // Cancel any in-flight recording cleanly on dismiss so the mic
        // and audio session release without a leak.
        .onDisappear {
            voice.cancel()
        }
        // Hands-free autopilot entry (founder press-and-hold spec). When
        // `.esangEnterAutopilot` fires while this sheet is up — e.g. ESANG
        // replied with `<<<ACTION:autopilot>>>`, or the user long-pressed
        // the orb — release THIS sheet's mic and dismiss so the root-level
        // `EusoAutopilotMount` HUD (which owns the continuous voice loop
        // for the SHIPPER role) takes over unobstructed. We do NOT start a
        // second loop here; the global engine is the single owner.
        .onReceive(NotificationCenter.default.publisher(for: .esangEnterAutopilot)) { _ in
            voice.cancel()
            if let onClose { onClose() } else { dismiss() }
        }
        // Document-intelligence spine. The shipper drops a doc (camera /
        // photos / files), the router classifies + extracts it via
        // `documentRouter.classifyAndRoute`, and `onApplySingle` hands
        // back a `ClassifiedDocument` we render HONESTLY into the chat —
        // never a raw image, never a fabricated type.
        .sheet(isPresented: $showDocClassifier) {
            DocumentClassifierSheet(
                mode: .prefillWizard,
                callerContext: "shipper esang coach",
                onApplySingle: { doc in attachClassifiedDoc(doc) },
                onDispatchBatch: { _ in }
            )
            .environment(\.palette, palette)
        }
    }

    // MARK: Header

    /// Shared ESANG chat header. This is a full-screen cover — there is
    /// no back nav, so `onBack` is nil and the trailing `overflow` slot
    /// holds a close "xmark" that calls `onClose()`/`dismiss()` exactly
    /// as the old bespoke header did. No `accessory`: the `statusText`
    /// line ("ONLINE · COPILOT") already carries presence, so the old
    /// duplicate "ONLINE" capsule was redundant (ASC build-712 sweep).
    private var header: some View {
        ChatHeaderESang(
            breadcrumb: "SHIPPER · ESANG COACH",
            statusText: sending ? "THINKING…" : "ONLINE · COPILOT",
            online: true,
            onBack: nil,
            overflow: {
                Button {
                    if let onClose { onClose() } else { dismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(palette.bgCardSoft)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close ESANG")
            }
        )
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s4) {
                    ChatDayDivider()
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
                    }
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
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
        if m.role == .shipper {
            ChatBubbleSent(text: m.text, time: clock(m.time))
        } else {
            ChatBubbleReceived(avatar: .esang, text: m.text, time: clock(m.time))
        }
    }

    /// `HH:mm` stamp for a bubble — rendered inside the card, matching
    /// the 053 reference look.
    private func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: Chip row

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(chips, id: \.0) { chip in
                    ChatQuickChip(label: chip.0) {
                        send(chip.1)
                    }
                    .disabled(sending)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, Space.s2)
        }
    }

    // MARK: Composer

    /// Shared input bar — keeps every shipper affordance: the document
    /// upload paperclip opens the classifier sheet (`onUpload`), the
    /// SFSpeech voice button + live-transcript binding live inside the
    /// kit, and `onSend` routes the draft through the same `esang.chat`
    /// send path via `sendDraft()`.
    private var composer: some View {
        ChatComposer(
            draft: $draft,
            voice: voice,
            placeholder: "Ask ESANG…",
            showUpload: true,
            showVoice: true,
            sending: sending,
            onUpload: { showDocClassifier = true },
            onSend: { sendDraft() }
        )
        .padding(.horizontal, 14)
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
        // Snapshot the env dispatcher at call time so the async
        // follow-up isn't reading a stale @Environment value.
        let dispatcher = autopilot
        let localNavAction = eSangAutopilot.localNavIntent(for: text)
        if let action = localNavAction,
           let label = navigationFallbackLabel(for: action) {
            messages.append(Msg(role: .esang, text: "Opening \(label)."))
            sending = false
            dispatchActions([action], dispatcher: dispatcher)
            return
        }
        Task {
            do {
                let resp = try await EusoTripAPI.shared.esang.chat(
                    message: text,
                    currentPage: "shipper.coach",
                    loadId: nil
                )
                // Split ESANG's reply into shipper-visible text + machine
                // actions. The parser strips every `<<<ACTION:verb:arg>>>`
                // token so the bubble shows clean prose, and hands back the
                // typed intents the autopilot dispatcher executes (navigate
                // to a screen, open a load, refresh, execute a CTA, …).
                let (cleaned, actions) = eSangAutopilot.parse(resp.message)
                let dispatchable = actions.isEmpty ? localNavAction.map { [$0] } ?? [] : actions
                await MainActor.run {
                    if !cleaned.isEmpty {
                        messages.append(Msg(role: .esang, text: cleaned))
                    } else if let label = navigationFallbackLabel(for: localNavAction) {
                        messages.append(Msg(role: .esang, text: "Opening \(label)."))
                    }
                    sending = false
                    dispatchActions(dispatchable, dispatcher: dispatcher)
                }
            } catch {
                do {
                    let grounded = try await ShipmentAgentService.shared.ask(text)
                    let (cleaned, actions) = eSangAutopilot.parse(grounded.answer)
                    let dispatchable = actions.isEmpty ? localNavAction.map { [$0] } ?? [] : actions
                    await MainActor.run {
                        if !cleaned.isEmpty {
                            messages.append(Msg(role: .esang, text: cleaned))
                        } else if let label = navigationFallbackLabel(for: localNavAction) {
                            messages.append(Msg(role: .esang, text: "Opening \(label)."))
                        }
                        sending = false
                        dispatchActions(dispatchable, dispatcher: dispatcher)
                    }
                } catch {
                    await MainActor.run {
                        if let action = localNavAction,
                           let label = navigationFallbackLabel(for: action) {
                            messages.append(Msg(role: .esang, text: "I could not reach live intelligence, but I can still open \(label)."))
                            sending = false
                            dispatchActions([action], dispatcher: dispatcher)
                        } else {
                            sendError = "ESANG could not connect to live intelligence. Try again."
                            sending = false
                        }
                    }
                }
            }
        }
    }

    private func dispatchActions(_ actions: [eSangAction],
                                 dispatcher: ((eSangAction) -> Void)?) {
        // Stagger so a navigate-then-execute sequence animates naturally
        // instead of stepping on itself.
        for (idx, action) in actions.enumerated() {
            let delay = Double(idx) * 0.20
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                dispatcher?(action)
            }
        }
    }

    private func navigationFallbackLabel(for action: eSangAction?) -> String? {
        guard let action else { return nil }
        switch action {
        case .navigatePath(let path):
            let p = path.lowercased()
            if p.contains("load") && (p.contains("create") || p.contains("new") || p.contains("post")) { return "Post a Load" }
            if p.contains("market") { return "Market Intelligence" }
            if p.contains("loads") { return "Loads" }
            if p.contains("wallet") { return "EusoWallet" }
            if p.contains("carrier") { return "Carrier Directory" }
            if p.contains("compliance") { return "Compliance" }
            if p.contains("message") { return "Messages" }
            return "that screen"
        case .back:
            return "the previous screen"
        case .openChat, .closeChat, .refresh, .selectLoad, .navigate,
             .execute, .autopilot, .undoAll, .tapAt:
            return nil
        }
    }

    // MARK: Document classification

    /// Surface a classified document into the chat. We render the REAL
    /// router result — detected type, confidence, summary, the key
    /// extracted fields, and any warnings — as an ESANG bubble, then
    /// seed the composer with a ready-to-send line so the shipper can
    /// ask ESANG about the doc it just understood. HONEST: low
    /// confidence or an `unknown` type reads as "couldn't confidently
    /// identify — please confirm", never a fabricated label.
    private func attachClassifiedDoc(_ doc: ClassifiedDocument) {
        let conf = Int((doc.confidence * 100).rounded())
        let lowConfidence = doc.confidence < 0.6
        let isUnknown = doc.classifiedType == "unknown"
            || doc.classifiedType.trimmingCharacters(in: .whitespaces).isEmpty

        // Honest header line.
        let headline: String
        if isUnknown || lowConfidence {
            headline = "I couldn't confidently identify this document (\(conf)% confidence). Please confirm what it is."
        } else {
            headline = "Got it. That's a \(humanDocType(doc.classifiedType)) (\(conf)% confidence)."
        }

        var lines: [String] = [headline]
        if !doc.summary.isEmpty {
            lines.append(doc.summary)
        }

        // A handful of the most useful extracted fields, verbatim from
        // the router. We never invent values — only show what came back.
        let fieldLines = doc.fields
            .sorted { $0.key < $1.key }
            .prefix(5)
            .map { "• \(prettyFieldKey($0.key)): \($0.value)" }
        if !fieldLines.isEmpty {
            lines.append("Detected:\n" + fieldLines.joined(separator: "\n"))
        }

        for w in doc.warnings.prefix(3) {
            lines.append("⚠ \(w)")
        }

        messages.append(Msg(role: .esang, text: lines.joined(separator: "\n\n")))

        // Seed the composer so the shipper has a one-tap follow-up that
        // references the document ESANG now knows about.
        if isUnknown || lowConfidence {
            draft = "About the document I just shared, "
        } else {
            draft = "About this \(humanDocType(doc.classifiedType).lowercased()), "
        }
        composerFocused = true
    }

    /// Human label for a router doc-type slug. Mirrors the mapping the
    /// classifier sheet renders so the chat copy reads the same way;
    /// the default path title-cases any slug we haven't named.
    private func humanDocType(_ raw: String) -> String {
        switch raw {
        case "bill_of_lading":                  return "Bill of Lading"
        case "rate_confirmation":               return "Rate Confirmation"
        case "run_ticket":                      return "Run Ticket"
        case "proof_of_delivery":               return "Proof of Delivery"
        case "load_csv":                        return "Load CSV"
        case "load_tender":                     return "Load Tender"
        case "weight_ticket", "scale_ticket":   return "Weight Ticket"
        case "us_coi", "ca_coi":                return "Insurance Certificate"
        case "us_cdl":                          return "CDL"
        case "us_medical_card":                 return "Medical Card"
        case "us_dot_authority", "us_mc_authority": return "FMCSA Authority"
        case "w9":                              return "W-9"
        case "form_1099":                       return "1099"
        case "us_ein_letter":                   return "EIN Letter"
        case "shipper_agreement", "broker_agreement", "carrier_packet",
             "factoring_agreement", "nda":
            return "Agreement"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Title-case an extracted-field key (e.g. `consigneeName` →
    /// "Consignee Name", `bol_number` → "Bol Number") for display.
    private func prettyFieldKey(_ key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .reduce(into: "") { acc, ch in
                if ch.isUppercase { acc.append(" ") }
                acc.append(ch)
            }
        return spaced
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
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
            "Morning. I've got your overnight bid sweep ready. Want a quick rundown?",
            "Morning, shipper. Three lanes need posting before the 10AM cutoff. Where do you want to start?",
            "Hey, early start. I'm tracking carrier capacity on your top lanes. What can I tee up?",
            "Morning. Settlement queue cleared overnight. Any new lanes you want to post?",
        ],
        .day: [
            "Hey, afternoon. Two of your loads need attention; want me to surface them?",
            "Hey, shipper. Catalysts are bidding live on your active posts. What do you need?",
            "Afternoon. I'm watching your spend run-rate vs. budget. What's on your mind?",
            "Hey. Ready to post a load, vet a carrier or check settlements?",
        ],
        .evening: [
            "Evening. Bid windows on three loads close by midnight. Want me to summarize?",
            "Evening, shipper. Carriers are staging for tomorrow's pickups. Anything to adjust?",
            "Hey. End of day, I can pull your dashboard or queue tomorrow's posts. What helps?",
            "Evening. Settlement, agreements or fresh load posts. Where do we go?",
        ],
        .night: [
            "Hey, running late. I've got bids stacking on your overnight posts. What do you need?",
            "Quiet hours, but the carrier marketplace is awake. Want me to walk through the queue?",
            "Hey. ESANG is on the night watch, load status, exception triage, settlement. What's first?",
            "Late one. Your active loads are tracking; I'll flag any that drift. What can I get for you?",
        ],
    ]

    static func pick(at date: Date = .init()) -> String {
        let part = DayPart.from(date)
        let bank = variants[part] ?? variants[.day]!
        return bank[Int.random(in: 0..<bank.count)]
    }
}

// MARK: - Previews

#Preview("ShippereSangCoachSheet · Dark") {
    ShippereSangCoachSheet()
        .frame(width: 390, height: 844)
        .environment(\.palette, Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("ShippereSangCoachSheet · Light") {
    ShippereSangCoachSheet()
        .frame(width: 390, height: 844)
        .environment(\.palette, Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
