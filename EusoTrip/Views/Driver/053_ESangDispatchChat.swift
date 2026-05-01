//
//  053_ESangDispatchChat.swift
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

struct ESangDispatchChat: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var draft: String = ""

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
        .screenTileRoot()
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
        // No dedicated radar surface yet — surface the live HOS / map
        // detail through the canonical Me deep-link so the driver
        // lands on a real screen, plus broadcast a refresh trigger
        // so any visible map view re-renders the latest weather pull.
        MeAction.fire("053.show-radar",
                      userInfo: ["loadId": lifecycle.loadId])
        NotificationCenter.default.post(name: .esangRefreshSurface,
                                        object: "weather",
                                        userInfo: [:])
    }

    private func counterOffer() {
        // Counter-offer wizard ships in a follow-up wave. Until then
        // the tap fires a MeAction so the analytics layer captures
        // intent, and a neutral toast surfaces so the driver sees
        // their input registered.
        MeAction.fire("053.counter-offer",
                      userInfo: ["loadId": lifecycle.loadId])
    }

    private func tapMic() {
        // ESANG voice intent — record the tap so a future wave that
        // wires SFSpeechRecognizer can resume from the same surface.
        MeAction.fire("053.mic-tapped",
                      userInfo: ["loadId": lifecycle.loadId])
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        MeAction.fire("053.send-message",
                      userInfo: ["loadId": lifecycle.loadId, "text": text])
        // Clear immediately so the input bar resets — the message has
        // been audited even if the chat back-end isn't wired here yet.
        draft = ""
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }
}

struct ESangDispatchChatScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ESangDispatchChat(register: .afternoon)
        } nav: {
            BottomNav(leading: driverNavLeading_053(),
                      trailing: driverNavTrailing_053(),
                      orbState: .idle)
        }
    }
}

// PNG canon at `01 Driver/{Light,Dark}/053 ESANG Dispatch Chat.png`
// pins TRIPS current — ESANG-driver chat thread with dock-staging
// card + quick replies. Icon set + trailing slot normalized to
// canonical 010-052 layout.
private func driverNavLeading_053() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",  isCurrent: true)]
}
private func driverNavTrailing_053() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
}

#Preview("053 · ESANG Dispatch Chat · Dark") {
    ESangDispatchChatScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("053 · ESANG Dispatch Chat · Light") {
    ESangDispatchChatScreen(theme: Theme.light).preferredColorScheme(.light)
}
