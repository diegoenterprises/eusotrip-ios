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
    let equipmentType: String?
    let rate: String?
    let distance: Double?
    let driver: CMParty?
    let catalyst: CMParty?
    let shipper: CMParty?
    struct CMParty: Decodable, Hashable {
        let id: Int?
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
    }
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
    let eyebrowStage: String     // "BIDDING · FIRST BID" / "AWARDED · CEL ACK" / …
    let citation: String         // §number stage citation (canonical)
    let titleStage: String       // stage-only title (composed at render)
    let stageNote: String        // appended to load-specific subhead
    let pillCopyStage: String    // stage-only pill copy (composed)
    let timeLeft: String         // illustration; bidding window
    let lastDeltaNote: String    // illustration; delta semantic
    let quotes: [CMQuote]        // TODO: replace with loads.getBids when shipped
    let leadCode: String         // illustration; lead carrier code
}

private extension CatalystM04Kind {
    var config: CMConfig {
        // NOTE: the quotes / leadCode / time fields below are
        // illustration data (multi-carrier bidding landscape) that
        // would be sourced from `loads.getBids` once the endpoint
        // lands. Until then, the textual stage labels (eyebrowStage,
        // citation, titleStage, stageNote, pillCopyStage) are dynamic
        // and the body composes them with `load.loadNumber`,
        // `load.pickupCity`, `load.destCity`, `load.equipmentType`,
        // `load.rate`, `load.distance` at render time.
        switch self {
        case .firstBid:
            return .init(eyebrowStage: "BIDDING · FIRST BID",
                         citation: "§360 · CHAIN PORT 2/N · BIDDING · 1/N",
                         titleStage: "first quote in",
                         stageNote: "first quote on the floor",
                         pillCopyStage: "FIRST BID IN · CHAIN PORT 2/N · RANK 1/1",
                         timeLeft: "3h 58m",
                         lastDeltaNote: "first on the floor",
                         quotes: [.init(code: "AUR", name: "Aurora Freight Lines", amount: 1640, bidId: "AUR-Q-001")],
                         leadCode: "AUR")
        case .secondQuote:
            return .init(eyebrowStage: "BIDDING · COMPETING QUOTE",
                         citation: "§362 · CHAIN PORT 4/N · BIDDING · 3/N",
                         titleStage: "competing quote · lead changes",
                         stageNote: "competing quote in · 2 carriers on board",
                         pillCopyStage: "COMPETING QUOTE IN · CHAIN PORT 4/N · RANK 1/2",
                         timeLeft: "3h 50m",
                         lastDeltaNote: "second carrier undercuts",
                         quotes: [
                            .init(code: "PFC", name: "Piedmont Freight Carriers", amount: 1625, bidId: "PFC-Q-002"),
                            .init(code: "AUR", name: "Aurora Freight Lines",      amount: 1640, bidId: "AUR-Q-001"),
                         ],
                         leadCode: "PFC")
        case .thirdQuote:
            return .init(eyebrowStage: "BIDDING · 3RD QUOTE",
                         citation: "§364 · CHAIN PORT 6/N · BIDDING · 5/N",
                         titleStage: "third quote in · three-way contest",
                         stageNote: "3 quotes on the floor",
                         pillCopyStage: "3 QUOTES · CHAIN PORT 6/N · RANK 1/3",
                         timeLeft: "3h 37m",
                         lastDeltaNote: "third carrier undercuts the lead",
                         quotes: [
                            .init(code: "SCC", name: "Southern Crescent Carriers", amount: 1615, bidId: "SCC-Q-003"),
                            .init(code: "PFC", name: "Piedmont Freight Carriers",  amount: 1625, bidId: "PFC-Q-002"),
                            .init(code: "AUR", name: "Aurora Freight Lines",        amount: 1640, bidId: "AUR-Q-001"),
                         ],
                         leadCode: "SCC")
        case .fourthQuote:
            return .init(eyebrowStage: "BIDDING · 4TH QUOTE",
                         citation: "§366 · CHAIN PORT 8/N · BIDDING · 7/N",
                         titleStage: "fourth quote in · final-call contest",
                         stageNote: "4 quotes on the floor · last call",
                         pillCopyStage: "4 QUOTES · CHAIN PORT 8/N · RANK 1/4",
                         timeLeft: "3h 27m",
                         lastDeltaNote: "fourth carrier seizes the lead",
                         quotes: [
                            .init(code: "CEL", name: "Carolina Express Logistics", amount: 1610, bidId: "CEL-Q-004"),
                            .init(code: "SCC", name: "Southern Crescent Carriers", amount: 1615, bidId: "SCC-Q-003"),
                            .init(code: "PFC", name: "Piedmont Freight Carriers",  amount: 1625, bidId: "PFC-Q-002"),
                            .init(code: "AUR", name: "Aurora Freight Lines",        amount: 1640, bidId: "AUR-Q-001"),
                         ],
                         leadCode: "CEL")
        case .awardedCEL:
            return .init(eyebrowStage: "AWARDED · WINNER ACK",
                         citation: "§369 · CHAIN PORT 11/N · AWARDED · 2/N",
                         titleStage: "awarded · winner receives tender",
                         stageNote: "winner armed · pickup window opens",
                         pillCopyStage: "AWARDED · WINNER ACK · ARM PICKUP",
                         timeLeft: "21h 35m",
                         lastDeltaNote: "tender window armed",
                         quotes: [
                            .init(code: "CEL", name: "Carolina Express Logistics", amount: 1610, bidId: "CEL-Q-004"),
                         ],
                         leadCode: "CEL")
        case .onSiteCEL:
            return .init(eyebrowStage: "PICKUP · ON-SITE",
                         citation: "§387 · CHAIN PORT 12/N · PICKUP · 2/N",
                         titleStage: "winner on-site · pickup armed",
                         stageNote: "driver on-site · dwell starting",
                         pillCopyStage: "PICKUP · ON-SITE · DWELL STARTING",
                         timeLeft: "0:02 dwell",
                         lastDeltaNote: "gate cleared · pickup in motion",
                         quotes: [
                            .init(code: "CEL", name: "Carolina Express Logistics", amount: 1610, bidId: "CEL-Q-004"),
                         ],
                         leadCode: "CEL")
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

    // MARK: - Dynamic display helpers

    private var loadNumberDisplay: String { load?.loadNumber ?? "—" }
    private var laneDisplay: String? {
        guard let p = load?.pickupCity, let d = load?.destCity else { return nil }
        return "\(p) → \(d)"
    }
    private var equipmentDisplay: String { load?.equipmentType ?? load?.trailerType ?? "—" }
    private var distanceDisplay: String {
        guard let d = load?.distance, d > 0 else { return "—" }
        return "\(Int(d.rounded())) mi"
    }
    private var rateDisplay: String {
        guard let r = load?.rate, let n = Double(r), n > 0 else { return "—" }
        let v = n.rounded()
        return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
    }
    private var carrierCodeDisplay: String {
        load?.catalyst?.companyName ?? load?.catalyst?.name ?? "—"
    }

    private func header(_ c: CMConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DISPATCH · \(c.eyebrowStage) · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            Text("Bidding · \(c.titleStage)")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("\(laneDisplay ?? "—") · \(equipmentDisplay) · \(rateDisplay) lead · \(distanceDisplay) · \(c.timeLeft) left")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func citationPill(_ c: CMConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("\(c.pillCopyStage) · \(loadNumberDisplay)")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(loadNumberDisplay) · \(c.stageNote) · \(c.lastDeltaNote)")
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        let shipIni = load?.shipper?.initials ?? "—"
        let shipName = load?.shipper?.name ?? "—"
        let shipCompany = load?.shipper?.companyName ?? "—"
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(shipIni).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(shipCompany) · \(shipName) · shipper")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("\(loadNumberDisplay) · \(laneDisplay ?? "—") · \(distanceDisplay)")
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: CMConfig) -> some View {
        let lead = c.quotes.first { $0.code == c.leadCode } ?? c.quotes[0]
        let winnerCode = load?.catalyst?.name ?? lead.code
        let driverIni = load?.driver?.initials ?? "—"
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .firstBid:
                return [
                    ("LEAD",   lead.code,                lead.name,              .green),
                    ("QUOTE",  "$\(lead.amount)",        "first on the floor",   .blue),
                    ("WINDOW", c.timeLeft,               "to close",             .orange),
                    ("RANK",   "1/1",                    "first to quote",       .green),
                ]
            case .secondQuote, .thirdQuote, .fourthQuote:
                return [
                    ("LEAD",   c.leadCode,               lead.name,              .green),
                    ("DELTA",  c.lastDeltaNote,          "spread under lead",    .green),
                    ("QUOTES", "\(c.quotes.count)",      "live carriers",        .blue),
                    ("WINDOW", c.timeLeft,               "to close",             .orange),
                ]
            case .awardedCEL:
                return [
                    ("WINNER", winnerCode,               lead.name,              .green),
                    ("TENDER", "$\(lead.amount)",        "tender accepted",      .green),
                    ("PICKUP", c.timeLeft,               "to gate open",         .blue),
                    ("CHAIN",  "11/N",                   "AWARDED · §369",       .blue),
                ]
            case .onSiteCEL:
                return [
                    ("STATUS",  "ON-SITE",               "\(winnerCode) · \(driverIni) · dock", .green),
                    ("DWELL",   "0:02",                  "since gate",           .green),
                    ("GATE",    "CLEARED",               "pickup armed",         .green),
                    ("PICK",    "1/5",                   "in queue",             .blue),
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
            case .firstBid:     return "First quote on the floor. Bidding window open; competing carriers have time to undercut."
            case .secondQuote:  return "Competing quote in. Lead changes; ESang flags lane history for both carriers."
            case .thirdQuote:   return "Third quote lands. Spread tightens; next quote either seals the lead or opens another contest."
            case .fourthQuote:  return "Fourth quote undercuts. Final-call clock running. Award fires when window closes or the shipper locks."
            case .awardedCEL:   return "Tender accepted by the winner. Pickup window armed; ESang pings −30 min before gate."
            case .onSiteCEL:    return "Driver on-site at pickup. Dwell timer is live; loading-state arms on first pallet movement."
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
