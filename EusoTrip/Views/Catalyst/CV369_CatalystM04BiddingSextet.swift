//
//  CV369_CatalystM04BiddingSextet.swift
//  EusoTrip — Catalyst · M-04 multi-broker bidding sextet (CV369-CV374).
//
//  Pixel-match to:
//    369 Catalyst First Bid M04
//    370 Catalyst Competing Quote M04
//    371 Catalyst Southern Crescent Competing M04
//    372 Catalyst Carolina Competing M04
//    373 Catalyst Awarded Cel M04
//    374 Catalyst Pickup On-Site Echo Cel M04
//
//  Scenario: Atlanta GA → Charlotte NC · 53' Dry Van · 245 mi · 4
//  competing carriers (Aurora / Piedmont / Southern Crescent / Carolina
//  Express). All 6 share `CatalystM04BiddingBody` parameterized by
//  `CatalystM04Kind`. Body reads `loads.getById` for the LD-E5C9 load.
//  Bottom nav frozen.
//

import SwiftUI

private struct CMLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let trailerType: String?
    let rate: String?
    let distance: Double?
}

enum CatalystM04Kind: String {
    case firstBid, secondQuote, thirdQuote, fourthQuote, awardedCEL, onSiteCEL
}

private struct CMQuote {
    let code: String       // "AUR" / "PFC" / "SCC" / "CEL"
    let name: String       // long name
    let amount: Int        // 1640 / 1625 / 1615 / 1610
    let bidId: String
}

private struct CMConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let chainPill: String
    let quotes: [CMQuote]
    let leadCode: String
    let timeLeft: String
    let lastDelta: String
}

private extension CatalystM04Kind {
    var config: CMConfig {
        switch self {
        case .firstBid:
            return .init(eyebrow: "CATALYST · DISPATCH · BIDDING · FIRST BID",
                         citation: "§360 · CHAIN PORT 2/N · BIDDING · 1/N",
                         title: "Bidding · first quote in · Aurora opens",
                         subhead: "Atlanta GA → Charlotte NC · 53' Dry Van · $1,640 quote · 245 mi · 3h 58m left",
                         pillCopy: "FIRST BID IN · M-04 · CHAIN PORT 2/N · WINDOW 3H 58M · RANK 1/1",
                         chainPill: "AUR-MC942008-M-04-Q-001 · Aurora Freight Lines · §360",
                         quotes: [.init(code: "AUR", name: "Aurora Freight Lines", amount: 1640, bidId: "AUR-MC942008-M-04-Q-001")],
                         leadCode: "AUR",
                         timeLeft: "3h 58m",
                         lastDelta: "vs target $1,650 (-10)")
        case .secondQuote:
            return .init(eyebrow: "CATALYST · DISPATCH · BIDDING · COMPETING QUOTE",
                         citation: "§362 · CHAIN PORT 4/N · BIDDING · 3/N",
                         title: "Bidding · Piedmont undercuts · AUR to 2/2",
                         subhead: "Atlanta GA → Charlotte NC · 53' Dry Van · $1,625 vs $1,640 · 2 quotes · 3h 50m left",
                         pillCopy: "COMPETING QUOTE IN · M-04 · CHAIN PORT 4/N · WINDOW 3H 50M · RANK 1/2",
                         chainPill: "PFC-MC748219-M-04-Q-002 · Piedmont Freight Carriers · §362",
                         quotes: [
                            .init(code: "PFC", name: "Piedmont Freight Carriers", amount: 1625, bidId: "PFC-MC748219-M-04-Q-002"),
                            .init(code: "AUR", name: "Aurora Freight Lines",      amount: 1640, bidId: "AUR-MC942008-M-04-Q-001"),
                         ],
                         leadCode: "PFC",
                         timeLeft: "3h 50m",
                         lastDelta: "vs AUR $1,640 (-15)")
        case .thirdQuote:
            return .init(eyebrow: "CATALYST · DISPATCH · BIDDING · 3RD QUOTE",
                         citation: "§364 · CHAIN PORT 6/N · BIDDING · 5/N",
                         title: "Bidding · SCC undercuts · PFC 2/3 · AUR 3/3",
                         subhead: "53' Dry Van · $1,615 vs $1,625 vs $1,640 · 3 quotes · 3h 37m left",
                         pillCopy: "3 QUOTES · LEAD SCC · M-04 · CHAIN PORT 6/N · WINDOW 3H 37M · RANK 1/3",
                         chainPill: "SCC-MC836472-M-04-Q-003 · Southern Crescent Carriers · §364",
                         quotes: [
                            .init(code: "SCC", name: "Southern Crescent Carriers", amount: 1615, bidId: "SCC-MC836472-M-04-Q-003"),
                            .init(code: "PFC", name: "Piedmont Freight Carriers",  amount: 1625, bidId: "PFC-MC748219-M-04-Q-002"),
                            .init(code: "AUR", name: "Aurora Freight Lines",        amount: 1640, bidId: "AUR-MC942008-M-04-Q-001"),
                         ],
                         leadCode: "SCC",
                         timeLeft: "3h 37m",
                         lastDelta: "vs PFC $1,625 (-10)")
        case .fourthQuote:
            return .init(eyebrow: "CATALYST · DISPATCH · BIDDING · 4TH QUOTE",
                         citation: "§366 · CHAIN PORT 8/N · BIDDING · 7/N",
                         title: "Bidding · CEL undercuts · SCC 2/4 · PFC 3/4 · AUR 4/4",
                         subhead: "53' Dry Van · $1,610 vs $1,615 vs $1,625 vs $1,640 · 4 quotes · 3h 27m left",
                         pillCopy: "4 QUOTES · LEAD CEL · M-04 · CHAIN PORT 8/N · WINDOW 3H 27M · RANK 1/4",
                         chainPill: "CEL-MC712944-M-04-Q-004 · Carolina Express Logistics · §366",
                         quotes: [
                            .init(code: "CEL", name: "Carolina Express Logistics",  amount: 1610, bidId: "CEL-MC712944-M-04-Q-004"),
                            .init(code: "SCC", name: "Southern Crescent Carriers",  amount: 1615, bidId: "SCC-MC836472-M-04-Q-003"),
                            .init(code: "PFC", name: "Piedmont Freight Carriers",   amount: 1625, bidId: "PFC-MC748219-M-04-Q-002"),
                            .init(code: "AUR", name: "Aurora Freight Lines",         amount: 1640, bidId: "AUR-MC942008-M-04-Q-001"),
                         ],
                         leadCode: "CEL",
                         timeLeft: "3h 27m",
                         lastDelta: "vs SCC $1,615 (-5)")
        case .awardedCEL:
            return .init(eyebrow: "CATALYST · DISPATCH · AWARDED · CEL ACK",
                         citation: "§369 · CHAIN PORT 11/N · AWARDED · 2/N · CEL $1,610",
                         title: "Awarded · CEL receives tender · arm pickup",
                         subhead: "53' Dry Van · $1,610 · win +$40 · pickup 21h 35m",
                         pillCopy: "AWARDED · CEL ACK · ARM PICKUP · 23H 59M",
                         chainPill: "AWARDED TO CEL · M-04 · CHAIN PORT 11/N · TENDER 10:24 EDT 5/21 · WIN +$40",
                         quotes: [
                            .init(code: "CEL", name: "Carolina Express Logistics", amount: 1610, bidId: "CEL-MC712944-M-04-Q-004"),
                         ],
                         leadCode: "CEL",
                         timeLeft: "21h 35m",
                         lastDelta: "CEL rank 1/4 · 24h tender window armed")
        case .onSiteCEL:
            return .init(eyebrow: "CATALYST · DISPATCH · PICKUP · ON-SITE",
                         citation: "§387 · CHAIN PORT 12/N · PICKUP · 2/N · CEL ON-SITE",
                         title: "Pickup · CEL driver on-site · dock 4A",
                         subhead: "53' Dry Van · JR on-site · dwell 0:02",
                         pillCopy: "PICKUP · ON-SITE · DOCK 4A · DWELL 0:02",
                         chainPill: "ON-SITE · M-04 · CHAIN PORT 12/N · 08:04 EDT 5/21 · GATE CLEARED · PICK 1/5",
                         quotes: [
                            .init(code: "CEL", name: "Carolina Express Logistics", amount: 1610, bidId: "CEL-MC712944-M-04-Q-004"),
                         ],
                         leadCode: "CEL",
                         timeLeft: "0:02 dwell",
                         lastDelta: "CEL fleet · JR on-site dock 4A · gate cleared")
        }
    }
}

private struct CatalystM04Shell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",          isCurrent: false),
                          NavSlot(label: "Fleet", systemImage: "truck.box.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct CatalystM04BiddingBody: View {
    let loadId: String
    let kind: CatalystM04Kind

    @Environment(\.palette) private var palette
    @State private var load: CMLoadCtx?

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                quoteLadder(c)
                identityRow
                kpiGrid(c)
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private func header(_ c: CMConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CMConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(c.chainPill).font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func quoteLadder(_ c: CMConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("QUOTE LADDER").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                ForEach(Array(c.quotes.enumerated()), id: \.offset) { idx, q in
                    HStack(spacing: 8) {
                        Circle().fill(q.code == c.leadCode ? LinearGradient.diagonal : LinearGradient(colors: [palette.bgPage, palette.bgPage], startPoint: .top, endPoint: .bottom))
                            .frame(width: 22, height: 22)
                            .overlay(Text(q.code).font(.system(size: 8, weight: .heavy)).foregroundStyle(q.code == c.leadCode ? .white : palette.textSecondary))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(q.name).font(.caption2.weight(.semibold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                            Text(q.bidId).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                        }
                        Spacer()
                        Text("$\(q.amount.formatted(.number))").font(.system(size: 14, weight: .heavy).monospacedDigit())
                            .foregroundStyle(q.code == c.leadCode ? Color.green : palette.textPrimary)
                        if q.code == c.leadCode {
                            Text("\(idx + 1)/\(c.quotes.count)").font(.caption2).foregroundStyle(.green)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(palette.bgPage))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(q.code == c.leadCode ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1))
                }
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("DU").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eusorone Technologies · Diego Usoro · catalyst").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("LD-260427-E5C9A41B22 · Atlanta GA → Charlotte NC · 245 mi").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: CMConfig) -> some View {
        let lead = c.quotes.first { $0.code == c.leadCode } ?? c.quotes[0]
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .firstBid:
                return [
                    ("LEAD",   "AUR",                  "Aurora · single quote", .green),
                    ("QUOTE",  "$\(lead.amount)",       "vs target $1,650",     .blue),
                    ("WINDOW", c.timeLeft,               "to close",             .orange),
                    ("RANK",   "1/1",                    "first to quote",       .green),
                ]
            case .secondQuote, .thirdQuote, .fourthQuote:
                return [
                    ("LEAD",   c.leadCode,               lead.name,              .green),
                    ("DELTA",  c.lastDelta,               "spread under lead",    .green),
                    ("QUOTES", "\(c.quotes.count)",       "live carriers",        .blue),
                    ("WINDOW", c.timeLeft,                "to close",             .orange),
                ]
            case .awardedCEL:
                return [
                    ("WINNER", "CEL",                     lead.name,             .green),
                    ("TENDER", "$\(lead.amount)",          "win +$40",           .green),
                    ("PICKUP", c.timeLeft,                  "to gate open",       .blue),
                    ("CHAIN",  "11/N",                       "AWARDED · §369",   .blue),
                ]
            case .onSiteCEL:
                return [
                    ("STATUS",  "ON-SITE",                  "CEL · JR · dock 4A", .green),
                    ("DWELL",   "0:02",                      "since gate",        .green),
                    ("GATE",    "CLEARED",                    "08:04 EDT",       .green),
                    ("PICK",    "1/5",                         "in queue",       .blue),
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
        let copy: String = {
            switch kind {
            case .firstBid:     return "Aurora opens the M-04 board at $1,640. Window holds 3h 58m; expect Piedmont/SCC/CEL to follow."
            case .secondQuote:  return "Piedmont undercuts by $15. AUR drops to 2/2. Watch for SCC follow — ESang flags lane history."
            case .thirdQuote:   return "Southern Crescent takes the lead at $1,615. CEL is queueing — Carolina lane is their flagship corridor."
            case .fourthQuote:  return "Carolina Express undercuts to $1,610. 4 quotes live. Award fires when window closes or DU taps to lock."
            case .awardedCEL:   return "CEL wins the tender at $1,610 (+$40 vs target). 24h pickup window armed; ESang pings -30 min before gate."
            case .onSiteCEL:    return "CEL driver JR on-site at dock 4A. Dwell timer is live; loading-state arms on first pallet movement."
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
}

// MARK: - Screens (CV369-CV374)

struct CatalystM04FirstBidScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystM04Shell(theme: theme) { CatalystM04BiddingBody(loadId: loadId, kind: .firstBid) } }
}
struct CatalystM04SecondQuoteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystM04Shell(theme: theme) { CatalystM04BiddingBody(loadId: loadId, kind: .secondQuote) } }
}
struct CatalystM04ThirdQuoteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystM04Shell(theme: theme) { CatalystM04BiddingBody(loadId: loadId, kind: .thirdQuote) } }
}
struct CatalystM04FourthQuoteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystM04Shell(theme: theme) { CatalystM04BiddingBody(loadId: loadId, kind: .fourthQuote) } }
}
struct CatalystM04AwardedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystM04Shell(theme: theme) { CatalystM04BiddingBody(loadId: loadId, kind: .awardedCEL) } }
}
struct CatalystM04OnSiteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystM04Shell(theme: theme) { CatalystM04BiddingBody(loadId: loadId, kind: .onSiteCEL) } }
}

// MARK: - Previews

#Preview("CV369 First · Dark")    { CatalystM04FirstBidScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV370 2nd · Light")     { CatalystM04SecondQuoteScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV371 3rd · Dark")      { CatalystM04ThirdQuoteScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV372 4th · Light")     { CatalystM04FourthQuoteScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV373 Award · Dark")    { CatalystM04AwardedScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV374 OnSite · Light")  { CatalystM04OnSiteScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
