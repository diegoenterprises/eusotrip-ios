//
//  SH261_ShipperM04ObservedNonet.swift
//  EusoTrip — Shipper · M-04 observed nonet (SH261-SH269).
//
//  Pixel-match to:
//    261 Shipper Fresh Matrix Posted
//    262 Shipper Bidding Observed M04
//    263 Shipper Competing Observed M04
//    264 Shipper Third Quote Observed M04
//    265 Shipper Fourth Quote Observed M04
//    266 Shipper Award Cel M04
//    267 Shipper Pickup On-Site Echo M04
//    268 Shipper In Transit Echo M04
//    269 Shipper At Delivery Echo M04
//
//  Shipper-vantage of Catalyst CV369-CV376 — same scenario (Atlanta →
//  Charlotte, $1,650 target, 4 competing carriers), but the shipper
//  observes rather than authors quotes. All 9 share
//  `ShipperM04ObservedBody` parameterized by `ShipperM04Kind`. Bottom
//  nav frozen.
//

import SwiftUI

private struct SMLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let rate: String?
    let distance: Double?
    let equipmentType: String?
    let driver: SMParty?
    let catalyst: SMParty?
    let shipper: SMParty?
    struct SMParty: Decodable, Hashable {
        let id: Int?
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
    }
}

enum ShipperM04Kind: String {
    case freshPosted, firstQuote, secondQuote, thirdQuote, fourthQuote, awarded, onSite, inTransit, atDelivery
}

// Stage descriptor — POSITIONAL/STRUCTURAL only (lifecycle citation §,
// stage label, next-step prompt). It carries NO business facts: every
// carrier name, MC/DOT, bid amount, lead, target, lane and KPI value is
// derived at render time from the live `shippers.getBidsForLoad` ladder
// and the live `loads.getById` context — never hardcoded.
private struct SMStage {
    let eyebrow: String      // stage label for the SHIPPER · LOADS eyebrow
    let citation: String     // lifecycle §-citation (positional, no facts)
}

private extension ShipperM04Kind {
    var stage: SMStage {
        switch self {
        case .freshPosted:
            return .init(eyebrow: "POSTED · FRESH CHAIN",
                         citation: "§359 · CHAIN PORT 1/N · POSTED · BIDS OPEN")
        case .firstQuote:
            return .init(eyebrow: "BIDDING · FIRST QUOTE",
                         citation: "§361 · CHAIN PORT 3/N · BIDDING · 1ST QUOTE IN")
        case .secondQuote:
            return .init(eyebrow: "BIDDING · COMPETING",
                         citation: "§363 · CHAIN PORT 5/N · BIDDING · 2 QUOTES IN")
        case .thirdQuote:
            return .init(eyebrow: "BIDDING · 3-QUOTE OBSERVED",
                         citation: "§365 · CHAIN PORT 7/N · BIDDING · 3 QUOTES IN")
        case .fourthQuote:
            return .init(eyebrow: "BIDDING · 4-QUOTE OBSERVED",
                         citation: "§367 · CHAIN PORT 9/N · BIDDING · 4 QUOTES IN")
        case .awarded:
            return .init(eyebrow: "AWARDED",
                         citation: "§368 · CHAIN PORT 10/N · AWARDED · TENDER ACCEPT")
        case .onSite:
            return .init(eyebrow: "PICKUP · ON-SITE ECHO",
                         citation: "§389 · CHAIN PORT 14/N · PICKUP · ON-SITE")
        case .inTransit:
            return .init(eyebrow: "IN-TRANSIT · ECHO",
                         citation: "§397 · CHAIN PORT 15/N · IN-TRANSIT · ROLLING")
        case .atDelivery:
            return .init(eyebrow: "AT-DELIVERY · ECHO",
                         citation: "§401 · CHAIN PORT 16/N · DELIVERY · ARRIVED · QUARTET CLOSES")
        }
    }
}

private struct ShipperM04Shell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",          isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "ESANG", systemImage: "sparkles", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",   isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct ShipperM04ObservedBody: View {
    let loadId: String
    let kind: ShipperM04Kind

    @Environment(\.palette) private var palette
    @State private var load: SMLoadCtx?
    @StateObject private var bids = ShipperBidsStore()

    // MARK: - Live derivations

    /// The live bid ladder, sorted lowest-first (a reverse auction: the
    /// lowest offer leads). Empty until `shippers.getBidsForLoad` settles.
    private var ladder: [ShipperAPI.Bid] {
        if case .loaded(let rows) = bids.state {
            return rows.sorted { $0.amount < $1.amount }
        }
        return []
    }

    /// Lead bid = the server's `recommended` flag if any row carries it,
    /// otherwise the lowest amount. Nil when there are no bids.
    private var leadBid: ShipperAPI.Bid? {
        ladder.first(where: { $0.recommended }) ?? ladder.first
    }

    /// Shipper's posted target rate from `loads.getById` (`rate` is a
    /// stringified USD figure). Nil when the load context hasn't loaded
    /// or the rate is non-numeric.
    private var targetRate: Double? {
        guard let raw = load?.rate else { return nil }
        let cleaned = raw.filter { $0.isNumber || $0 == "." }
        return Double(cleaned)
    }

    var body: some View {
        let s = kind.stage
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(s)
                citationPill(s)
                quoteLadderCard
                identityRow
                kpiGrid
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task {
            await loadCtx()
            bids.setLoadId(loadId)
            await bids.refresh()
        }
        .refreshable {
            await loadCtx()
            await bids.refresh()
        }
    }

    // MARK: - Dynamic display helpers

    private var loadNumberDisplay: String { load?.loadNumber ?? "—" }
    private var laneDisplay: String? {
        guard let p = load?.pickupCity, let d = load?.destCity else { return nil }
        return "\(p) → \(d)"
    }
    private var distanceDisplay: String? {
        guard let d = load?.distance, d > 0 else { return nil }
        return "\(Int(d)) mi"
    }

    /// Live title — derived from the lead bid + lane, never hardcoded.
    private var liveTitle: String {
        switch kind {
        case .freshPosted:
            return laneDisplay.map { "Posted · \($0) · bids open" } ?? "Posted · bids open"
        case .awarded:
            if let b = leadBid { return "Awarded to \(b.catalystName) · \(usd(b.amount))" }
            return "Awarded · pending bid feed"
        case .onSite, .inTransit, .atDelivery:
            if let b = leadBid { return "\(b.catalystName) · \(usd(b.amount))" }
            return "Awarded carrier · live"
        case .firstQuote, .secondQuote, .thirdQuote, .fourthQuote:
            if let b = leadBid {
                let count = ladder.count
                return "\(b.catalystName) leads · \(usd(b.amount)) · \(count) quote\(count == 1 ? "" : "s")"
            }
            return "Bids open · awaiting first quote"
        }
    }

    /// Live subhead — lead/count/lane, never hardcoded amounts.
    private var liveSubhead: String {
        var parts: [String] = [kind.stage.citation.components(separatedBy: " · ").first ?? ""]
        if let b = leadBid { parts.append("LEAD \(initials(b.catalystName)) · \(usd(b.amount))") }
        if !ladder.isEmpty { parts.append("\(ladder.count) QUOTE\(ladder.count == 1 ? "" : "S")") }
        if let lane = laneDisplay { parts.append(lane) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func header(_ s: SMStage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · LOADS · \(s.eyebrow) · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            Text(liveTitle).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(liveSubhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ s: SMStage) -> some View {
        // Live chain line built from the real load context + lead bid.
        var chain: [String] = [loadNumberDisplay]
        if let lane = laneDisplay { chain.append(lane) }
        if let dist = distanceDisplay { chain.append(dist) }
        if let eq = load?.equipmentType, !eq.isEmpty { chain.append(eq) }
        if let t = targetRate { chain.append("target \(usd(t))") }
        let chainLine = chain.joined(separator: " · ")
        return LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(s.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(s.eyebrow).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(chainLine).font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var quoteLadderCard: some View {
        switch bids.state {
        case .loading:
            LifecycleCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OBSERVED QUOTES").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Loading observed bids…").font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
            }
        case .empty:
            LifecycleCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OBSERVED QUOTES").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text("No bids yet — carriers will surface offers as they tender on this load.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .loaded:
            quoteLadder(ladder)
        case .error(let err):
            LifecycleCard(accentDanger: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OBSERVED QUOTES").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text((err as? EusoTripAPIError)?.errorDescription ?? err.localizedDescription)
                        .font(EType.caption).foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func quoteLadder(_ rows: [ShipperAPI.Bid]) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("OBSERVED QUOTES").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                ForEach(rows) { q in
                    let isLead = q.id == leadBid?.id
                    HStack(spacing: 8) {
                        Circle().fill(isLead ? LinearGradient.diagonal : LinearGradient(colors: [palette.bgPage, palette.bgPage], startPoint: .top, endPoint: .bottom))
                            .frame(width: 22, height: 22)
                            .overlay(Text(initials(q.catalystName)).font(.system(size: 8, weight: .heavy)).foregroundStyle(isLead ? .white : palette.textSecondary))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(q.catalystName).font(.caption2.weight(.semibold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                            Text(dashIfEmpty(q.dotNumber)).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(usd(q.amount)).font(.system(size: 14, weight: .heavy).monospacedDigit())
                                .foregroundStyle(isLead ? Color.green : palette.textPrimary)
                            if let t = targetRate {
                                let delta = q.amount - t
                                Text("\(delta >= 0 ? "+" : "−")\(usd(abs(delta))) vs target").font(.caption2).foregroundStyle(palette.textTertiary)
                            } else if q.recommended {
                                Text("ESANG ★").font(.caption2).foregroundStyle(palette.textTertiary)
                            }
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(palette.bgPage))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isLead ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1))
                }
            }
        }
    }

    private var identityRow: some View {
        // Identity sourced from the live load context (shipper party +
        // lane), with honest dashes when the context hasn't resolved.
        let shipperLine: String = {
            var bits: [String] = []
            if let co = load?.shipper?.companyName, !co.isEmpty { bits.append(co) }
            if let nm = load?.shipper?.name, !nm.isEmpty { bits.append(nm) }
            bits.append("shipper")
            return bits.joined(separator: " · ")
        }()
        var contextBits: [String] = [loadNumberDisplay]
        if let lane = laneDisplay { contextBits.append(lane) }
        if let dist = distanceDisplay { contextBits.append(dist) }
        if let t = targetRate { contextBits.append("target \(usd(t))") }
        let contextLine = contextBits.joined(separator: " · ")
        let avatar = load?.shipper?.initials ?? load?.shipper?.name.map { initials($0) } ?? "—"
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(avatar).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(shipperLine).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text(contextLine).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let lead = leadBid
        let target = targetRate
        let savings: Double? = {
            guard let t = target, let b = lead else { return nil }
            return t - b.amount
        }()
        let savingsCaption: String = {
            guard let s = savings else { return "vs target —" }
            return s >= 0 ? "−\(usd(abs(s))) vs target" : "+\(usd(abs(s))) over target"
        }()
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .freshPosted:
                return [
                    ("STATE",   "POSTED",                        "bids window open",                        .green),
                    ("TARGET",  target.map { usd($0) } ?? "—",   "shipper target",                          .blue),
                    ("QUOTES",  "\(ladder.count)",               ladder.isEmpty ? "awaiting tenders" : "live carriers", .blue),
                    ("DIST",    distanceDisplay ?? "—",          dashIfEmpty(load?.equipmentType),          .blue),
                ]
            case .firstQuote, .secondQuote, .thirdQuote, .fourthQuote:
                return [
                    ("LEAD",    lead.map { initials($0.catalystName) } ?? "—",  lead?.catalystName ?? "no bids yet", .green),
                    ("BEST",    lead.map { usd($0.amount) } ?? "—",             savingsCaption,                      .green),
                    ("QUOTES",  "\(ladder.count)",                              "live carriers",                     .blue),
                    ("LANE",    distanceDisplay ?? "—",                         dashIfEmpty(load?.equipmentType),    .blue),
                ]
            case .awarded:
                return [
                    ("WINNER",  lead.map { initials($0.catalystName) } ?? "—",  lead.map { "\($0.catalystName) · \(usd($0.amount))" } ?? "pending feed", .green),
                    ("BEST",    lead.map { usd($0.amount) } ?? "—",             savingsCaption,                      .green),
                    ("STATE",   "AWARDED",                                      "tender accept",                     .green),
                    ("QUOTES",  "\(ladder.count)",                              "bids observed",                     .blue),
                ]
            case .onSite:
                return [
                    ("STATE",   "ON-SITE",                                      lead?.catalystName ?? "awarded carrier", .green),
                    ("LANE",    distanceDisplay ?? "—",                         laneDisplay ?? "—",                  .blue),
                    ("AMOUNT",  lead.map { usd($0.amount) } ?? "—",             savingsCaption,                      .green),
                    ("QUOTES",  "\(ladder.count)",                              "bids observed",                     .blue),
                ]
            case .inTransit:
                return [
                    ("STATE",   "ROLLING",                                      lead?.catalystName ?? "awarded carrier", .green),
                    ("LANE",    distanceDisplay ?? "—",                         laneDisplay ?? "—",                  .blue),
                    ("AMOUNT",  lead.map { usd($0.amount) } ?? "—",             savingsCaption,                      .green),
                    ("QUOTES",  "\(ladder.count)",                              "bids observed",                     .blue),
                ]
            case .atDelivery:
                return [
                    ("STATE",   "ARRIVED",                                      lead?.catalystName ?? "awarded carrier", .green),
                    ("LANE",    distanceDisplay ?? "—",                         laneDisplay ?? "—",                  .green),
                    ("AMOUNT",  lead.map { usd($0.amount) } ?? "—",             savingsCaption,                      .green),
                    ("POD",     "PENDING",                                      "quartet closes on co-sign",         .orange),
                ]
            }
        }()
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.0).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.1).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.3)
                    Text(k.2).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.3.opacity(0.3)))
            }
        }
    }

    private var nextStepCard: some View {
        let lead = leadBid
        let copy: String = {
            switch kind {
            case .freshPosted:
                return "Load posted with bids open. Carriers tender as they pick up the lane; the observed ladder fills in below as offers arrive."
            case .firstQuote, .secondQuote, .thirdQuote, .fourthQuote:
                if let b = lead {
                    let count = ladder.count
                    return "\(b.catalystName) leads at \(usd(b.amount)) across \(count) observed quote\(count == 1 ? "" : "s"). Watch for under-cuts before the window closes."
                }
                return "Bids are open but none have landed yet. The lead carrier and best price surface here as carriers tender."
            case .awarded:
                if let b = lead {
                    return "Awarded to \(b.catalystName) at \(usd(b.amount)). Tender acceptance and pickup arm next in the chain."
                }
                return "Award stage — the winning bid surfaces here once the bid feed resolves."
            case .onSite, .inTransit, .atDelivery:
                if let b = lead {
                    return "\(b.catalystName) carries this load at \(usd(b.amount)). Status echoes through the chain as the driver progresses."
                }
                return "The awarded carrier surfaces here once the bid feed resolves."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.map { String($0.prefix(1)) }.joined().uppercased()
        return s.isEmpty ? "—" : s
    }
}

// MARK: - Screens (SH261-SH269)

struct ShipperM04FreshPostedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperM04Shell(theme: theme) { ShipperM04ObservedBody(loadId: loadId, kind: .freshPosted) } }
}
struct ShipperM04FirstQuoteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperM04Shell(theme: theme) { ShipperM04ObservedBody(loadId: loadId, kind: .firstQuote) } }
}
struct ShipperM04SecondQuoteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperM04Shell(theme: theme) { ShipperM04ObservedBody(loadId: loadId, kind: .secondQuote) } }
}
struct ShipperM04ThirdQuoteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperM04Shell(theme: theme) { ShipperM04ObservedBody(loadId: loadId, kind: .thirdQuote) } }
}
struct ShipperM04FourthQuoteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperM04Shell(theme: theme) { ShipperM04ObservedBody(loadId: loadId, kind: .fourthQuote) } }
}
struct ShipperM04AwardedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperM04Shell(theme: theme) { ShipperM04ObservedBody(loadId: loadId, kind: .awarded) } }
}
struct ShipperM04OnSiteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperM04Shell(theme: theme) { ShipperM04ObservedBody(loadId: loadId, kind: .onSite) } }
}
struct ShipperM04InTransitScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperM04Shell(theme: theme) { ShipperM04ObservedBody(loadId: loadId, kind: .inTransit) } }
}
struct ShipperM04AtDeliveryScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperM04Shell(theme: theme) { ShipperM04ObservedBody(loadId: loadId, kind: .atDelivery) } }
}

// MARK: - Previews

#Preview("SH261 Posted · Dark")     { ShipperM04FreshPostedScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("SH262 1st · Light")       { ShipperM04FirstQuoteScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("SH263 2nd · Dark")        { ShipperM04SecondQuoteScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("SH264 3rd · Light")       { ShipperM04ThirdQuoteScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("SH265 4th · Dark")        { ShipperM04FourthQuoteScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("SH266 Award · Light")     { ShipperM04AwardedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("SH267 OnSite · Dark")     { ShipperM04OnSiteScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("SH268 Transit · Light")   { ShipperM04InTransitScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("SH269 AtDel · Dark")      { ShipperM04AtDeliveryScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
