//
//  CV379_CatalystM05BiddingQuartet.swift
//  EusoTrip — Catalyst · M-05 multi-broker bidding quartet (CV379-CV382).
//
//  Pixel-match to:
//    379 Catalyst First Bid M05
//    380 Catalyst Competing Quote M05
//    381 Catalyst Third Quote M05
//    382 Catalyst Awarded M05
//
//  Mirrors the CV369 M04 bidding sextet pattern: enum-driven shared
//  body, four screens differ only in citation copy + KPI tilt.
//
//  Server wiring (no stubs / no fabrication — EVERY visible business
//  value binds to a real tRPC proc, or paints "-"/"—" until it resolves):
//    • `loads.getById` ({ id }) → CVQLoad
//        loadNumber, rate, distance, equipment/cargo, lane (nested
//        pickupLocation/deliveryLocation {city,state}), lifecycle status.
//        CONTRACT: top-level `id` is a STRING on the wire (server emits
//        String(load.id) at loads.ts:1340) — decoding it as Int throws
//        typeMismatch and fails the WHOLE decode → a silently blank
//        surface. pickup/delivery are nested {city,state} objects, NOT
//        flat city fields. Party objects carry a NUMERIC id.
//    • `loads.getBids` ({ id }) → [CVQBid]
//        EVERY bid on the load (server loads.ts:1395), lead-first
//        (lowest amount, then newest). Each row carries the real
//        per-bid `status` (so the winner = the row whose status is
//        "accepted") plus the real carrier party (catalyst.name /
//        companyName). The quote count + winner name + awarded amount
//        all derive from these rows — NO hardcoded persona, NO invented
//        "1/2/3 quotes". Empty list → honest "—" / "no quotes yet".
//
//  Every hardcoded persona (Aurora / Southern Crescent / Piedmont /
//  Carolina Express / Eusotrans / Diego Usoro / Naomi Chen / Michael
//  Eusorone) and every `?? <invented>` fallback is DELETED. Bottom nav
//  frozen.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - tRPC decode shapes

/// `loads.getById` projection (server loads.ts:1338). Top-level `id` is a
/// String on the wire — decoding as Int throws typeMismatch and fails the
/// whole decode. pickup/delivery are nested {city,state} objects (server
/// emits "" — not nil — when a field is missing). Party objects carry a
/// numeric id.
private struct CVQLoad: Decodable, Hashable {
    let id: String?
    let loadNumber: String?
    let status: String?
    let rate: String?
    let distance: Double?
    let cargoType: String?
    let equipmentType: String?
    let hazmatClass: String?
    let pickupLocation: CVQCityState?
    let deliveryLocation: CVQCityState?
    let pickupDate: String?
    let driver: CVQParty?
    let catalyst: CVQParty?
    let shipper: CVQParty?
    struct CVQCityState: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct CVQParty: Decodable, Hashable {
        let id: Int?            // party (user/company) id is numeric on the wire
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }
}

/// One bid row from `loads.getBids` (server loads.ts:1395). Lead-first
/// (lowest amount, then most recent). `status` is the per-bid lifecycle
/// state — "accepted" marks the winning bid. `catalyst` is the resolved
/// carrier party (name / companyName real, or null when unresolved).
private struct CVQBid: Decodable, Hashable, Identifiable {
    let bidId: String           // "bid_<n>"
    let rank: Int?
    let amount: Double?
    let status: String?
    let catalyst: CVQBidParty?
    var id: String { bidId }
    struct CVQBidParty: Decodable, Hashable {
        let id: Int?
        let name: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
        let code: String?
    }
}

enum CatalystM05BiddingKind: String {
    case firstBid, competingQuote, thirdQuote, awarded
}

private struct CVQConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let stagePill: String
    let chainPill: String
}

private extension CatalystM05BiddingKind {
    /// `quotes` is the real bid count; `winner` is the real winning-carrier
    /// name (or "—" when unresolved). No persona / count literals.
    func config(loadNumber: String, quotes: Int, winner: String) -> CVQConfig {
        let qWord = quotes == 1 ? "quote" : "quotes"
        switch self {
        case .firstBid:
            return .init(eyebrow: "CATALYST · DISPATCH · BIDDING · FIRST BID · M-05",
                         citation: "§411 · BIDDING · FIRST BID · 1/4 · POSTED",
                         title: "Bidding · first quote",
                         subhead: "BIDDING · first quote on the floor",
                         stagePill: "\(loadNumber) · BIDDING · first quote · clock running",
                         chainPill: "\(loadNumber) · M-05 BID FLOOR · \(quotes) \(qWord) · competing carriers expected")
        case .competingQuote:
            return .init(eyebrow: "CATALYST · DISPATCH · BIDDING · COMPETING · M-05",
                         citation: "§413 · BIDDING · COMPETING QUOTE · 2/4 · BIDDING",
                         title: "Competing quote",
                         subhead: "BIDDING · another carrier on the board",
                         stagePill: "\(loadNumber) · BIDDING · \(quotes) \(qWord) · shipper choosing",
                         chainPill: "\(loadNumber) · M-05 BID FLOOR · \(quotes) \(qWord) · award pending")
        case .thirdQuote:
            return .init(eyebrow: "CATALYST · DISPATCH · BIDDING · THIRD QUOTE · M-05",
                         citation: "§414 · BIDDING · THIRD QUOTE · 3/4 · BIDDING",
                         title: "Third quote",
                         subhead: "BIDDING · multi-way contest",
                         stagePill: "\(loadNumber) · BIDDING · \(quotes) \(qWord) · last call",
                         chainPill: "\(loadNumber) · M-05 BID FLOOR · \(quotes) \(qWord) · about to award")
        case .awarded:
            return .init(eyebrow: "CATALYST · DISPATCH · AWARDED · M-05",
                         citation: "§415 · AWARDED · 4/4 · ASSIGN DRIVER",
                         title: "Awarded",
                         subhead: "AWARDED · \(winner) wins · assign within window",
                         stagePill: "\(loadNumber) · AWARDED · \(winner) · assign-driver window open",
                         chainPill: "\(loadNumber) · M-05 BID FLOOR · awarded · ledger committed")
        }
    }
}

// MARK: - Shell + Body

private struct CVQShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",                isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.stack.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Fleet",  systemImage: "truck.box.fill",      isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct CVQBody: View {
    let loadId: String
    let kind: CatalystM05BiddingKind

    @Environment(\.palette) private var palette
    @State private var load: CVQLoad?
    @State private var bids: [CVQBid] = []

    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }
    private var rateDisplay: String {
        if let r = load?.rate, let n = Double(r), n > 0 {
            let v = n.rounded()
            return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
        }
        return "-"
    }
    private var laneDisplay: String? {
        let p = [load?.pickupLocation?.city, load?.pickupLocation?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let d = [load?.deliveryLocation?.city, load?.deliveryLocation?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if p.isEmpty && d.isEmpty { return nil }
        return "\(p.isEmpty ? "-" : p) → \(d.isEmpty ? "-" : d)"
    }
    private var distanceDisplay: String {
        guard let d = load?.distance, d > 0 else { return "-" }
        return "\(Int(d.rounded())) mi"
    }
    private var equipmentDisplay: String {
        let parts = [load?.equipmentType, load?.cargoType].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "-" : parts.joined(separator: " · ")
    }

    // MARK: Bid-derived (loads.getBids) — real quote count + winner, no literals

    /// The real number of quotes on the floor (every bid row). 0 when no
    /// bids resolve.
    private var quoteCount: Int { bids.count }

    /// "1" / "2" / "3" … as a string, or "-" when no quotes have landed.
    private var quoteCountDisplay: String { quoteCount > 0 ? "\(quoteCount)" : "-" }

    /// The winning bid — the row whose per-bid status is "accepted".
    private var winningBid: CVQBid? {
        bids.first { ($0.status ?? "").lowercased() == "accepted" }
    }

    /// Real winning-carrier name — company name preferred, then user name.
    /// "—" when there is no accepted bid or the party didn't resolve.
    private var winnerNameDisplay: String {
        guard let w = winningBid?.catalyst else { return "—" }
        if let c = w.companyName?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        if let n = w.name?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        return "—"
    }

    /// The awarded amount from the accepted bid — "-" when none / non-positive.
    private var awardedAmountDisplay: String {
        guard let a = winningBid?.amount, a > 0 else { return "-" }
        return a < 1000 ? String(format: "$%.0f", a) : "$\(Int(a.rounded()).formatted(.number))"
    }

    var body: some View {
        let c = kind.config(loadNumber: loadNumberDisplay, quotes: quoteCount, winner: winnerNameDisplay)
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                chainPill(c)
                kpiGrid
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private func header(_ c: CVQConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow)
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            Text(c.title)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(c.subhead)
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CVQConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(c.stagePill)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let lane = laneDisplay {
                    Text("\(lane) · \(distanceDisplay) · \(equipmentDisplay)")
                        .font(.caption2).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func chainPill(_ c: CVQConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("BID FLOOR STATE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(c.chainPill)
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(label: String, value: String, sub: String, tint: Color)] = {
            switch kind {
            case .firstBid:
                return [
                    ("STAGE",   "BIDDING",          "first quote in",       .blue),
                    ("RATE",    rateDisplay,        "posted",               .green),
                    ("DIST",    distanceDisplay,    "lane",                 .blue),
                    ("QUOTES",  quoteCountDisplay,  "on the floor",         .blue),
                ]
            case .competingQuote:
                return [
                    ("STAGE",   "BIDDING",          "competing quote",      .blue),
                    ("RATE",    rateDisplay,        "posted",               .green),
                    ("DIST",    distanceDisplay,    "lane",                 .blue),
                    ("QUOTES",  quoteCountDisplay,  "on the floor",         .blue),
                ]
            case .thirdQuote:
                return [
                    ("STAGE",   "BIDDING",          "third quote",          .blue),
                    ("RATE",    rateDisplay,        "posted",               .green),
                    ("DIST",    distanceDisplay,    "lane",                 .blue),
                    ("QUOTES",  quoteCountDisplay,  "on the floor",         .blue),
                ]
            case .awarded:
                return [
                    ("STAGE",   "AWARDED",          "carrier wins",         .green),
                    ("RATE",    awardedAmountDisplay != "-" ? awardedAmountDisplay : rateDisplay, "awarded", .green),
                    ("DIST",    distanceDisplay,    "lane",                 .blue),
                    ("STATE",   (load?.status ?? "-").uppercased(), "load row", .green),
                ]
            }
        }()
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(k.value)
                        .font(.system(size: 16, weight: .heavy).monospacedDigit())
                        .foregroundStyle(k.tint).lineLimit(1)
                    Text(k.sub)
                        .font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.tint.opacity(0.3)))
            }
        }
    }

    private var nextStepCard: some View {
        let copy: String = {
            switch kind {
            case .firstBid:       return "First quote in. Lane is open. Competing carriers have minutes to counter."
            case .competingQuote: return "Another quote lands. Shipper now weighs the offers; the cheaper or faster wins."
            case .thirdQuote:     return "Another quote on the board. Final-call clock running before the shipper awards."
            case .awarded:
                let w = winnerNameDisplay
                return w == "—"
                    ? "Awarded. Ledger committed; assign a driver from the dispatcher board next."
                    : "\(w) awarded. Ledger committed; assign a driver from the dispatcher board next."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(copy)
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        let api = EusoTripAPI.shared
        // load.getById is the spine; bids enrich the quote-count / winner.
        // A failure on either degrades to the honest "-"/"—" empty case;
        // neither blanks the other.
        do {
            load = try await api.query("loads.getById", input: In(id: loadId))
        } catch { /* tolerated — every value renders "-"/"—" */ }
        do {
            bids = try await api.query("loads.getBids", input: In(id: loadId))
        } catch { /* tolerated — quote count / winner render "-"/"—" */ }
    }
}

// MARK: - Screens (CV379-CV382)

struct CatalystM05FirstBidScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CVQShell(theme: theme) { CVQBody(loadId: loadId, kind: .firstBid) } }
}
struct CatalystM05CompetingQuoteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CVQShell(theme: theme) { CVQBody(loadId: loadId, kind: .competingQuote) } }
}
struct CatalystM05ThirdQuoteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CVQShell(theme: theme) { CVQBody(loadId: loadId, kind: .thirdQuote) } }
}
struct CatalystM05AwardedAuroraScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CVQShell(theme: theme) { CVQBody(loadId: loadId, kind: .awarded) } }
}

// MARK: - Previews

#Preview("379 First Bid · Light")        { CatalystM05FirstBidScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("380 Competing · Dark")         { CatalystM05CompetingQuoteScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("381 Third Quote · Light")      { CatalystM05ThirdQuoteScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("382 Awarded · Dark")           { CatalystM05AwardedAuroraScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
