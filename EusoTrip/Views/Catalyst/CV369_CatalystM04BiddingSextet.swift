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
//  Catalyst-vantage multi-carrier bidding landscape. All 6 stages share
//  `CatalystM04BiddingBody`, parameterized by `CatalystM04Kind` (the
//  stage-only textual chrome — eyebrow / citation / title / pill copy /
//  next-step copy). The QUOTE LADDER and every business value bind to
//  REAL tRPC procs:
//
//    • `loads.getById` ({ id }) → CMLoadCtx
//        Lane (pickupLocation/deliveryLocation {city,state}), miles
//        (distance), equipment (equipmentType), posted rate, parties
//        (shipper/catalyst/driver). Top-level `id` is a STRING on the
//        wire (loads.ts:1340 `id: String(load.id)`) — decoding it as Int
//        throws typeMismatch and fails the WHOLE decode → blank screen.
//        pickup/delivery are NESTED {city,state} objects (loads.ts:1351),
//        NOT flat city fields.
//    • `loads.getBids` ({ id }) → [CMBid]
//        EVERY bid on the load (incl. the winner), price-sorted lead-first
//        (lowest amount, newest as tiebreaker; loads.ts:1479). Each bid:
//        bidId "bid_<n>", real amount, catalyst {name, companyName, code}.
//
//  ZERO fabrication: there are no hardcoded carrier personas (Aurora /
//  Piedmont / Southern Crescent / Carolina Express), no invented bid
//  amounts ($1,640 / $1,625 / $1,615 / $1,610), and no invented party
//  names. The QUOTE LADDER renders the REAL bids; when none exist it
//  paints an honest empty ladder. Any value without a live source renders
//  "-" / "—". Bottom nav frozen.
//
//  Powered by ESANG AI™.
//

import SwiftUI

/// `loads.getById` decode shape (server loads.ts:1338-1379).
/// CONTRACT — these two field shapes are silent-decode-failure traps:
///   • Top-level `id` is a STRING on the wire (`id: String(load.id)`).
///     Decoding it as Int throws typeMismatch and fails the entire
///     decode, leaving `load == nil` and the whole surface blank.
///   • `pickupLocation`/`deliveryLocation` are NESTED {city,state}
///     objects, NOT flat `pickupCity`/`destCity` fields. The server
///     sends "" (empty string), not nil, when a city is missing.
private struct CMLoadCtx: Decodable, Hashable {
    let id: String?
    let loadNumber: String?
    let pickupLocation: CMLoc?
    let deliveryLocation: CMLoc?
    let equipmentType: String?
    let rate: String?
    let distance: Double?
    let driver: CMParty?
    let catalyst: CMParty?
    let shipper: CMParty?
    struct CMLoc: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct CMParty: Decodable, Hashable {
        let id: Int?            // party (user/company) id is numeric on the wire
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }
}

enum CatalystM04Kind: String {
    case firstBid, secondQuote, thirdQuote, fourthQuote, awardedCEL, onSiteCEL
}

/// Stage-only textual chrome. NOTE: this carries NO business data — no
/// quotes, no carrier names, no amounts, no lead code. The QUOTE LADDER
/// and all economics bind to `loads.getBids` / `loads.getById` at render.
/// `timeLeft` / `lastDeltaNote` are stage-semantic labels (the bidding
/// narrative), not server values; they describe the lifecycle stage.
private struct CMConfig {
    let eyebrowStage: String     // "BIDDING · FIRST BID" / "AWARDED · CEL ACK" / …
    let citation: String         // §number stage citation (canonical)
    let titleStage: String       // stage-only title (composed at render)
    let stageNote: String        // appended to load-specific subhead
    let pillCopyStage: String    // stage-only pill copy (composed)
    let timeLeft: String         // stage-semantic bidding-window label
    let lastDeltaNote: String    // stage-semantic delta narrative
}

private extension CatalystM04Kind {
    var config: CMConfig {
        switch self {
        case .firstBid:
            return .init(eyebrowStage: "BIDDING · FIRST BID",
                         citation: "§360 · CHAIN PORT 2/N · BIDDING · 1/N",
                         titleStage: "first quote in",
                         stageNote: "first quote on the floor",
                         pillCopyStage: "FIRST BID IN · CHAIN PORT 2/N",
                         timeLeft: "bidding open",
                         lastDeltaNote: "first on the floor")
        case .secondQuote:
            return .init(eyebrowStage: "BIDDING · COMPETING QUOTE",
                         citation: "§362 · CHAIN PORT 4/N · BIDDING · 3/N",
                         titleStage: "competing quote · lead changes",
                         stageNote: "competing quote in",
                         pillCopyStage: "COMPETING QUOTE IN · CHAIN PORT 4/N",
                         timeLeft: "bidding open",
                         lastDeltaNote: "competing carrier undercuts")
        case .thirdQuote:
            return .init(eyebrowStage: "BIDDING · 3RD QUOTE",
                         citation: "§364 · CHAIN PORT 6/N · BIDDING · 5/N",
                         titleStage: "third quote in · multi-way contest",
                         stageNote: "more quotes on the floor",
                         pillCopyStage: "MULTI-WAY · CHAIN PORT 6/N",
                         timeLeft: "bidding open",
                         lastDeltaNote: "spread tightens")
        case .fourthQuote:
            return .init(eyebrowStage: "BIDDING · 4TH QUOTE",
                         citation: "§366 · CHAIN PORT 8/N · BIDDING · 7/N",
                         titleStage: "fourth quote in · final-call contest",
                         stageNote: "last call on the floor",
                         pillCopyStage: "FINAL CALL · CHAIN PORT 8/N",
                         timeLeft: "final call",
                         lastDeltaNote: "final-call clock running")
        case .awardedCEL:
            return .init(eyebrowStage: "AWARDED · WINNER ACK",
                         citation: "§369 · CHAIN PORT 11/N · AWARDED · 2/N",
                         titleStage: "awarded · winner receives tender",
                         stageNote: "winner armed · pickup window opens",
                         pillCopyStage: "AWARDED · WINNER ACK · ARM PICKUP",
                         timeLeft: "tender armed",
                         lastDeltaNote: "tender window armed")
        case .onSiteCEL:
            return .init(eyebrowStage: "PICKUP · ON-SITE",
                         citation: "§387 · CHAIN PORT 12/N · PICKUP · 2/N",
                         titleStage: "winner on-site · pickup armed",
                         stageNote: "driver on-site · dwell starting",
                         pillCopyStage: "PICKUP · ON-SITE · DWELL STARTING",
                         timeLeft: "dwell starting",
                         lastDeltaNote: "gate cleared · pickup in motion")
        }
    }
}

private struct CatalystM04Shell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: CarrierNavRoute.leading(current: .drivers),
                trailing: CarrierNavRoute.trailing(current: .drivers),
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
    @State private var bids: [CMBid] = []

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
        .task { await refresh() }
        .eusoRefreshable { await refresh() }
    }

    private func refresh() async {
        _ = await (loadCtx(), loadBids())
    }

    // MARK: - Server-sourced quote ladder (loads.getBids · price-sorted lead-first)

    /// One renderable ladder row, mapped from a real `loads.getBids` bid.
    /// `code` is the server-resolved carrier short code; `name` is the
    /// real carrier company name (or user name, or code) — never invented.
    private struct CMLadderRow: Hashable {
        let code: String
        let name: String
        let amount: Int
        let bidId: String
    }

    /// The REAL bids, mapped to ladder rows. Empty when the load has no
    /// bids — the ladder then paints an honest empty state. No fallback
    /// to fabricated quotes.
    private var ladderRows: [CMLadderRow] {
        bids.map { b in
            CMLadderRow(code: b.catalyst.code,
                        name: b.catalyst.companyName ?? b.catalyst.name ?? b.catalyst.code,
                        amount: Int(b.amount.rounded()),
                        bidId: b.bidId)
        }
    }

    /// The lead bid's carrier code (rank 1 = server's price-sorted lead).
    /// nil when there are no bids — nothing is highlighted as the lead.
    private var leadCode: String? {
        ladderRows.first?.code
    }

    // MARK: - Dynamic display helpers (live-bound; honest "-"/"—" fallback)

    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }
    private var laneDisplay: String? {
        // Nested {city,state}; server sends "" (not nil) when missing.
        let o = [load?.pickupLocation?.city, load?.pickupLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        let d = [load?.deliveryLocation?.city, load?.deliveryLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        guard !o.isEmpty || !d.isEmpty else { return nil }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }
    private var equipmentDisplay: String {
        let eq = load?.equipmentType?.trimmingCharacters(in: .whitespaces) ?? ""
        return eq.isEmpty ? "-" : eq
    }
    private var distanceDisplay: String {
        guard let d = load?.distance, d > 0 else { return "-" }
        return "\(Int(d.rounded())) mi"
    }
    /// Posted/lead rate from the load row (decimal string). "-" when absent.
    private var rateDisplay: String {
        guard let r = load?.rate, let n = Double(r), n > 0 else { return "-" }
        let v = n.rounded()
        return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
    }
    /// Lowest live bid amount ("$1,610"), the true lead quote. "-" when no bids.
    private var leadQuoteDisplay: String {
        guard let lead = ladderRows.first else { return "-" }
        return "$\(lead.amount.formatted(.number))"
    }

    private func header(_ c: CMConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DISPATCH · \(c.eyebrowStage) · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            Text("Bidding · \(c.titleStage)")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("\(laneDisplay ?? "-") · \(equipmentDisplay) · \(rateDisplay) posted · \(distanceDisplay) · \(c.timeLeft)")
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
                if ladderRows.isEmpty {
                    quoteLadderEmptyRow
                } else {
                    ForEach(Array(ladderRows.enumerated()), id: \.offset) { idx, q in
                        let isLead = q.code == leadCode
                        HStack(spacing: 8) {
                            Circle().fill(isLead ? LinearGradient.diagonal : LinearGradient(colors: [palette.bgPage, palette.bgPage], startPoint: .top, endPoint: .bottom))
                                .frame(width: 22, height: 22)
                                .overlay(Text(q.code).font(.system(size: 8, weight: .heavy)).foregroundStyle(isLead ? .white : palette.textSecondary))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(q.name).font(.caption2.weight(.semibold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                                Text(q.bidId).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                            }
                            Spacer()
                            Text("$\(q.amount.formatted(.number))").font(.system(size: 14, weight: .heavy).monospacedDigit())
                                .foregroundStyle(isLead ? Color.green : palette.textPrimary)
                            if isLead {
                                Text("\(idx + 1)/\(ladderRows.count)").font(.caption2).foregroundStyle(.green)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(palette.bgPage))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isLead ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1))
                    }
                }
            }
        }
    }

    /// Honest empty ladder — no bids on this load yet. No fabricated quotes.
    private var quoteLadderEmptyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No bids on this load yet")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(palette.bgPage))
    }

    private var identityRow: some View {
        let shipIni = load?.shipper?.initials ?? "-"
        let shipName = load?.shipper?.name ?? "-"
        let shipCompany = load?.shipper?.companyName ?? "-"
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(shipIni).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(shipCompany) · \(shipName) · shipper")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("\(loadNumberDisplay) · \(laneDisplay ?? "-") · \(distanceDisplay)")
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: CMConfig) -> some View {
        let lead = ladderRows.first
        let leadCodeText = lead?.code ?? "-"
        let leadNameText = lead?.name ?? "-"
        let leadAmountText = lead.map { "$\($0.amount.formatted(.number))" } ?? "-"
        // Winner identity: the load's resolved catalyst when set, else the
        // current lead carrier code. "-" when neither is known. No persona.
        let winnerName = load?.catalyst?.companyName ?? load?.catalyst?.name ?? leadCodeText
        let driverIni = load?.driver?.initials ?? "-"
        let bidCount = ladderRows.count
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .firstBid:
                return [
                    ("LEAD",   leadCodeText,             leadNameText,           .green),
                    ("QUOTE",  leadQuoteDisplay,         "lead on the floor",    .blue),
                    ("WINDOW", c.timeLeft,               "bidding window",       .orange),
                    ("BIDS",   "\(bidCount)",            "live carriers",        .green),
                ]
            case .secondQuote, .thirdQuote, .fourthQuote:
                return [
                    ("LEAD",   leadCodeText,             leadNameText,           .green),
                    ("QUOTE",  leadQuoteDisplay,         "lowest on the floor",  .green),
                    ("BIDS",   "\(bidCount)",            "live carriers",        .blue),
                    ("WINDOW", c.timeLeft,               "bidding window",       .orange),
                ]
            case .awardedCEL:
                return [
                    ("WINNER", winnerName,               leadNameText,           .green),
                    ("TENDER", leadAmountText,           "lead tender",          .green),
                    ("PICKUP", c.timeLeft,               "to gate open",         .blue),
                    ("CHAIN",  "11/N",                   "AWARDED · §369",       .blue),
                ]
            case .onSiteCEL:
                return [
                    ("STATUS",  "ON-SITE",               "\(winnerName) · \(driverIni) · dock", .green),
                    ("WINNER",  winnerName,              leadNameText,           .green),
                    ("GATE",    "CLEARED",               "pickup armed",         .green),
                    ("WINDOW",  c.timeLeft,              "dwell",                .blue),
                ]
            }
        }()
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.0).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.1).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.3).lineLimit(1).minimumScaleFactor(0.6)
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
            case .fourthQuote:  return "Fourth quote undercuts. Final-call clock running. Award fires when the window closes or the shipper locks."
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
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* leave nil → honest "-" */ }
    }

    private func loadBids() async {
        struct In: Encodable { let id: String }
        do { bids = try await EusoTripAPI.shared.query("loads.getBids", input: In(id: loadId)) } catch { /* leave [] → honest empty ladder */ }
    }
}

/// Server-sourced bid shape from `loads.getBids` (server loads.ts:1479).
/// Returns ALL bids on the load (incl. the winner), price-sorted
/// lead-first. `id` is numeric on the wire for the catalyst party; `code`
/// is the server-resolved short code. When the array is empty the bidding
/// screen renders an honest empty ladder — never fabricated quotes.
private struct CMBid: Decodable, Hashable {
    let bidId: String
    let rank: Int
    let loadId: String
    let amount: Double
    let currency: String?
    let status: String?
    let notes: String?
    let createdAt: String?
    let expiresAt: String?
    let catalyst: CMBidCatalyst

    struct CMBidCatalyst: Decodable, Hashable {
        let id: Int?
        let name: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
        let code: String
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
