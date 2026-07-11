//
//  543_DispatcherRateNegotiation.swift
//  EusoTrip — Dispatcher · Rate Negotiation.
//
//  Verbatim SwiftUI port of:
//    `04 Dispatcher/Dark-SVG/543 Dispatcher Rate Negotiation.svg`
//
//  NEGOTIATION archetype — a spread-to-target gauge over a two-sided
//  counter-offer LADDER (a thread used by no other catalog screen). The
//  dispatcher sees the whole rate conversation, how far the live offer sits
//  from the ceiling, and counters or accepts in one tap.
//
//  Honest wiring — 0 stubs, fully dynamic (rateNegotiations confirmed on disk
//  2026-07-11):
//    • READ  rateNegotiations.list    (…:75, {status:"active",type:"load_rate"})
//            → the newest live load-rate thread this dispatcher is a party to.
//    • READ  rateNegotiations.getById (…:134, {id}) → the neg + both parties +
//            the full message ladder (each message carries a plaintext
//            offerAmount; the free-text body stays encrypted server-side).
//    • WRITE rateNegotiations.counterOffer (…:291, {negotiationId,amount}) →
//            "Counter $X" writes the round + broadcasts.
//    • WRITE rateNegotiations.accept       (…:346, {negotiationId}) → "Accept"
//            agrees the current offer.
//
//  HONEST NOTE: there is no explicit "target" column on a negotiation, so the
//  gauge ceiling is the highest offer floated in the thread (a real, derived
//  value) — not a fabricated target. Party labels are the real initiator /
//  respondent names, not hardcoded.
//
//  Persona: Aurora Freight Lines · Renée Marquette (RM), negotiating with the
//  shipper Eusorone (Diego Usoro). transportMode=truck; currency USD. NAV:
//  HOME · BOARD(current) · [orb] · COMMS · ME. Powered by ESANG AI™.
//  Author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Decoders

private struct NegList543: Decodable { let negotiations: [NegListRow543]; let total: Int }
private struct NegListRow543: Decodable { let id: Int }

private struct NegDetail543: Decodable {
    let id: Int
    let negotiationNumber: String?
    let subject: String?
    let status: String?
    let loadId: Int?
    let initiatorUserId: Int
    let respondentUserId: Int
    let initiator: NegParty543?
    let respondent: NegParty543?
    let messages: [NegMsg543]
}
private struct NegParty543: Decodable { let id: Int?; let name: String? }
private struct NegMsg543: Decodable, Identifiable {
    let id: Int
    let senderUserId: Int
    let round: Int?
    let messageType: String?
    let offerAmount: String?
    let createdAt: String?
    let sender: NegParty543?
    var amount: Double? { offerAmount.flatMap { Double($0) } }
}

// MARK: - Screen

struct DispatcherRateNegotiationScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DispatcherRateNegotiationBody() } nav: { DispatchPortNav() }
    }
}

// MARK: - Body

private struct DispatcherRateNegotiationBody: View {
    @Environment(\.palette) private var palette

    @State private var neg: NegDetail543?
    @State private var loading = true
    @State private var loadError: String?
    @State private var working = false
    @State private var actionNote: String?

    // Offers oldest→newest
    private var offers: [(amount: Double, msg: NegMsg543)] {
        (neg?.messages ?? [])
            .compactMap { m in m.amount.map { ($0, m) } }
            .sorted { ($0.msg.createdAt ?? "") < ($1.msg.createdAt ?? "") }
    }
    private var lo: Double { offers.map(\.amount).min() ?? 0 }
    private var hi: Double { offers.map(\.amount).max() ?? 0 }
    private var now: Double { offers.last?.amount ?? 0 }
    private var toTarget: Double { max(0, hi - now) }
    private var counterAmount: Double {
        // Push toward the ceiling: half the remaining gap, min +$50, rounded to $25.
        let step = toTarget > 0 ? max(50, toTarget * 0.5) : 50
        return (((now + step) / 25).rounded() * 25)
    }
    // newest-first ladder
    private var ladder: [NegMsg543] {
        (neg?.messages ?? [])
            .filter { $0.amount != nil }
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }
    private func isInitiatorSide(_ m: NegMsg543) -> Bool { m.senderUserId == (neg?.initiatorUserId ?? -1) }
    private func partyName(_ m: NegMsg543) -> String {
        if isInitiatorSide(m) { return neg?.initiator?.name ?? "Carrier" }
        return neg?.respondent?.name ?? "Shipper"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline().padding(.top, Space.s3)

            if loading {
                DispatchPortLoadingCard(text: "Loading negotiation…").padding(.top, Space.s5)
            } else if let err = loadError {
                DispatchPortErrorCard(message: err) { Task { await load() } }.padding(.top, Space.s5)
            } else if neg == nil || offers.isEmpty {
                EusoEmptyState(systemImage: "arrow.left.arrow.right.circle.fill",
                               title: "No live rate thread",
                               subtitle: "Open a rate negotiation from a load and the spread + counter ladder appears here.")
                    .padding(.top, Space.s6)
            } else {
                gaugeCard.padding(.top, Space.s5)
                ladderCard.padding(.top, Space.s5)
                esangCard.padding(.top, Space.s5)
                if let note = actionNote {
                    Text(note).font(EType.caption).foregroundStyle(palette.textSecondary).padding(.top, Space.s3)
                }
                ctaPair.padding(.top, Space.s5)
            }
        }
        .padding(.horizontal, 20).padding(.top, Space.s2)
        .task { await load() }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ DISPATCHER · RATE NEGOTIATION")
                    .font(EType.micro).tracking(1.0).foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                HStack(spacing: 5) {
                    Circle().fill(Brand.success).frame(width: 6, height: 6)
                    Text("LIVE").font(EType.micro).tracking(1.0).foregroundStyle(Brand.success)
                }
            }
            HStack(alignment: .center, spacing: Space.s3) {
                DispatchPortBackChevron()
                Text("Negotiation").font(EType.h1).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            Text(neg?.subject ?? (neg?.negotiationNumber ?? "load-rate thread"))
                .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1).padding(.leading, 40)
        }
    }

    // MARK: Spread gauge

    private var gaugeCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("SPREAD TO CEILING · \(neg?.negotiationNumber ?? "")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary).lineLimit(1)
                Spacer()
                Circle().fill(Brand.success).frame(width: 7, height: 7)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(PortMoney.full(now))
                    .font(.system(size: 40, weight: .bold).monospacedDigit()).foregroundStyle(palette.textPrimary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("latest offer").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                    Text(offers.last.map { partyName($0.msg) } ?? "—")
                        .font(EType.caption.weight(.bold)).foregroundStyle(Brand.escort).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(toTarget > 0 ? "\(PortMoney.full(toTarget)) to ceiling" : "at ceiling")
                        .font(EType.caption.weight(.bold).monospacedDigit()).foregroundStyle(Brand.escort)
                    Text("ceiling \(PortMoney.full(hi))").font(.system(size: 11).monospacedDigit()).foregroundStyle(palette.textTertiary)
                }
            }
            // track: lo → hi, marker at now
            GeometryReader { geo in
                let w = geo.size.width
                let frac = hi > lo ? CGFloat((now - lo) / (hi - lo)) : 1
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 6)
                    Capsule().fill(LinearGradient(colors: [Brand.blue, Brand.escort], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, w * frac), height: 6)
                    Rectangle().fill(Brand.success).frame(width: 2, height: 16).offset(x: w - 1, y: -5)
                    Circle().fill(Color.white).overlay(Circle().strokeBorder(Brand.escort, lineWidth: 3))
                        .frame(width: 16, height: 16).offset(x: max(0, w * frac - 8))
                }
            }
            .frame(height: 16)
            HStack {
                Text("ASK \(PortMoney.full(lo))").font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(palette.textSecondary)
                Spacer()
                Text("CEILING").font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.success)
            }
            Text("\(offers.count) offers · \(neg.map { "\($0.messages.count) messages" } ?? "")")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: Ladder (two-sided, newest first)

    private var ladderCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("COUNTER-OFFER LADDER")
                    .font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("rateNegotiations").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s2)

            VStack(spacing: Space.s3) {
                ForEach(Array(ladder.prefix(6))) { m in
                    ladderBubble(m)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func ladderBubble(_ m: NegMsg543) -> some View {
        let mine = isInitiatorSide(m)
        let accent: Color = mine ? Brand.escort : Brand.info
        return HStack {
            if !mine { bubbleBody(m, accent: accent, align: .leading); Spacer(minLength: 40) }
            else { Spacer(minLength: 40); bubbleBody(m, accent: accent, align: .trailing) }
        }
    }

    private func bubbleBody(_ m: NegMsg543, accent: Color, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 3) {
            HStack(spacing: Space.s2) {
                Text(partyName(m).uppercased())
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(accent).lineLimit(1)
                Text(relTime(m.createdAt)).font(.system(size: 9)).foregroundStyle(palette.textTertiary)
            }
            Text(PortMoney.full(m.amount ?? 0))
                .font(.system(size: 17, weight: .heavy).monospacedDigit()).foregroundStyle(palette.textPrimary)
            Text(offerKind(m.messageType)).font(.system(size: 9)).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: 210, alignment: align == .leading ? .leading : .trailing)
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.22), lineWidth: 1))
    }

    // MARK: ESANG card

    private var esangCard: some View {
        DispatchPortESangStrip(
            headline: toTarget > 0 ? "ESANG says: counter \(PortMoney.full(counterAmount))" : "ESANG says: hold — at ceiling",
            detail: toTarget > 0 ? "\(PortMoney.full(toTarget)) to ceiling · \(offers.count) rounds so far"
                                 : "latest offer is the highest floated · \(offers.count) rounds"
        )
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button { Task { await counter() } } label: {
                HStack(spacing: Space.s2) {
                    if working { ProgressView().tint(palette.textOnGradient) }
                    Text(working ? "Working…" : "Counter \(PortMoney.full(counterAmount))")
                        .font(EType.bodyStrong).foregroundStyle(palette.textOnGradient).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain).disabled(working || neg == nil)

            Button { Task { await accept() } } label: {
                Text("Accept").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .frame(width: 110).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(Color(hex: 0x232932)))
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }
            .buttonStyle(.plain).disabled(working || neg == nil)
        }
    }

    // MARK: Data + actions

    private func load() async {
        loading = true; loadError = nil
        struct ListIn: Encodable { let status: String; let type: String; let limit: Int }
        struct ByIdIn: Encodable { let id: Int }
        do {
            let list: NegList543 = try await EusoTripAPI.shared.query(
                "rateNegotiations.list", input: ListIn(status: "active", type: "load_rate", limit: 1))
            guard let first = list.negotiations.first else { neg = nil; loading = false; return }
            neg = try await EusoTripAPI.shared.query("rateNegotiations.getById", input: ByIdIn(id: first.id))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func counter() async {
        guard let id = neg?.id else { return }
        working = true; actionNote = nil
        struct In: Encodable { let negotiationId: Int; let amount: Double }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("rateNegotiations.counterOffer", input: In(negotiationId: id, amount: counterAmount))
            actionNote = "Countered at \(PortMoney.full(counterAmount))."
            await load()
        } catch {
            actionNote = "Couldn't counter: \((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)"
        }
        working = false
    }

    private func accept() async {
        guard let id = neg?.id else { return }
        working = true; actionNote = nil
        struct In: Encodable { let negotiationId: Int }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("rateNegotiations.accept", input: In(negotiationId: id))
            actionNote = "Accepted the current offer of \(PortMoney.full(now))."
            await load()
        } catch {
            actionNote = "Couldn't accept: \((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)"
        }
        working = false
    }

    // MARK: Formatting

    private func offerKind(_ t: String?) -> String {
        switch (t ?? "").lowercased() {
        case "initial_offer": return "posted ask"
        case "counter_offer": return "counter"
        case "acceptance": return "accepted"
        default: return "offer"
        }
    }
    private func relTime(_ iso: String?) -> String {
        guard let iso else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "" }
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 { return "just now" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        if secs < 86400 { return "\(secs / 3600)h ago" }
        return "\(secs / 86400)d ago"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("543 · Rate Negotiation · Dark") {
    DispatcherRateNegotiationScreen(theme: Theme.dark).environment(\.palette, Theme.dark)
}
#Preview("543 · Rate Negotiation · Light") {
    DispatcherRateNegotiationScreen(theme: Theme.light).environment(\.palette, Theme.light)
}
#endif
