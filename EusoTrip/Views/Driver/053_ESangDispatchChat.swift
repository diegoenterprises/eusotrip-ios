//
//  053_eSangDispatchChat.swift
//  EusoTrip — Lifecycle screen 053 · ESANG Dispatch Chat.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `053 ESANG Dispatch Chat.png`. Conversational layer that sits
//  on the morning brief — driver and ESANG-mediated dispatcher
//  exchange, route preview pill, quick-reply chips, and a voice/
//  text input bar.
//
//  ── Honest binding (2026-06-06) ──────────────────────────────
//  The transcript used to be a hardcoded persona scene (Univar /
//  Yara / $1,420 / 42°F / Michael Eusorone / MC-331 / EUSO-004640).
//  None of that had a live source. It is GONE. What renders now:
//
//    • Load facts (lane, distance, rate, RPM-vs-lane-avg, HOS
//      reset) bind to live procs — `loads.getById` (CORRECTED shape:
//      top-level id:String?, nested pickupLocation/deliveryLocation
//      {city,state}, party objects), `hos.getStatus`, and
//      `rates.compareLaneRate`. Anything with no live value renders
//      an honest "—".
//    • The transcript binds to the REAL message thread via
//      `messaging.getMessages(conversationId: loadId)`. When the
//      thread is empty (the ESANG canned dialogue has no live
//      source) the message rail shows an honest empty/loading state
//      — never a fabricated customer/commodity/price line.
//
//  Visual layout / chrome / nav are preserved verbatim.
//
//  Powered by ESANG AI™.
//

import SwiftUI

/// Server-shaped projection of `loads.getById` — the CORRECTED wire
/// contract proven in DL133/DL126/DL091:
///   • top-level `id` is a String (server emits `String(load.id)`);
///     decoding as Int throws typeMismatch and blanks the whole screen.
///   • `pickupLocation`/`deliveryLocation` are nested {city,state}
///     objects (server sends "" — not nil — when a piece is missing).
///   • `driver`/`catalyst`/`shipper` are PARTY objects with a numeric
///     party id plus name / initials / companyName / mcNumber / dotNumber.
private struct ESDChatLoadCtx: Decodable, Hashable {
    let id: String?
    let loadNumber: String?
    let pickupLocation: ESDLoc?
    let deliveryLocation: ESDLoc?
    let rate: String?
    let distance: Double?
    let cargoType: String?
    let equipmentType: String?
    let transportMode: String?
    let driver: ESDParty?
    let catalyst: ESDParty?
    let shipper: ESDParty?
    struct ESDLoc: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct ESDParty: Decodable, Hashable {
        let id: Int?
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }
}

struct eSangDispatchChat: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @Environment(\.driverOpenMessages) private var openMessages
    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: ESDChatLoadCtx?
    @State private var hos: HOSStatus?
    @State private var lane: RatesAPI.LaneComparison?
    @State private var transcript: [MessagingMessage] = []
    @State private var transcriptLoading: Bool = true
    @State private var draft: String = ""
    @State private var showCounterSheet: Bool = false
    @State private var counterAmount: String = ""
    @State private var counterNote: String = ""
    @State private var counterInflight: Bool = false
    @State private var sendInflight: Bool = false
    @State private var actionToast: String? = nil
    @State private var showDocClassifier: Bool = false
    /// Real Speech.framework voice-to-text — the same controller the
    /// Shipper coach sheet drives. Bound live to the composer while
    /// recording so the text you SEE is the text ESANG receives.
    @StateObject private var voice = eSangVoiceInputController()

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .afternoon) { self.register = register }

    // MARK: - Live display helpers (honest "—" fallback)

    /// "Curtis Bay, MD → York, PA" — composed from the nested
    /// pickup/delivery {city,state}; em-dash when an endpoint is blank.
    private var laneDisplay: String {
        let o = [activeLoad?.pickupLocation?.city, activeLoad?.pickupLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        let d = [activeLoad?.deliveryLocation?.city, activeLoad?.deliveryLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        guard !o.isEmpty || !d.isEmpty else { return "—" }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }

    /// "150 mi" — em-dash when distance is missing/zero.
    private var distanceDisplay: String {
        guard let d = activeLoad?.distance, d > 0 else { return "—" }
        return "\(Int(d.rounded())) mi"
    }

    /// "$1,420" — em-dash when rate is missing/invalid.
    private var rateDisplay: String {
        guard let r = activeLoad?.rate, let n = Double(r), n > 0 else { return "—" }
        let v = n.rounded()
        return v < 1000 ? "$\(Int(v))" : "$\(Int(v).formatted(.number))"
    }

    /// Load reference for the status chip — real loadNumber, else "—".
    private var loadHashDisplay: String { activeLoad?.loadNumber ?? "—" }

    /// HOS reset clock from `hos.getStatus` — the next break-due ISO
    /// drives the "RESET" chip; em-dash when no live HOS status.
    private var resetClockDisplay: String {
        guard let due = hos?.nextBreakDue,
              let date = ISO8601DateFormatter().date(from: due) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"
        return "RESET \(f.string(from: date))"
    }

    /// "DRIVE 7h 22m" — live drive-remaining from hos.getStatus.
    private var driveRemainingDisplay: String {
        guard let s = hos else { return "—" }
        return "DRIVE \(s.drivingRemainingDisplay)"
    }

    /// Live RPM-vs-lane-avg sentence from rates.compareLaneRate, or "—".
    private var rpmComparisonDisplay: String? {
        guard let c = lane, c.marketAvgRPM > 0 else { return nil }
        let delta = c.yourRPM - c.marketAvgRPM
        let sign = delta >= 0 ? "+" : "−"
        return String(format: "$%.2f/mi · %@$%.2f vs lane avg",
                      c.yourRPM, sign, abs(delta))
    }

    /// Driver greeting name from the session — never a hardcoded persona.
    private var greetingName: String {
        let f = session.user?.firstName ?? ""
        return f.isEmpty ? "driver" : f
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    statusRow
                    dayDivider
                    loadFactsBubble
                    transcriptSection
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            watchingPill
            quickReplies
            inputBar
        }
        .task { await hydrateLiveTrip() }
        .onAppear {
            // Hand the real transcript back into the composer. Append so a
            // dictation can extend a half-typed message rather than clobber it.
            voice.onFinalTranscript = { transcript in
                let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                draft = trimmed.isEmpty ? transcript : "\(trimmed) \(transcript)"
            }
        }
        .onDisappear { voice.cancel() }
        .sheet(isPresented: $showCounterSheet) {
            counterComposerSheet
                .environment(\.palette, palette)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showDocClassifier) {
            DocumentClassifierSheet(
                mode: .prefillWizard,
                callerContext: "esang dispatch chat",
                onApplySingle: { doc in attachClassifiedDoc(doc) },
                onDispatchBatch: { _ in }
            )
            .environment(\.palette, palette)
        }
        .overlay(alignment: .bottom) {
            if let msg = actionToast {
                Text(msg)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: actionToast)
        .screenTileRoot()
    }

    /// Counter-offer composer — shared shape with 052. Real submit
    /// fires `drivers.counterOffer` server-side.
    private var counterComposerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("COUNTER OFFER")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Submit a different rate")
                        .font(EType.body.weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                    if let load = activeLoad,
                       let rate = Double(load.rate ?? ""),
                       rate > 0 {
                        Text("Posted rate: $\(Int(rate))")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    HStack {
                        Text("$")
                            .font(EType.body.weight(.heavy))
                            .foregroundStyle(palette.textPrimary)
                        TextField("Amount", text: $counterAmount)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("CONDITIONS (OPTIONAL)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(palette.textSecondary)
                    TextField("e.g. weekend rate, PG-1 hazmat", text: $counterNote)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Cancel") { showCounterSheet = false }
                            .buttonStyle(.bordered)
                            .disabled(counterInflight)
                        Spacer()
                        Button {
                            Task { await submitCounter() }
                        } label: {
                            HStack(spacing: 6) {
                                if counterInflight {
                                    ProgressView().controlSize(.small).tint(.white)
                                }
                                Text(counterInflight ? "Sending…" : "Send counter")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(counterInflight || counterAmount.isEmpty)
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("Counter offer")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        ChatHeaderESang(
            breadcrumb: "DRIVER · ESANG DISPATCH",
            statusText: "ONLINE · DISPATCH LINKED",
            online: true,
            onBack: { navBack?() },
            accessory: {
                LoadModeBadge(modeRaw: activeLoad?.transportMode,
                              multiVehicleCount: nil,
                              compact: true)
            },
            overflow: {
                // Mirrors the real quick actions so nothing is dead.
                Menu {
                    Button { Task { await acceptTender() } } label: {
                        Label("Accept tender", systemImage: "checkmark.circle")
                    }
                    Button { counterOffer() } label: {
                        Label("Counter offer", systemImage: "arrow.left.arrow.right")
                    }
                    Button { showRadar() } label: {
                        Label("Show radar", systemImage: "dot.radiowaves.left.and.right")
                    }
                    Button { showDocClassifier = true } label: {
                        Label("Attach document", systemImage: "paperclip")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
            }
        )
    }

    private var statusRow: some View {
        ChatStatusRow {
            ChatStatusChip(label: resetClockDisplay, color: Brand.success, live: true)
            ChatStatusChip(label: loadHashDisplay, color: palette.textSecondary)
            ChatStatusChip(label: driveRemainingDisplay, color: Brand.warning)
        }
    }

    private var dayDivider: some View { ChatDayDivider() }

    /// The one ESANG bubble that DOES have a live source: the load
    /// facts ESANG is "watching" for this tender. Lane / distance /
    /// rate from `loads.getById`, RPM vs lane avg from
    /// `rates.compareLaneRate`, drive-remaining from `hos.getStatus`.
    /// Every value is real or em-dash — no commodity, customer, price
    /// or weather is invented.
    private var loadFactsBubble: some View {
        esangBubble(
            text: "Morning, \(greetingName). Here's the tender I'm watching in your lane: \(laneDisplay) · \(distanceDisplay) · \(rateDisplay). Drive remaining \(hos?.drivingRemainingDisplay ?? "—").",
            time: nil,
            attachment: AnyView(routePreviewPill)
        )
    }

    /// The live conversation. When the messaging thread for this load
    /// has messages, render them as bubbles. When it's empty — the
    /// ESANG canned dialogue has no live backing source — show an
    /// honest empty / loading state rather than a scripted exchange.
    @ViewBuilder private var transcriptSection: some View {
        if !transcript.isEmpty {
            ForEach(transcript) { m in
                if m.isOwn == true {
                    driverBubble(text: m.content, time: timeLabel(m.timestamp))
                } else {
                    esangBubble(text: m.content, time: timeLabel(m.timestamp))
                }
            }
        } else if transcriptLoading {
            HStack {
                Spacer()
                ProgressView()
                    .controlSize(.regular)
                    .padding(.vertical, 24)
                Spacer()
            }
        } else {
            EusoEmptyState(
                systemImage: "bubble.left.and.bubble.right",
                title: "No messages yet",
                subtitle: "Start the conversation below — your dispatch thread for this tender shows up here the moment a message lands."
            )
        }
    }

    private func esangBubble(text: String, time: String?, attachment: AnyView? = nil) -> some View {
        ChatBubbleReceived(avatar: .esang, text: text, time: time) {
            if let attachment { attachment }
        }
    }

    private func driverBubble(text: String, time: String?) -> some View {
        ChatBubbleSent(text: text, time: time)
    }

    /// Route preview pill — real lane + distance from the load; the
    /// RPM comparison line surfaces only when rates.compareLaneRate
    /// returned a real lane average.
    private var routePreviewPill: some View {
        ChatInlineCard(icon: "map.fill",
                       title: laneDisplay == "—" ? "Route preview" : "Route · \(laneDisplay)",
                       subtitle: rpmComparisonDisplay ?? "\(distanceDisplay) · \(rateDisplay)",
                       badge: activeLoad == nil ? nil : "OPEN")
    }

    /// Live "ESANG is watching X" presence pill — centered, above the
    /// quick-reply rail, matching the AFTER frame.
    private var watchingPill: some View {
        ChatPresencePill(text: "ESANG monitoring this tender · live")
            .padding(.bottom, Space.s2)
    }

    private var quickReplies: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ChatQuickChip(label: "Accept tender", highlighted: true) { Task { await acceptTender() } }
                ChatQuickChip(label: "Show radar") { showRadar() }
                ChatQuickChip(label: "Counter offer") { counterOffer() }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, Space.s2)
    }

    private var inputBar: some View {
        ChatComposer(
            draft: $draft,
            voice: voice,
            placeholder: "Ask ESANG…",
            showUpload: true,
            showVoice: true,
            sending: sendInflight,
            onUpload: { showDocClassifier = true },
            onSend: { sendDraft() },
            onToggleVoice: {
                MeAction.fire("053.voice-toggled",
                              userInfo: ["loadId": lifecycle.loadId,
                                         "recording": !voice.isRecording])
            }
        )
        .padding(.horizontal, 14)
        .padding(.bottom, Space.s3)
    }

    // MARK: - Actions

    private func acceptTender() async {
        // Real `drivers.acceptLoad` mutation flips loadBids server-
        // side to status='accepted' AND binds the driver. Without
        // it the lifecycle transition runs but the marketplace
        // doesn't know who took the tender (same fix as 052).
        if let id = activeLoad?.id, !id.isEmpty {
            do {
                _ = try await EusoTripAPI.shared.drivers
                    .acceptLoad(loadId: id)
            } catch {
                actionToast = "Accept failed: \(error.localizedDescription)"
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                actionToast = nil
                return
            }
        }
        MeAction.fire("053.accept-tender",
                      userInfo: ["loadId": lifecycle.loadId])
        let keys = ["accept", "tender_accepted", "assigned", "approach"]
        if let t = lifecycle.availableTransitions
            .first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }

    private func showRadar() {
        // Switch to Home tab + post a refresh so the active live-
        // map surface (013/018 / live tracking) re-pulls the
        // latest weather + traffic. The driver lands on a REAL
        // screen, not an inert ack.
        MeAction.fire("053.show-radar",
                      userInfo: ["loadId": lifecycle.loadId])
        NotificationCenter.default.post(name: .esangRefreshSurface,
                                        object: "weather",
                                        userInfo: [:])
        // Walk the trip phase backward toward the live route so the
        // driver sees the map under the current phase.
        navBack?()
    }

    private func counterOffer() {
        // Open the counter-offer composer (same pattern as 052).
        // Pre-fills with the load's posted rate × 1.05.
        if let load = activeLoad {
            let rate = Double(load.rate ?? "") ?? 0
            if rate > 0 {
                counterAmount = String(format: "%.0f", rate * 1.05)
            }
        }
        counterNote = ""
        showCounterSheet = true
    }

    private func submitCounter() async {
        guard !counterInflight else { return }
        guard let id = activeLoad?.id, !id.isEmpty else { return }
        guard let amount = Double(counterAmount), amount > 0 else {
            actionToast = "Enter a valid rate"
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            actionToast = nil
            return
        }
        counterInflight = true
        defer { counterInflight = false }
        do {
            _ = try await EusoTripAPI.shared.drivers.counterOffer(
                loadId: id,
                amount: amount,
                conditions: counterNote.isEmpty ? nil : counterNote
            )
            MeAction.fire("053.counter-offer",
                          userInfo: ["loadId": lifecycle.loadId, "amount": amount])
            showCounterSheet = false
            actionToast = "Counter sent"
        } catch {
            actionToast = "Counter failed: \(error.localizedDescription)"
        }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        actionToast = nil
    }

    /// A document was classified by the vision spine. Insert an
    /// honest, concise reference line into the chat input so the
    /// driver (and ESANG, once the message lands) knows exactly what
    /// the document is — never a type the classifier didn't return.
    private func attachClassifiedDoc(_ doc: ClassifiedDocument) {
        let confidencePct = Int((doc.confidence * 100).rounded())
        // Low confidence or no real type → don't assert a label.
        let unconfident = doc.classifiedType.isEmpty
            || doc.classifiedType.lowercased() == "unknown"
            || doc.confidence < 0.6

        let line: String
        if unconfident {
            line = "📎 Document attached. Couldn't confidently identify it, please confirm what it is."
        } else {
            let label = humanDocType(doc.classifiedType)
            var s = "📎 \(label) (\(confidencePct)%)"
            // Append a couple of key extracted fields when present so
            // ESANG gets the salient details, not just a type name.
            let keyFields = doc.fields
                .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
                .sorted { $0.key < $1.key }
                .prefix(3)
                .map { "\(humanFieldKey($0.key)): \($0.value)" }
            if !keyFields.isEmpty {
                s += " - " + keyFields.joined(separator: ", ")
            } else if !doc.summary.isEmpty {
                s += " - " + doc.summary
            }
            line = s
        }

        // Surface any classifier warnings honestly on their own line.
        let warningLine = doc.warnings.isEmpty
            ? ""
            : "\n⚠ " + doc.warnings.prefix(2).joined(separator: "; ")

        let insertion = line + warningLine
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = trimmed.isEmpty ? insertion : "\(draft)\n\(insertion)"

        MeAction.fire("053.doc-classified",
                      userInfo: ["loadId": lifecycle.loadId,
                                 "type": doc.classifiedType,
                                 "confidence": doc.confidence])
    }

    /// Local human-readable mapping for the doc types most likely to
    /// surface in dispatch chat (BOL / POD / rate con / credentials).
    /// Falls back to a de-snaked title for anything else.
    private func humanDocType(_ raw: String) -> String {
        switch raw {
        case "bill_of_lading": return "Bill of Lading"
        case "rate_confirmation": return "Rate Confirmation"
        case "proof_of_delivery": return "Proof of Delivery"
        case "load_tender": return "Load Tender"
        case "run_ticket": return "Run Ticket"
        case "weight_ticket", "scale_ticket": return "Weight Ticket"
        case "us_cdl": return "CDL"
        case "us_medical_card": return "Medical Card"
        case "us_coi", "ca_coi": return "Insurance Certificate"
        case "lumper_receipt": return "Lumper Receipt"
        case "fuel_receipt": return "Fuel Receipt"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func humanFieldKey(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2",
                                  options: .regularExpression)
            .capitalized
    }

    /// "09:31" — formats a message ISO timestamp for the bubble; nil
    /// (no time row) when the server didn't send one.
    private func timeLabel(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let parsers: [ISO8601DateFormatter] = {
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return [withFrac, plain]
        }()
        guard let date = parsers.lazy.compactMap({ $0.date(from: iso) }).first else { return nil }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sendInflight else { return }
        sendInflight = true
        // Optimistic clear — the chat input resets immediately so
        // the driver can keep typing while the round-trip lands.
        let pendingText = text
        draft = ""
        MeAction.fire("053.send-message",
                      userInfo: ["loadId": lifecycle.loadId, "text": pendingText])
        Task {
            defer { Task { @MainActor in sendInflight = false } }
            // Use the load id as the conversation id — the messages
            // router treats `loadId` as a stable conversation key
            // for dispatch chat threads. If the load isn't hydrated
            // yet, fall back to the messaging inbox.
            guard let id = activeLoad?.id, !id.isEmpty else {
                openMessages?(nil)
                return
            }
            do {
                _ = try await EusoTripAPI.shared.messaging.sendMessage(
                    conversationId: id,
                    content: pendingText,
                    type: "text"
                )
                // Re-pull the thread so the just-sent message renders
                // from the live source rather than an optimistic stub.
                await loadTranscript(conversationId: id)
            } catch {
                Task { @MainActor in
                    actionToast = "Send failed: \(error.localizedDescription)"
                    draft = pendingText  // restore so the driver can retry
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    actionToast = nil
                }
            }
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()

        // HOS reset / drive-remaining are independent of any specific
        // load — pull regardless so the chips render even on an empty board.
        hos = try? await EusoTripAPI.shared.hos.getStatus()

        guard !lifecycle.loadId.isEmpty else {
            transcriptLoading = false
            return
        }

        // Load facts — CORRECTED loads.getById shape (id:String? + nested loc).
        struct In: Encodable { let id: String }
        activeLoad = try? await EusoTripAPI.shared.query(
            "loads.getById", input: In(id: lifecycle.loadId))

        // Lane-avg RPM (rates.compareLaneRate) — only when we have the
        // real origin/dest states + rate + distance to ask with.
        await loadLaneComparison()

        // Real message thread for this tender, keyed by load id.
        await loadTranscript(conversationId: lifecycle.loadId)
    }

    private func loadLaneComparison() async {
        guard let load = activeLoad,
              let oState = load.pickupLocation?.state, !oState.isEmpty,
              let dState = load.deliveryLocation?.state, !dState.isEmpty,
              let rate = Double(load.rate ?? ""), rate > 0,
              let distance = load.distance, distance > 0 else { return }
        lane = try? await EusoTripAPI.shared.rates.compareLaneRate(
            originState: oState,
            destState: dState,
            rate: rate,
            distance: distance,
            cargoType: load.cargoType,
            transportMode: load.transportMode ?? "truck"
        )
    }

    private func loadTranscript(conversationId: String) async {
        transcriptLoading = true
        defer { transcriptLoading = false }
        if let rows = try? await EusoTripAPI.shared.messaging.getMessages(
            conversationId: conversationId, limit: 50) {
            transcript = rows
        }
    }
}

struct eSangDispatchChatScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            eSangDispatchChat(register: .afternoon)
        } nav: {
            BottomNav(leading: driverNavLeading_053(),
                      trailing: driverNavTrailing_053(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_053() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_053() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("053 · ESANG Dispatch Chat · Dark") {
    eSangDispatchChatScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("053 · ESANG Dispatch Chat · Light") {
    eSangDispatchChatScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
