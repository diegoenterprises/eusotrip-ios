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

            // Document upload — the real affordance, not just mic+send.
            // Opens the document router; the classifier tells us EXACTLY
            // what the doc is before it ever reaches ESANG.
            Button { showDocClassifier = true } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(voice.isRecording || sending)
            .accessibilityLabel("Attach document")

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
        // Snapshot the env dispatcher at call time so the async
        // follow-up isn't reading a stale @Environment value.
        let dispatcher = autopilot
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
                await MainActor.run {
                    if !cleaned.isEmpty {
                        messages.append(Msg(role: .esang, text: cleaned))
                    }
                    sending = false
                    // Stagger so a navigate-then-execute sequence animates
                    // naturally instead of stepping on itself.
                    for (idx, action) in actions.enumerated() {
                        let delay = Double(idx) * 0.20
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            dispatcher?(action)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    sendError = "ESANG couldn't reach the server. Try again."
                    sending = false
                }
            }
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
            headline = "I couldn't confidently identify this document (\(conf)% confidence) — please confirm what it is."
        } else {
            headline = "Got it — that's a \(humanDocType(doc.classifiedType)) (\(conf)% confidence)."
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
            draft = "About the document I just shared — "
        } else {
            draft = "About this \(humanDocType(doc.classifiedType).lowercased()) — "
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
