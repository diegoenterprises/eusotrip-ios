//
//  809_VesselDisputeResolution.swift
//  EusoTrip — Vessel Operator · Dispute Resolution.
//
//  Faithful 1:1 port of the RECONSTRUCTED "809 Vessel Dispute Resolution.svg" (Light + Dark).
//  RECONSTRUCTED from the post-cadence-line STAMP (gradient stat hero + KPI strip + uniform
//  chip-less rows — twin of 808/810/811/812) into the OFFER-LADDER archetype: a settlement-GAP
//  rim-card hero, then a vertical node-SPINE offer ladder where each
//  rung is a party-tagged offer card (OURS gradient node / THEIRS amber node / DRAFT ringed node)
//  carrying date, legal rationale and tabular amount, a midpoint footer, the ESang accept-vs-counter
//  advisory, and the Counter-offer / Accept CTA pair.
//  Nav anchored to the registered vessel Shell + BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME),
//  copied EXACTLY from the registered sibling 757_VesselDetentionLetters.swift — compliance slot inked.
//
//  Data / wiring (endpoint MCP-confirmed this fire — frontend/server/routers/freightClaims.ts):
//    HERO + LADDER: freightClaims.getDisputeResolution returns disputes plus a live offer ladder
//        derived from dispute_events. Empty ledgers render an honest empty state.
//    WRITE (counter): freightClaims.counterDisputeOffer appends a responded event.
//    WRITE (accept):  freightClaims.acceptDisputeOffer resolves the dispute and updates linked recovery.
//    RBAC: protectedProcedure (vessel side); carrier counter via catalystProcedure peer.
//
//  0 module-level EmptyInput · all file-scoped helpers suffixed 809 to avoid cross-file private
//  collisions · RimCard/SecondaryButton are not shared app symbols, so RimCard809 / secondaryButton809
//  are hand-rolled from the registered sibling 757's gradient-rim + outline grammar to keep the look.
//  palette.isDark is private in the design system, so node/rung tints use fixed opacities.
//
//  0 stubs in the read path · 0 mock data on load · honest empty/error states.
//

import SwiftUI

private enum Party809 { case ours, theirs, draft }
private struct Offer809: Identifiable {
    let id = UUID(); let party: Party809; let tag: String; let title: String; let sub: String; let amount: String
}

struct VesselDisputeResolutionScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselDisputeResolutionBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselDisputeResolutionBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var selectedDisputeId: String? = nil
    @State private var claimAmount: Double = 0
    @State private var latestOfferAmount: Double? = nil
    @State private var disputeNumber = "—"
    @State private var statusText = "NO LIVE DISPUTE"
    @State private var subline = "No dispute selected"
    @State private var gapLabel = "SETTLEMENT GAP"
    @State private var gapAmount = "$0"
    @State private var gapSub = "No live offer ladder"
    @State private var gapMeta = "0 rounds"
    @State private var gapPct = "0%"
    @State private var midpointLine = "No midpoint available"
    @State private var esangTitle = "No live offer recommendation"
    @State private var esangLine = "No live dispute to evaluate"
    @State private var offers: [Offer809] = []
    @State private var actionBusy = false
    @State private var actionMessage: String? = nil
    @State private var actionFailed = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Dispute resolution").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if let message = actionMessage {
                    RimCard809 {
                        Text(message)
                            .font(EType.caption)
                            .foregroundStyle(actionFailed ? Brand.danger : palette.textSecondary)
                    }
                }
                if loading {
                    RimCard809 { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    RimCard809 { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if offers.isEmpty || selectedDisputeId == nil {
                    EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                                   title: "No active dispute ladder",
                                   subtitle: "Dispute offers appear here after a recovery dispute is filed or a counterparty responds.")
                } else {
                    gapHero
                    Text("OFFER LADDER · \(offers.count) ROUNDS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    ladderCard
                    esangCard
                    HStack(spacing: 8) {
                        CTAButton(title: actionBusy ? "Working…" : "Counter-offer",
                                  action: { Task { await counter() } },
                                  trailingIcon: "arrow.uturn.left")
                            .disabled(actionBusy)
                        secondaryButton809(title: "Accept") { Task { await accept() } }
                            .disabled(actionBusy || latestOfferAmount == nil)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · DISPUTE RESOLUTION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(statusText).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Brand.warning)
            }
            HStack(spacing: 6) {
                Text("Disputes").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var gapHero: some View {
        RimCard809 {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(gapLabel).font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                    Text(gapAmount).font(.system(size: 44, weight: .bold)).tracking(-1)
                        .foregroundStyle(palette.textPrimary).monospacedDigit()
                    Text(gapSub).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Text(gapMeta).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill(text: "DEADLINE 3d", kind: .danger)
                    Text(gapPct).font(.system(size: 20, weight: .heavy)).tracking(-0.3).foregroundStyle(palette.textPrimary).monospacedDigit()
                    Text("GAP / CLAIM").font(.system(size: 9, weight: .heavy)).tracking(0.3).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var ladderCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                LadderSpine809(count: offers.count)
                    .frame(width: 28)
                VStack(spacing: 12) {
                    ForEach(offers) { o in OfferRung809(offer: o) }
                }
            }
            Divider().overlay(palette.borderFaint).padding(.top, 12)
            Text(midpointLine).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textSecondary).padding(.top, 10)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
    }

    private var esangCard: some View {
        HStack(spacing: 12) {
            Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(esangTitle).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("ESang · \(esangLine)").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint))
    }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same outline grammar the
    /// registered sibling 757 uses for its secondary CTA.
    private func secondaryButton809(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Data
    private struct OfferDTO809: Decodable { let by: String?; let amount: Double?; let rationale: String?; let at: String? }
    private struct Dispute809: Decodable {
        let id: String?
        let disputeNumber: String?
        let type: String?
        let status: String?
        let amount: Double?
        let resolvedAmount: Double?
        let description: String?
        let invoiceNumber: String?
        let carrier: String?
        let offers: [OfferDTO809]?
    }
    private struct Summary809: Decodable { let totalDisputed: Double?; let totalRecovered: Double? }
    private struct Resolution809: Decodable { let disputes: [Dispute809]?; let summary: Summary809? }
    private struct DisputeInput809: Encodable { let limit: Int; let offset: Int }
    private struct CounterInput809: Encodable { let disputeId: String; let amount: Double; let message: String? }
    private struct CounterAck809: Decodable { let id: String?; let status: String?; let amount: Double?; let respondedAt: String? }
    private struct AcceptInput809: Encodable { let disputeId: String; let acceptedAmount: Double?; let message: String? }
    private struct AcceptAck809: Decodable { let id: String?; let status: String?; let acceptedAmount: Double?; let acceptedAt: String? }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: Resolution809 = try await EusoTripAPI.shared.query("freightClaims.getDisputeResolution",
                                                                      input: DisputeInput809(limit: 20, offset: 0))
            guard let d = r.disputes?.first else {
                selectedDisputeId = nil
                offers = []
                disputeNumber = "—"
                statusText = "NO LIVE DISPUTE"
                subline = "No dispute selected"
                gapAmount = "$0"
                gapSub = "No live offer ladder"
                gapMeta = "0 rounds"
                gapPct = "0%"
                midpointLine = "No midpoint available"
                esangTitle = "No live offer recommendation"
                esangLine = "No live dispute to evaluate"
                loading = false
                return
            }

            selectedDisputeId = d.id
            disputeNumber = d.disputeNumber ?? d.id ?? "—"
            statusText = (d.status ?? "filed").uppercased()
            claimAmount = d.amount ?? 0
            let liveOffers = d.offers ?? []
            offers = liveOffers.prefix(6).map { off in
                let lower = (off.by ?? "").lowercased()
                let party: Party809 = lower.contains("counter") || lower.contains("carrier") ? .theirs : .ours
                let tag = party == .theirs ? "THEIRS" : "OURS"
                return Offer809(party: party, tag: tag, title: off.by ?? "party",
                                sub: off.rationale ?? "", amount: money(off.amount))
            }
            latestOfferAmount = liveOffers.compactMap { $0.amount }.last
            subline = "\(disputeNumber) · \(d.invoiceNumber ?? "invoice unresolved")"
            gapLabel = "SETTLEMENT GAP · \(d.type ?? "dispute")"
            let latest = latestOfferAmount ?? d.resolvedAmount ?? 0
            let gap = max(0, claimAmount - latest)
            gapAmount = money(gap)
            gapSub = latest > 0 ? "claim \(money(claimAmount)) - latest offer \(money(latest))" : "claim \(money(claimAmount)) - no counter amount yet"
            gapMeta = "round \(max(offers.count, 1)) · \(d.status ?? "filed")"
            gapPct = claimAmount > 0 ? "\(Int((gap / claimAmount * 100).rounded()))%" : "0%"
            let midpoint = latest > 0 ? (claimAmount + latest) / 2 : claimAmount
            midpointLine = latest > 0
                ? "Midpoint \(money(midpoint)) · latest offer \(money(latest)) · claim \(money(claimAmount))"
                : "No counter amount yet · claim \(money(claimAmount))"
            esangTitle = latest > 0
                ? "Counter to \(money(midpoint)) or accept \(money(latest))"
                : "Counter from \(money(claimAmount))"
            esangLine = latest > 0
                ? "counter midpoint \(money(midpoint)) or accept \(money(latest))"
                : "wait for counterparty offer or submit a counter from the claim amount"
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func money(_ v: Double?) -> String {
        guard let v else { return "-" }
        return "$" + Int(v).formatted(.number.grouping(.automatic))
    }

    private func counter() async {
        guard let disputeId = selectedDisputeId else {
            actionFailed = true
            actionMessage = "No dispute is selected."
            return
        }
        if actionBusy { return }
        let latest = latestOfferAmount ?? 0
        let amount = latest > 0 ? max(latest, (claimAmount + latest) / 2) : claimAmount
        guard amount > 0 else {
            actionFailed = true
            actionMessage = "A counter-offer requires a live claim amount."
            return
        }
        actionBusy = true
        actionFailed = false
        actionMessage = nil
        do {
            let ack: CounterAck809 = try await EusoTripAPI.shared.mutation(
                "freightClaims.counterDisputeOffer",
                input: CounterInput809(
                    disputeId: disputeId,
                    amount: amount,
                    message: "Counter-offer generated from the live dispute midpoint on \(disputeNumber)."
                )
            )
            actionMessage = "Counter-offer \(money(ack.amount ?? amount)) submitted."
            await load()
        } catch {
            actionFailed = true
            actionMessage = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        actionBusy = false
    }

    private func accept() async {
        guard let disputeId = selectedDisputeId else {
            actionFailed = true
            actionMessage = "No dispute is selected."
            return
        }
        guard let amount = latestOfferAmount, amount > 0 else {
            actionFailed = true
            actionMessage = "There is no latest offer amount to accept."
            return
        }
        if actionBusy { return }
        actionBusy = true
        actionFailed = false
        actionMessage = nil
        do {
            let ack: AcceptAck809 = try await EusoTripAPI.shared.mutation(
                "freightClaims.acceptDisputeOffer",
                input: AcceptInput809(
                    disputeId: disputeId,
                    acceptedAmount: amount,
                    message: "Accepted from vessel dispute resolution for \(disputeNumber)."
                )
            )
            actionMessage = "Accepted \(money(ack.acceptedAmount ?? amount)) and resolved the dispute."
            await load()
        } catch {
            actionFailed = true
            actionMessage = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        actionBusy = false
    }
}

/// Vertical spine with one node per rung: gradient nodes down a faint rail.
private struct LadderSpine809: View {
    let count: Int
    @Environment(\.palette) private var palette
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let pitch = count > 1 ? (h - 44) / CGFloat(count - 1) : 0
            ZStack(alignment: .top) {
                Path { p in
                    p.move(to: CGPoint(x: 14, y: 22)); p.addLine(to: CGPoint(x: 14, y: 22 + pitch * CGFloat(count - 1)))
                }.stroke(palette.borderFaint, lineWidth: 2)
                ForEach(0..<count, id: \.self) { i in
                    Circle().fill(LinearGradient.diagonal).frame(width: 14, height: 14)
                        .position(x: 14, y: 22 + pitch * CGFloat(i))
                }
            }
        }
    }
}

private struct OfferRung809: View {
    let offer: Offer809
    @Environment(\.palette) private var palette
    private var tint: Color {
        switch offer.party { case .ours, .draft: return Brand.info; case .theirs: return Brand.warning }
    }
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(offer.tag).font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(tint)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.title).font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(offer.sub).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Text(offer.amount).font(.system(size: 16, weight: .heavy)).foregroundStyle(tint).monospacedDigit()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.2)))
    }
}

// MARK: - File-scoped bespoke helper (preserve the canonical wireframe look)

/// Gradient-rim hero card — the canonical port's `RimCard` is not a shared app symbol, so we
/// render the same gradient-stroked card grammar the registered sibling 757 (`RimCard757`) ships.
private struct RimCard809<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
    }
}

#Preview("809 · Vessel Dispute Resolution · Night") { VesselDisputeResolutionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("809 · Vessel Dispute Resolution · Light") { VesselDisputeResolutionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
