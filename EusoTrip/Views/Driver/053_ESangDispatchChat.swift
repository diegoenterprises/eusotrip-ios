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
    @FocusState private var draftFieldFocused: Bool

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
        return "Morning, Michael Eusorone. Reset returned at 09:30. I pulled one tender in your lane — Univar Curtis Bay to Yara York, \(n.contains("NH3") ? "NH3, " : "")150 mi, $1,420. Weather is 42°F scattered showers along I-83. Want the breakdown?"
    }

    private var driverReply: String {
        "Yeah — how does the rate compare and is tractor good to go?"
    }

    private var dispatchReply: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:
            return "$9.46/mi net — +$0.42 over lane avg the last 14 days. Tractor passed Saturday's post-trip, MC-331 domes were purged, urea at 78%. DOT inspection sticker expires May 14."
        case .reefer:
            return "$9.46/mi net — +$0.42 over lane avg. Reefer pulled-down to set-point, fuel at 64%, thermograph clean. DOT inspection clean."
        case .flatbed:
            return "$9.46/mi net — +$0.42 over lane avg. Tarps + 12 straps + 2 chains staged, WLL within spec. DOT inspection clean."
        case .container, .railIntermodal, .vesselContainer:
            return "$9.46/mi net — +$0.42 over lane avg. Chassis pre-trip clean, twistlocks oiled, EDI 322 armed. DOT inspection clean."
        case .railBulk, .vesselBulk:
            return "$9.46/mi net — +$0.42 over lane avg. Grounding kit checked, hatches sealed, AAR waybill ready."
        case .dryVan:
            return "$9.46/mi net — +$0.42 over lane avg. Trailer swept dry, seal staged, pallet jack on board. DOT inspection clean."
        }
    }

    private var prepReply: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:
            return "I queued the pre-trip DVIR and pre-loaded the ERG 125 card for UN1005. No surprise — I'll hold the tender 13 more minutes."
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
                    esangBubble(text: brief, time: "09:31")
                    driverBubble(text: driverReply, time: "09:31")
                    esangBubble(text: dispatchReply, time: "09:32", attachment: AnyView(routePreviewPill))
                    esangBubble(text: prepReply, time: "09:33")
                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            quickReplies
            inputBar
        }
        .task { await hydrateLiveTrip() }
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
        HStack(alignment: .top, spacing: 10) {
            Button { navBack?() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 30, height: 30)
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text("ESANG")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text(fallbackBriefHash)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .overlay(Capsule().stroke(LinearGradient.diagonal.opacity(0.5), lineWidth: 1))
                        LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                      multiVehicleCount: activeLoad?.multiVehicleCount,
                                      compact: true)
                    }
                    Text("MORNING BRIEF · JUST NOW")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
            Text(fallbackClock)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Space.s3)
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            statusChip(label: fallbackResetClock, color: Brand.success)
            statusChip(label: "LOAD EUSO-004640", color: palette.textSecondary)
            statusChip(label: fallbackExpiresIn, color: Brand.warning)
            Spacer()
        }
    }

    private func statusChip(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .heavy)).tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
    }

    private func esangBubble(text: String, time: String, attachment: AnyView? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                Image(systemName: "sparkles").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .padding(Space.s3)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                if let attachment {
                    attachment
                }
                Text(time)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 36)
        }
    }

    private func driverBubble(text: String, time: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Spacer(minLength: 36)
            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .font(EType.body)
                    .foregroundStyle(.white)
                    .padding(Space.s3)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                Text(time)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var routePreviewPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "map.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 1) {
                Text("Route preview · I-695 → I-83 N")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("156 MI · 2:01 EFA · BAY 4 · PEAK 73°F")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text("OPEN")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(LinearGradient.diagonal)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var quickReplies: some View {
        HStack(spacing: Space.s2) {
            quickChip("Accept tender", isPrimary: true) { Task { await acceptTender() } }
            quickChip("Show radar") { showRadar() }
            quickChip("Counter offer") { counterOffer() }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, Space.s2)
    }

    private func quickChip(_ label: String, isPrimary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(isPrimary ? .white : palette.textPrimary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 8)
                .background(isPrimary ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                .overlay(
                    Capsule()
                        .stroke(isPrimary ? Color.clear : palette.borderSoft, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            HStack {
                TextField("Ask ESANG…", text: $draft)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .submitLabel(.send)
                    .focused($draftFieldFocused)
                    .onSubmit { sendDraft() }
                Spacer()
                Button { tapMic() } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 10)
            .background(palette.bgCard)
            .overlay(
                Capsule().stroke(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(Capsule())

            Button { showDocClassifier = true } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Attach document")

            Button { sendDraft() } label: {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 40, height: 40)
                        .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
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
            line = "📎 Document attached — couldn't confidently identify it, please confirm what it is."
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
                s += " — " + keyFields.joined(separator: ", ")
            } else if !doc.summary.isEmpty {
                s += " — " + doc.summary
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
        draftFieldFocused = true
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

    private func tapMic() {
        // Mic tap → focus the text input + open the keyboard. Voice
        // dictation is then available via the iOS keyboard's mic
        // button — real today, no SFSpeechRecognizer dependency.
        // When DictationBroker ships (per feedback_watch_voice
        // doctrine) the focus state can route through it instead.
        MeAction.fire("053.mic-tapped",
                      userInfo: ["loadId": lifecycle.loadId])
        draftFieldFocused = true
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
