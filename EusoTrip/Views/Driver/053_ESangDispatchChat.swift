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
//  Powered by ESANG AI™.
//

import SwiftUI

struct eSangDispatchChat: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @Environment(\.driverOpenMessages) private var openMessages
    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
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

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private let fallbackClock      = "09:34"
    private let fallbackBriefHash  = "X1"
    private let fallbackResetClock = "RES RESET 6/11/14"
    private let fallbackLoadHash   = "LOAD EUSO-004640"
    private let fallbackExpiresIn  = "EXPIRES 09:47"

    private var brief: String {
        let n = ctx.beatCommodityDescriptor
        return "Morning, Michael Eusorone. Reset returned at 09:30. I pulled one tender in your lane, Univar Curtis Bay to Yara York, \(n.contains("NH3") ? "NH3, " : "")150 mi, $1,420. Weather is 42°F scattered showers along I-83. Want the breakdown?"
    }

    private var driverReply: String {
        "Yeah, how does the rate compare and is tractor good to go?"
    }

    private var dispatchReply: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:
            return "$9.46/mi net, +$0.42 over lane avg the last 14 days. Tractor passed Saturday's post-trip, MC-331 domes were purged, urea at 78%. DOT inspection sticker expires May 14."
        case .reefer:
            return "$9.46/mi net, +$0.42 over lane avg. Reefer pulled-down to set-point, fuel at 64%, thermograph clean. DOT inspection clean."
        case .flatbed:
            return "$9.46/mi net, +$0.42 over lane avg. Tarps + 12 straps + 2 chains staged, WLL within spec. DOT inspection clean."
        case .container, .railIntermodal, .vesselContainer:
            return "$9.46/mi net, +$0.42 over lane avg. Chassis pre-trip clean, twistlocks oiled, EDI 322 armed. DOT inspection clean."
        case .railBulk, .vesselBulk:
            return "$9.46/mi net, +$0.42 over lane avg. Grounding kit checked, hatches sealed, AAR waybill ready."
        case .dryVan:
            return "$9.46/mi net, +$0.42 over lane avg. Trailer swept dry, seal staged, pallet jack on board. DOT inspection clean."
        }
    }

    private var prepReply: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:
            return "I queued the pre-trip DVIR and pre-loaded the ERG 125 card for UN1005. No surprise. I'll hold the tender 13 more minutes."
        case .reefer:
            return "Pre-trip DVIR is queued and the temp trace export is waiting. I'll hold the tender 13 more minutes."
        case .flatbed:
            return "Pre-trip DVIR queued + securement sheet pre-filled. I'll hold the tender 13 more minutes."
        case .container, .railIntermodal, .vesselContainer:
            return "Pre-trip DVIR queued + EDI 322 + VGM staged. I'll hold the tender 13 more minutes."
        case .railBulk, .vesselBulk:
            return "Pre-trip DVIR queued + AAR waybill loaded. I'll hold the tender 13 more minutes."
        case .dryVan:
            return "Pre-trip DVIR queued + BOL packet on tablet. I'll hold the tender 13 more minutes."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    statusRow
                    dayDivider
                    esangBubble(text: brief, time: "09:31")
                    driverBubble(text: driverReply, time: "09:31")
                    esangBubble(text: dispatchReply, time: "09:32", attachment: AnyView(routePreviewPill))
                    esangBubble(text: prepReply, time: "09:33")
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
                              multiVehicleCount: activeLoad?.multiVehicleCount,
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
            ChatStatusChip(label: fallbackResetClock, color: Brand.success, live: true)
            ChatStatusChip(label: fallbackLoadHash, color: palette.textSecondary)
            ChatStatusChip(label: fallbackExpiresIn, color: Brand.warning)
        }
    }

    private var dayDivider: some View { ChatDayDivider() }

    private func esangBubble(text: String, time: String, attachment: AnyView? = nil) -> some View {
        ChatBubbleReceived(avatar: .esang, text: text, time: time) {
            if let attachment { attachment }
        }
    }

    private func driverBubble(text: String, time: String) -> some View {
        ChatBubbleSent(text: text, time: time)
    }

    private var routePreviewPill: some View {
        ChatInlineCard(icon: "map.fill",
                       title: "Route preview · I-695 → I-83 N",
                       subtitle: "156 MI · 2:01 EFA · BAY 4 · PEAK 73°F",
                       badge: "OPEN")
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
        if let load = activeLoad {
            do {
                _ = try await EusoTripAPI.shared.drivers
                    .acceptLoad(loadId: String(load.id))
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
        guard let load = activeLoad else { return }
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
                loadId: String(load.id),
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
            guard let load = activeLoad else {
                openMessages?(nil)
                return
            }
            do {
                _ = try await EusoTripAPI.shared.messaging.sendMessage(
                    conversationId: String(load.id),
                    content: pendingText,
                    type: "text"
                )
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
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
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
    eSangDispatchChatScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("053 · ESANG Dispatch Chat · Light") {
    eSangDispatchChatScreen(theme: Theme.light).preferredColorScheme(.light)
}
