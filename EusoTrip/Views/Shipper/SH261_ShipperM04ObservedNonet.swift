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

private struct SMQuote {
    let code: String, name: String
    let amount: Int, bidId: String
}

private struct SMConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let chainPill: String
    let quotes: [SMQuote]
    let lead: String?
    let target: Int        // $1,650 target
    let timeLeft: String?
}

private extension ShipperM04Kind {
    var config: SMConfig {
        switch self {
        case .freshPosted:
            return .init(eyebrow: "POSTED · FRESH CHAIN",
                         citation: "§359 · CHAIN PORT 1/N · POSTED · BIDS OPEN",
                         title: "Posted · fresh MATRIX load · bids open",
                         subhead: "§359 · POSTED · BIDS OPEN",
                         pillCopy: "FRESH MATRIX-50 ROW M-04 · CHAIN PORT 1/N · BIDS WINDOW OPEN · 4H 00M",
                         chainPill: "LD-260427-E5C9A41B22 · Atlanta GA → Charlotte NC · 245 mi · 53' Dry Van · 38,000 lb · target $1,650",
                         quotes: [],
                         lead: nil, target: 1650, timeLeft: "4h 00m")
        case .firstQuote:
            return .init(eyebrow: "BIDDING · FIRST QUOTE",
                         citation: "§361 · CHAIN PORT 3/N · BIDDING · 1/1 QUOTE IN",
                         title: "First quote in · Aurora · $1,640",
                         subhead: "§361 · BIDDING · 1/1 QUOTE IN · 3H 57M",
                         pillCopy: "FIRST QUOTE · AURORA · MC-942 008 · CHAIN PORT 3/N · QUARTET 2/N",
                         chainPill: "AUR-MC942008-M-04-Q-001 · $1,640 · vs target $1,650 · spread −$10 · $6.69/mi",
                         quotes: [.init(code: "AUR", name: "Aurora Freight Lines", amount: 1640, bidId: "AUR-MC942008-M-04-Q-001")],
                         lead: "AUR", target: 1650, timeLeft: "3h 57m")
        case .secondQuote:
            return .init(eyebrow: "BIDDING · COMPETING",
                         citation: "§363 · CHAIN PORT 5/N · BIDDING · 4/N · 2 QUOTES IN",
                         title: "Piedmont leads · $1,625 · −$15 under Aurora",
                         subhead: "§363 · 2 QUOTES · LEAD PFC · 3H 46M",
                         pillCopy: "BIDDING · 2 QUOTES · LEAD PFC · 3H 46M · spread $15",
                         chainPill: "PFC-MC748219-M-04-Q-002 · $1,625 · vs target $1,650 · spread −$25",
                         quotes: [
                            .init(code: "PFC", name: "Piedmont Freight Carriers", amount: 1625, bidId: "PFC-MC748219-M-04-Q-002"),
                            .init(code: "AUR", name: "Aurora Freight Lines",      amount: 1640, bidId: "AUR-MC942008-M-04-Q-001"),
                         ],
                         lead: "PFC", target: 1650, timeLeft: "3h 46m")
        case .thirdQuote:
            return .init(eyebrow: "BIDDING · 3-QUOTE OBSERVED",
                         citation: "§365 · CHAIN PORT 7/N · BIDDING · 6/N · 3 QUOTES IN",
                         title: "SCC takes the lead · $1,615 · −$35 vs target",
                         subhead: "§365 · 3 QUOTES · LEAD SCC · 3H 33M",
                         pillCopy: "BIDDING · 3 QUOTES · LEAD SCC · 3H 33M · spread $25",
                         chainPill: "SCC-MC836472-M-04-Q-003 · $1,615 · vs target $1,650 · spread −$35",
                         quotes: [
                            .init(code: "SCC", name: "Southern Crescent Carriers", amount: 1615, bidId: "SCC-MC836472-M-04-Q-003"),
                            .init(code: "PFC", name: "Piedmont Freight Carriers",  amount: 1625, bidId: "PFC-MC748219-M-04-Q-002"),
                            .init(code: "AUR", name: "Aurora Freight Lines",        amount: 1640, bidId: "AUR-MC942008-M-04-Q-001"),
                         ],
                         lead: "SCC", target: 1650, timeLeft: "3h 33m")
        case .fourthQuote:
            return .init(eyebrow: "BIDDING · 4-QUOTE OBSERVED",
                         citation: "§367 · CHAIN PORT 9/N · BIDDING · 8/N · 4 QUOTES IN",
                         title: "CEL takes the lead · $1,610 · −$40 vs target",
                         subhead: "§367 · 4 QUOTES · LEAD CEL · 3H 23M",
                         pillCopy: "BIDDING · 4 QUOTES · LEAD CEL · 3H 23M · spread $30",
                         chainPill: "CEL-MC712944-M-04-Q-004 · $1,610 · vs target $1,650 · spread −$40",
                         quotes: [
                            .init(code: "CEL", name: "Carolina Express Logistics",  amount: 1610, bidId: "CEL-MC712944-M-04-Q-004"),
                            .init(code: "SCC", name: "Southern Crescent Carriers",  amount: 1615, bidId: "SCC-MC836472-M-04-Q-003"),
                            .init(code: "PFC", name: "Piedmont Freight Carriers",   amount: 1625, bidId: "PFC-MC748219-M-04-Q-002"),
                            .init(code: "AUR", name: "Aurora Freight Lines",         amount: 1640, bidId: "AUR-MC942008-M-04-Q-001"),
                         ],
                         lead: "CEL", target: 1650, timeLeft: "3h 23m")
        case .awarded:
            return .init(eyebrow: "AWARDED · CEL WON",
                         citation: "§368 · CHAIN PORT 10/N · AWARDED · 1/N · QUARTET 1/N",
                         title: "Awarded to CEL · $1,610 · saved $40",
                         subhead: "§368 · CEL $1,610 · TENDER ACCEPT 24H",
                         pillCopy: "AWARD COMMITTED · CEL $1,610 · −$40 vs TARGET · CHAIN PORT 10/N · QUARTET 1/N AWARDED",
                         chainPill: "CEL-MC712944-M-04-Q-004 · saved $40 vs target $1,650 · pickup 21h 36m",
                         quotes: [.init(code: "CEL", name: "Carolina Express Logistics", amount: 1610, bidId: "CEL-MC712944-M-04-Q-004")],
                         lead: "CEL", target: 1650, timeLeft: "21h 36m")
        case .onSite:
            return .init(eyebrow: "PICKUP · ON-SITE ECHO",
                         citation: "§389 · CHAIN PORT 14/N · PICKUP · 4/N · ON-SITE",
                         title: "Driver on-site · dock 4A",
                         subhead: "§389 · CEL · on-site 0:06 ago",
                         pillCopy: "PICKUP · ON-SITE · DOCK 4A · CEL driver JR · delivery by 16:00 EDT",
                         chainPill: "CEL-MC712944-M-04-Q-004 · JR on-site dock 4A · 245 mi to LA",
                         quotes: [.init(code: "CEL", name: "Carolina Express Logistics", amount: 1610, bidId: "CEL-MC712944-M-04-Q-004")],
                         lead: "CEL", target: 1650, timeLeft: nil)
        case .inTransit:
            return .init(eyebrow: "IN-TRANSIT · ECHO",
                         citation: "§397 · CHAIN PORT 15/N · IN-TRANSIT · 4/4 · ROLLING",
                         title: "In transit · ETA 12:43",
                         subhead: "§397 · CEL · 80/245 mi · delivery by 16:00",
                         pillCopy: "IN-TRANSIT · ROLLING · I-85 SE · CEL JR · 80/245 mi · 33% complete",
                         chainPill: "CEL-MC712944-M-04-Q-004 · ETA 12:43 EDT · delivery by 16:00",
                         quotes: [.init(code: "CEL", name: "Carolina Express Logistics", amount: 1610, bidId: "CEL-MC712944-M-04-Q-004")],
                         lead: "CEL", target: 1650, timeLeft: nil)
        case .atDelivery:
            return .init(eyebrow: "AT-DELIVERY · ECHO",
                         citation: "§401 · CHAIN PORT 16/N · DELIVERY · 4/4 · ARRIVED · QUARTET 4/4 CLOSES",
                         title: "At delivery · POD pending",
                         subhead: "§401 · CEL · arrived 12:43 · appt 14:00",
                         pillCopy: "AT-DELIVERY · CEL DRIVER ON-SITE CLT NEWELL · CHAIN PORT 16/N · QUARTET 4/4 CLOSES",
                         chainPill: "CEL-MC712944-M-04-Q-004 · arrived 12:43 EDT · 245/245 mi · 100% · appt 14:00 · POD PENDING",
                         quotes: [.init(code: "CEL", name: "Carolina Express Logistics", amount: 1610, bidId: "CEL-MC712944-M-04-Q-004")],
                         lead: "CEL", target: 1650, timeLeft: nil)
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

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                if !c.quotes.isEmpty { quoteLadder(c) }
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

    // MARK: - Dynamic display helpers

    private var loadNumberDisplay: String { load?.loadNumber ?? "—" }
    private var laneDisplay: String? {
        guard let p = load?.pickupCity, let d = load?.destCity else { return nil }
        return "\(p) → \(d)"
    }

    private func header(_ c: SMConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · LOADS · \(c.eyebrow) · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: SMConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(c.chainPill).font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func quoteLadder(_ c: SMConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("OBSERVED QUOTES").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                ForEach(Array(c.quotes.enumerated()), id: \.offset) { _, q in
                    HStack(spacing: 8) {
                        Circle().fill(q.code == c.lead ? LinearGradient.diagonal : LinearGradient(colors: [palette.bgPage, palette.bgPage], startPoint: .top, endPoint: .bottom))
                            .frame(width: 22, height: 22)
                            .overlay(Text(q.code).font(.system(size: 8, weight: .heavy)).foregroundStyle(q.code == c.lead ? .white : palette.textSecondary))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(q.name).font(.caption2.weight(.semibold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                            Text(q.bidId).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("$\(q.amount.formatted(.number))").font(.system(size: 14, weight: .heavy).monospacedDigit())
                                .foregroundStyle(q.code == c.lead ? Color.green : palette.textPrimary)
                            Text("\(q.amount - c.target >= 0 ? "+" : "")\(q.amount - c.target) vs target").font(.caption2).foregroundStyle(palette.textTertiary)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(palette.bgPage))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(q.code == c.lead ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1))
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
                    Text("Eusorone Technologies · Diego Usoro · shipper").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("LD-260427-E5C9A41B22 · Atlanta GA → Charlotte NC · 245 mi · target $1,650").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: SMConfig) -> some View {
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .freshPosted:
                return [
                    ("STATE",   "POSTED",                   "bids window open",        .green),
                    ("TARGET",  "$\(c.target)",              "shipper target",         .blue),
                    ("WINDOW",  c.timeLeft ?? "—",            "to close",              .orange),
                    ("DIST",    "245 mi",                     "ATL → CLT · Dry Van",   .blue),
                ]
            case .firstQuote, .secondQuote, .thirdQuote, .fourthQuote:
                let bestAmount = c.quotes.first { $0.code == c.lead }?.amount ?? c.target
                let savings = c.target - bestAmount
                return [
                    ("LEAD",    c.lead ?? "—",                  c.quotes.first { $0.code == c.lead }?.name ?? "—", .green),
                    ("BEST",    "$\(bestAmount)",                 savings > 0 ? "−$\(savings) vs target" : "above target", .green),
                    ("QUOTES",  "\(c.quotes.count)",                "live carriers",  .blue),
                    ("WINDOW",  c.timeLeft ?? "—",                    "to close",     .orange),
                ]
            case .awarded:
                return [
                    ("WINNER",  "CEL",                              "$1,610 · saved $40", .green),
                    ("PICKUP",  c.timeLeft ?? "21h 36m",              "to gate open",     .blue),
                    ("STATE",   "AWARDED",                              "tender accept 24h", .green),
                    ("QUARTET", "1/N",                                    "§368 AWARDED",  .green),
                ]
            case .onSite:
                return [
                    ("STATE",   "ON-SITE",                                  "CEL JR · dock 4A", .green),
                    ("DELIVERY","16:00",                                       "EDT · receiver", .blue),
                    ("DIST",    "245 mi",                                       "to LA",         .blue),
                    ("CHAIN",   "14/N",                                            "§389 PICKUP", .green),
                ]
            case .inTransit:
                return [
                    ("ETA",     "12:43",                                            "EDT · rolling", .blue),
                    ("DIST",    "80/245",                                            "33% complete",  .blue),
                    ("STATE",   "ROLLING",                                            "I-85 SE",      .green),
                    ("CHAIN",   "15/N",                                                "§397 TRANSIT", .green),
                ]
            case .atDelivery:
                return [
                    ("APPT",    "14:00",                                                  "EDT · receiver", .blue),
                    ("ARRIVED", "12:43",                                                    "EDT · CLT Newell", .green),
                    ("DIST",    "245/245",                                                    "100% complete", .green),
                    ("POD",     "PENDING",                                                      "quartet 4/4 closes", .orange),
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
            case .freshPosted:  return "Fresh MATRIX-50 row posted. Bidding window holds 4h; carriers tender in chain-port order."
            case .firstQuote:   return "Aurora opens at $1,640. ESang flags this as in-band but watch for under-cuts in the next 30 min."
            case .secondQuote:  return "Piedmont takes the lead at $1,625. Spread widens to $15; SCC + CEL likely to follow."
            case .thirdQuote:   return "Southern Crescent leads at $1,615. Spread $25. CEL still has 3h 33m to enter."
            case .fourthQuote:  return "Carolina Express takes the floor at $1,610. Award fires when window closes or you tap to lock."
            case .awarded:      return "CEL wins at $1,610, saving $40 vs target. Tender accept holds for 24h; pickup arms in 21h 36m."
            case .onSite:       return "CEL driver JR on-site at dock 4A. Loading state arms on first pallet movement; ETA holds 12:43."
            case .inTransit:    return "CEL rolling I-85 SE at 33% leg. ESang nudges you if ETA drifts >10 min vs 12:43 target."
            case .atDelivery:   return "CEL arrived CLT Newell at 12:43, 17 min before appt. POD pending; quartet 4/4 closes on co-sign."
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
