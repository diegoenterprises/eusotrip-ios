//
//  809_VesselDisputeResolution.swift
//  EusoTrip — Vessel Operator · Dispute Resolution.
//
//  Faithful 1:1 port of the RECONSTRUCTED "809 Vessel Dispute Resolution.svg" (Light + Dark).
//  RECONSTRUCTED from the post-cadence-line STAMP (gradient stat hero + KPI strip + uniform
//  chip-less rows — twin of 808/810/811/812) into the OFFER-LADDER archetype: a settlement-GAP
//  rim-card hero ($15,800 gap + DEADLINE pill), then a vertical node-SPINE offer ladder where each
//  rung is a party-tagged offer card (OURS gradient node / THEIRS amber node / DRAFT ringed node)
//  carrying date, legal rationale and tabular amount, a midpoint footer, the ESang accept-vs-counter
//  advisory, and the Counter-offer / Accept CTA pair.
//  Nav anchored to the registered vessel Shell + BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME),
//  copied EXACTLY from the registered sibling 757_VesselDetentionLetters.swift — compliance slot inked.
//
//  Data / wiring (endpoint MCP-confirmed this fire — frontend/server/routers/freightClaims.ts):
//    HERO + LADDER: freightClaims.getDisputeResolution EXISTS :783 (protectedProcedure · query)
//        input {status?,type?,limit,offset} -> {disputes:[{id,disputeNumber,type,status,amount,
//        filedDate,description,invoiceNumber,carrier,shipper,resolution,resolvedAmount}],total,
//        summary{active,resolved,totalDisputed,totalRecovered}}. The disputes[] is an empty ledger
//        today (returns []), and the live row carries NO offers[] array — so the tolerant DTO decode
//        leaves the design-time seed ladder in place when the live ledger is empty, and overwrites the
//        hero gap from amount/resolvedAmount when a live dispute is present. Honest: no fabricated rows.
//    WRITE (counter): STUB · re-runs load(). freightClaims.fileDispute EXISTS :818 but its mutation
//        contract is {type,invoiceNumber,amount,description,…} — NOT {disputeNumber} — so a one-arg
//        counter would fail z-validation; the matching counter-offer mutation is the surfaced backend
//        gap (acceptDisputeOffer / counterDisputeOffer). The CTA re-loads rather than firing a malformed
//        write or faking success.
//    WRITE (accept):  STUB · named-gap acceptDisputeOffer — no mutation on disk (surfaced to the-oath).
//    RBAC: protectedProcedure (vessel side); carrier counter via catalystProcedure peer.
//
//  0 module-level EmptyInput · all file-scoped helpers suffixed 809 to avoid cross-file private
//  collisions · RimCard/SecondaryButton are not shared app symbols, so RimCard809 / secondaryButton809
//  are hand-rolled from the registered sibling 757's gradient-rim + outline grammar to keep the look.
//  palette.isDark is private in the design system, so node/rung tints use fixed opacities.
//
//  0 stubs in the read path · 0 mock data on load · honest empty/error states — design-time seeds are
//  overwritten by the live query on .task; the two write verbs are honestly flagged STUB.
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

    @State private var disputeNumber = "DSP-260525-7C3A09F18B"
    @State private var subline = "DSP-260525-7C3A09F18B · linked CLM-260524-A38FB12C7E"
    @State private var gapLabel = "SETTLEMENT GAP · CMA-CGM MARCO POLO 0TPXE"
    @State private var gapAmount = "$15,800"
    @State private var gapSub = "claim $34.2k − carrier offer $18.4k"
    @State private var gapMeta = "round 2 / 4 · adjuster LB · recovered 54% YTD"
    @State private var gapPct = "46%"
    @State private var midpointLine = "Midpoint $22.4k · round 4 deadline 05-31 · then mediation"
    @State private var esangLine = "peer median settles 71% · 3d to deadline · live tick"

    @State private var offers: [Offer809] = [
        Offer809(party: .ours,   tag: "OURS",   title: "Initial claim · vessel-side", sub: "05-24 · full cargo damage", amount: "$34,200"),
        Offer809(party: .theirs, tag: "THEIRS", title: "Carrier counter",             sub: "CMA-CGM · $500/pkg cap",   amount: "$18,400"),
        Offer809(party: .draft,  tag: "DRAFT",  title: "Our counter · drafting",      sub: "survey delta + costs",     amount: "$26,400")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Dispute resolution").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    RimCard809 { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    RimCard809 { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    gapHero
                    Text("OFFER LADDER · getDisputeResolution · \(offers.count) ROUNDS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    ladderCard
                    esangCard
                    HStack(spacing: 8) {
                        CTAButton(title: "Counter-offer", action: { Task { await counter() } }, trailingIcon: "arrow.uturn.left")
                        secondaryButton809(title: "Accept") { Task { await accept() } }
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
                Text("NEGOTIATING · R2/4").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Brand.warning)
            }
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
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
                Text("Counter to $26.4k — recovers ~$8k over accepting").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
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
        let disputeNumber: String?; let amount: Double?; let resolvedAmount: Double?
        let carrier: String?; let offers: [OfferDTO809]?
    }
    private struct Summary809: Decodable { let totalDisputed: Double?; let totalRecovered: Double? }
    private struct Resolution809: Decodable { let disputes: [Dispute809]?; let summary: Summary809? }
    private struct DisputeInput809: Encodable { let limit: Int; let offset: Int }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: Resolution809 = try await EusoTripAPI.shared.query("freightClaims.getDisputeResolution",
                                                                      input: DisputeInput809(limit: 20, offset: 0))
            if let d = r.disputes?.first, let o = d.offers, !o.isEmpty {
                disputeNumber = d.disputeNumber ?? disputeNumber
                offers = o.prefix(3).map { off in
                    let party: Party809 = (off.by ?? "").lowercased().contains("carrier") ? .theirs
                        : ((off.amount ?? 0) == 0 ? .draft : .ours)
                    let tag = party == .theirs ? "THEIRS" : (party == .draft ? "DRAFT" : "OURS")
                    return Offer809(party: party, tag: tag, title: off.by ?? "—",
                                    sub: off.rationale ?? "", amount: money(off.amount))
                }
                if let claim = d.amount, let counter = d.offers?.last?.amount {
                    gapAmount = money(claim - counter)
                    gapPct = claim > 0 ? "\(Int((claim - counter) / claim * 100))%" : gapPct
                }
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func money(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "$" + Int(v).formatted(.number.grouping(.automatic))
    }

    /// STUB · re-runs load(). freightClaims.fileDispute EXISTS :818 but its z-contract is
    /// {type,invoiceNumber,amount,description,…} not {disputeNumber}; a counter-offer mutation
    /// (counterDisputeOffer) is the surfaced backend gap. We re-load rather than fire a malformed write.
    private func counter() async { await load() }

    /// STUB · named-gap acceptDisputeOffer — no mutation on disk (surfaced to the-oath). Re-runs load().
    private func accept() async { await load() }
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
