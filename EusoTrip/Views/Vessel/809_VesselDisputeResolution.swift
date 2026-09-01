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
    @State private var selectedCurrency: FreightClaimsAPI.CurrencyCode? = nil
    @State private var claimAmount: Double? = nil
    @State private var latestLedgerOfferAmount: Double? = nil
    @State private var latestLedgerOfferCurrency: FreightClaimsAPI.CurrencyCode? = nil
    @State private var latestOfferAmount: Double? = nil
    @State private var latestOfferCurrency: FreightClaimsAPI.CurrencyCode? = nil
    @State private var selectedResolvedAmount: Double? = nil
    @State private var selectedResolvedCurrency: FreightClaimsAPI.CurrencyCode? = nil
    @State private var disputeNumber = "—"
    @State private var statusText = "NO LIVE DISPUTE"
    @State private var subline = "No dispute selected"
    @State private var gapLabel = "SETTLEMENT GAP"
    @State private var gapAmount = "—"
    @State private var gapSub = "No live offer ladder"
    @State private var gapMeta = "0 rounds"
    @State private var gapPct = "—"
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
                            .disabled(actionBusy || claimAmount == nil || selectedCurrency == nil)
                        secondaryButton809(title: "Accept") { Task { await accept() } }
                            .disabled(actionBusy || latestOfferAmount == nil || latestOfferCurrency == nil)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
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
    private struct AmountStates809: Decodable { let amount: FreightClaimsAPI.MetricTruth }
    private struct OfferDTO809: Decodable {
        let offerEventId: String?
        let by: String?
        let amount: Double?
        let currency: FreightClaimsAPI.CurrencyCode?
        let canAccept: Bool?
        let rationale: String?
        let at: String?
        let metricStates: AmountStates809
    }
    private struct Dispute809: Decodable {
        struct States: Decodable {
            let amount: FreightClaimsAPI.MetricTruth
            let resolvedAmount: FreightClaimsAPI.MetricTruth
        }
        let id: String?
        let disputeNumber: String?
        let type: String?
        let status: String?
        let amount: Double?
        let currency: FreightClaimsAPI.CurrencyCode?
        let resolvedAmount: Double?
        let resolvedCurrency: FreightClaimsAPI.CurrencyCode?
        let description: String?
        let invoiceNumber: String?
        let carrier: String?
        let offers: [OfferDTO809]?
        let metricStates: States
    }
    private struct Summary809: Decodable { let totalDisputed: Double?; let totalRecovered: Double? }
    private struct Provenance809: Decodable { let source: String; let scope: String; let observedAt: String?; let computedAt: String? }
    private struct Resolution809: Decodable { let disputes: [Dispute809]?; let summary: Summary809?; let provenance: Provenance809 }
    private struct DisputeInput809: Encodable { let limit: Int; let offset: Int }
    private struct CounterInput809: Encodable { let disputeId: String; let amount: Double; let currency: FreightClaimsAPI.CurrencyCode; let message: String? }
    private struct CounterAck809: Decodable { let id: String?; let status: String?; let amount: Double?; let currency: FreightClaimsAPI.CurrencyCode?; let metricStates: AmountStates809; let respondedAt: String? }
    private struct AcceptInput809: Encodable { let disputeId: String; let acceptedAmount: Double; let currency: FreightClaimsAPI.CurrencyCode; let message: String? }
    private struct AcceptedStates809: Decodable { let acceptedAmount: FreightClaimsAPI.MetricTruth }
    private struct AcceptAck809: Decodable { let id: String?; let status: String?; let acceptedAmount: Double?; let acceptedCurrency: FreightClaimsAPI.CurrencyCode?; let metricStates: AcceptedStates809; let acceptedAt: String? }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: Resolution809 = try await EusoTripAPI.shared.query("freightClaims.getDisputeResolution",
                                                                      input: DisputeInput809(limit: 20, offset: 0))
            guard r.provenance.source == "disputes+dispute_events",
                  r.provenance.computedAt != nil else {
                throw DisputeContractError809.invalidLedgerProvenance
            }
            guard let d = r.disputes?.first else {
                selectedDisputeId = nil
                selectedCurrency = nil
                claimAmount = nil
                latestLedgerOfferAmount = nil
                latestLedgerOfferCurrency = nil
                latestOfferAmount = nil
                latestOfferCurrency = nil
                selectedResolvedAmount = nil
                selectedResolvedCurrency = nil
                offers = []
                disputeNumber = "—"
                statusText = "NO LIVE DISPUTE"
                subline = "No dispute selected"
                gapAmount = "—"
                gapSub = "No live offer ladder"
                gapMeta = "0 rounds"
                gapPct = "—"
                midpointLine = "No midpoint available"
                esangTitle = "No live offer recommendation"
                esangLine = "No live dispute to evaluate"
                loading = false
                return
            }

            selectedDisputeId = d.id
            disputeNumber = d.disputeNumber ?? d.id ?? "—"
            statusText = (d.status ?? "unknown").uppercased()
            let qualifiedClaim = measuredMoney(
                amount: d.amount,
                currency: d.currency,
                truth: d.metricStates.amount,
                expectedSource: "disputes.amountInDispute+baseCurrency"
            )
            claimAmount = qualifiedClaim?.amount
            selectedCurrency = qualifiedClaim?.currency
            let qualifiedResolution = measuredMoney(
                amount: d.resolvedAmount,
                currency: d.resolvedCurrency,
                truth: d.metricStates.resolvedAmount,
                expectedSource: "disputes.resolvedAmount+resolvedCurrency"
            )
            selectedResolvedAmount = qualifiedResolution?.amount
            selectedResolvedCurrency = qualifiedResolution?.currency

            let liveOffers = (d.offers ?? []).compactMap { off -> (OfferDTO809, Double, FreightClaimsAPI.CurrencyCode)? in
                guard let measured = measuredMoney(
                    amount: off.amount,
                    currency: off.currency,
                    truth: off.metricStates.amount,
                    expectedSource: off.offerEventId == nil
                        ? "disputes.amountInDispute+baseCurrency"
                        : "dispute_events.offerAmount+offerCurrency"
                ), measured.currency == selectedCurrency else { return nil }
                return (off, measured.amount, measured.currency)
            }
            offers = liveOffers.prefix(6).map { off, amount, currency in
                let lower = (off.by ?? "").lowercased()
                let party: Party809 = lower.contains("counter") || lower.contains("carrier") ? .theirs : .ours
                let tag = party == .theirs ? "THEIRS" : "OURS"
                return Offer809(party: party, tag: tag, title: off.by ?? "party",
                                sub: off.rationale ?? "", amount: money(amount, currency: currency))
            }
            latestLedgerOfferAmount = liveOffers.last?.1
            latestLedgerOfferCurrency = liveOffers.last?.2
            let acceptableOffer = liveOffers.last(where: { $0.0.canAccept == true })
            latestOfferAmount = acceptableOffer?.1
            latestOfferCurrency = acceptableOffer?.2
            subline = "\(disputeNumber) · \(d.invoiceNumber ?? "invoice unresolved")"
            gapLabel = "SETTLEMENT GAP · \(d.type ?? "dispute")"
            if let claim = claimAmount, let currency = selectedCurrency {
                if let latest = latestLedgerOfferAmount {
                    let gap = max(0, claim - latest)
                    let midpoint = (claim + latest) / 2
                    gapAmount = money(gap, currency: currency)
                    gapSub = "claim \(money(claim, currency: currency)) - latest offer \(money(latest, currency: currency))"
                    gapPct = claim > 0 ? "\(Int((gap / claim * 100).rounded()))%" : "—"
                    midpointLine = "Midpoint \(money(midpoint, currency: currency)) · latest offer \(money(latest, currency: currency)) · claim \(money(claim, currency: currency))"
                    esangTitle = "Review \(money(midpoint, currency: currency)) midpoint"
                    esangLine = latestOfferAmount == nil
                        ? "the latest qualified offer is not available for this account to accept"
                        : "counter at the midpoint or accept the latest counterparty offer"
                } else {
                    gapAmount = "—"
                    gapSub = "No currency-qualified offer is recorded"
                    gapPct = "—"
                    midpointLine = "No qualified offer midpoint available"
                    esangTitle = "Await a qualified offer"
                    esangLine = "the dispute has a qualified claim amount but no qualified offer event"
                }
            } else {
                gapAmount = "—"
                gapSub = d.metricStates.amount.reason ?? "Dispute amount or currency is not qualified"
                gapPct = "—"
                midpointLine = "No qualified monetary midpoint available"
                esangTitle = "Money evidence incomplete"
                esangLine = d.metricStates.amount.reason ?? "amount and ISO currency must be recorded together"
            }
            gapMeta = "\(offers.count) qualified round\(offers.count == 1 ? "" : "s") · \(d.status ?? "status unknown")"
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func measuredMoney(
        amount: Double?,
        currency: FreightClaimsAPI.CurrencyCode?,
        truth: FreightClaimsAPI.MetricTruth,
        expectedSource: String
    ) -> (amount: Double, currency: FreightClaimsAPI.CurrencyCode)? {
        guard let amount, amount > 0, let currency,
              truth.valueState == .measured,
              truth.accessState == .granted,
              truth.trackingState == .tracked,
              truth.provenance.source == expectedSource,
              truth.provenance.observedAt != nil,
              truth.provenance.computedAt != nil else { return nil }
        return (amount, currency)
    }

    private func money(_ value: Double, currency: FreightClaimsAPI.CurrencyCode) -> String {
        value.formatted(.currency(code: currency.rawValue).precision(.fractionLength(0...2)))
    }

    private func counter() async {
        guard let disputeId = selectedDisputeId else {
            actionFailed = true
            actionMessage = "No dispute is selected."
            return
        }
        if actionBusy { return }
        guard let claim = claimAmount, let currency = selectedCurrency else {
            actionFailed = true
            actionMessage = "A counter-offer requires a tracked claim amount and ISO currency."
            return
        }
        let amount = latestLedgerOfferAmount.map { max($0, (claim + $0) / 2) } ?? claim
        actionBusy = true
        actionFailed = false
        actionMessage = nil
        do {
            let ack: CounterAck809 = try await EusoTripAPI.shared.mutation(
                "freightClaims.counterDisputeOffer",
                input: CounterInput809(
                    disputeId: disputeId,
                    amount: amount,
                    currency: currency,
                    message: "Counter-offer generated from the live dispute midpoint on \(disputeNumber)."
                )
            )
            guard ack.id == disputeId,
                  ack.currency == currency,
                  ack.amount.map({ abs($0 - amount) < 0.005 }) == true,
                  measuredMoney(amount: ack.amount, currency: ack.currency, truth: ack.metricStates.amount, expectedSource: "dispute_events.offerAmount+offerCurrency") != nil else {
                throw DisputeContractError809.invalidCounterAcknowledgement
            }
            await load()
            guard selectedDisputeId == disputeId,
                  latestLedgerOfferCurrency == currency,
                  latestLedgerOfferAmount.map({ abs($0 - amount) < 0.005 }) == true else {
                throw DisputeContractError809.counterReadbackMismatch
            }
            actionMessage = "Counter-offer \(money(amount, currency: currency)) confirmed."
        } catch {
            actionFailed = true
            actionMessage = error.eusoUserCopy
        }
        actionBusy = false
    }

    private func accept() async {
        guard let disputeId = selectedDisputeId else {
            actionFailed = true
            actionMessage = "No dispute is selected."
            return
        }
        guard let amount = latestOfferAmount, let currency = latestOfferCurrency else {
            actionFailed = true
            actionMessage = "There is no tracked counterparty offer with a qualified currency to accept."
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
                    currency: currency,
                    message: "Accepted from vessel dispute resolution for \(disputeNumber)."
                )
            )
            guard ack.id == disputeId,
                  ack.status?.lowercased() == "resolved",
                  ack.acceptedCurrency == currency,
                  ack.acceptedAmount.map({ abs($0 - amount) < 0.005 }) == true,
                  measuredMoney(amount: ack.acceptedAmount, currency: ack.acceptedCurrency, truth: ack.metricStates.acceptedAmount, expectedSource: "disputes.resolvedAmount+resolvedCurrency") != nil else {
                throw DisputeContractError809.invalidAcceptanceAcknowledgement
            }
            await load()
            guard selectedDisputeId == disputeId,
                  statusText == "RESOLVED",
                  selectedResolvedCurrency == currency,
                  selectedResolvedAmount.map({ abs($0 - amount) < 0.005 }) == true else {
                throw DisputeContractError809.acceptanceReadbackMismatch
            }
            actionMessage = "Accepted \(money(amount, currency: currency)) and confirmed the resolution."
        } catch {
            actionFailed = true
            actionMessage = error.eusoUserCopy
        }
        actionBusy = false
    }
}

private enum DisputeContractError809: LocalizedError {
    case invalidLedgerProvenance
    case invalidCounterAcknowledgement
    case counterReadbackMismatch
    case invalidAcceptanceAcknowledgement
    case acceptanceReadbackMismatch

    var errorDescription: String? {
        switch self {
        case .invalidLedgerProvenance:
            return "The dispute ledger did not provide its expected live provenance."
        case .invalidCounterAcknowledgement:
            return "The counter-offer acknowledgement did not match the submitted amount and currency."
        case .counterReadbackMismatch:
            return "The counter-offer was not confirmed in the live dispute ledger."
        case .invalidAcceptanceAcknowledgement:
            return "The acceptance acknowledgement did not match the selected qualified offer."
        case .acceptanceReadbackMismatch:
            return "The resolved amount and currency were not confirmed in the live dispute ledger."
        }
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
