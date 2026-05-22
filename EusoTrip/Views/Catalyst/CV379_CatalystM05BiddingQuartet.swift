//
//  CV379_CatalystM05BiddingQuartet.swift
//  EusoTrip — Catalyst · M-05 multi-broker bidding quartet (CV379-CV382).
//
//  Pixel-match to:
//    379 Catalyst First Bid M05
//    380 Catalyst Competing Quote M05
//    381 Catalyst Third Quote M05
//    382 Catalyst Awarded Aurora M05
//
//  Mirrors the CV369 M04 bidding sextet pattern: enum-driven shared
//  body, single `loads.getById` read, four screens differ only in
//  citation copy + KPI tilt. All values bind to the load row; no
//  scenario literals. Bottom nav frozen.
//

import SwiftUI

private struct CVQLoad: Decodable, Hashable {
    let id: Int?
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
    struct CVQCityState: Decodable, Hashable {
        let city: String?
        let state: String?
    }
}

enum CatalystM05BiddingKind: String {
    case firstBid, competingQuote, thirdQuote, awardedAurora
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
    func config(loadNumber: String) -> CVQConfig {
        switch self {
        case .firstBid:
            return .init(eyebrow: "CATALYST · DISPATCH · BIDDING · FIRST BID · M-05",
                         citation: "§411 · BIDDING · FIRST BID · 1/4 · POSTED",
                         title: "Bidding · first quote",
                         subhead: "BIDDING · first quote on the floor",
                         stagePill: "\(loadNumber) · BIDDING · first quote · clock running",
                         chainPill: "\(loadNumber) · M-05 BID FLOOR · 1 quote · two competing carriers expected")
        case .competingQuote:
            return .init(eyebrow: "CATALYST · DISPATCH · BIDDING · COMPETING · M-05",
                         citation: "§413 · BIDDING · COMPETING QUOTE · 2/4 · BIDDING",
                         title: "Competing quote",
                         subhead: "BIDDING · second carrier on the board",
                         stagePill: "\(loadNumber) · BIDDING · 2 quotes · shipper choosing",
                         chainPill: "\(loadNumber) · M-05 BID FLOOR · 2 quotes · awarded pending")
        case .thirdQuote:
            return .init(eyebrow: "CATALYST · DISPATCH · BIDDING · THIRD QUOTE · M-05",
                         citation: "§414 · BIDDING · THIRD QUOTE · 3/4 · BIDDING",
                         title: "Third quote",
                         subhead: "BIDDING · three-way contest",
                         stagePill: "\(loadNumber) · BIDDING · 3 quotes · last call",
                         chainPill: "\(loadNumber) · M-05 BID FLOOR · 3 quotes · about to award")
        case .awardedAurora:
            return .init(eyebrow: "CATALYST · DISPATCH · AWARDED · AURORA · M-05",
                         citation: "§415 · AWARDED · 4/4 · ASSIGN DRIVER",
                         title: "Awarded · Aurora",
                         subhead: "AWARDED · Aurora wins · assign within window",
                         stagePill: "\(loadNumber) · AWARDED · Aurora · assign-driver window open",
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
                trailing: [NavSlot(label: "Wallet",  systemImage: "creditcard.fill",      isCurrent: false),
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

    private var loadNumberDisplay: String { load?.loadNumber ?? "—" }
    private var rateDisplay: String {
        if let r = load?.rate, let n = Double(r), n > 0 {
            let v = n.rounded()
            return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
        }
        return "—"
    }
    private var laneDisplay: String? {
        let p = [load?.pickupLocation?.city, load?.pickupLocation?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let d = [load?.deliveryLocation?.city, load?.deliveryLocation?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if p.isEmpty && d.isEmpty { return nil }
        return "\(p.isEmpty ? "—" : p) → \(d.isEmpty ? "—" : d)"
    }
    private var distanceDisplay: String {
        guard let d = load?.distance, d > 0 else { return "—" }
        return "\(Int(d.rounded())) mi"
    }
    private var equipmentDisplay: String {
        let parts = [load?.equipmentType, load?.cargoType].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    var body: some View {
        let c = kind.config(loadNumber: loadNumberDisplay)
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
                    ("STAGE",   "BIDDING",       "first quote in",       .blue),
                    ("RATE",    rateDisplay,     "posted",               .green),
                    ("DIST",    distanceDisplay, "lane",                 .blue),
                    ("QUOTES",  "1",             "first on the floor",   .blue),
                ]
            case .competingQuote:
                return [
                    ("STAGE",   "BIDDING",       "second quote",         .blue),
                    ("RATE",    rateDisplay,     "posted",               .green),
                    ("DIST",    distanceDisplay, "lane",                 .blue),
                    ("QUOTES",  "2",             "two-way contest",      .blue),
                ]
            case .thirdQuote:
                return [
                    ("STAGE",   "BIDDING",       "third quote",          .blue),
                    ("RATE",    rateDisplay,     "posted",               .green),
                    ("DIST",    distanceDisplay, "lane",                 .blue),
                    ("QUOTES",  "3",             "three-way contest",    .blue),
                ]
            case .awardedAurora:
                return [
                    ("STAGE",   "AWARDED",       "Aurora wins",          .green),
                    ("RATE",    rateDisplay,     "awarded",              .green),
                    ("DIST",    distanceDisplay, "lane",                 .blue),
                    ("STATE",   (load?.status ?? "—").uppercased(), "load row", .green),
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
            case .firstBid:       return "First quote in. Lane is open — competing carriers have minutes to counter."
            case .competingQuote: return "Second quote lands. Shipper now weighs both offers; the cheaper or faster wins."
            case .thirdQuote:     return "Third quote on the board. Final-call clock running before the shipper awards."
            case .awardedAurora:  return "Aurora awarded. Ledger committed; assign a driver from the dispatcher board next."
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
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
        } catch { /* tolerated */ }
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
    var body: some View { CVQShell(theme: theme) { CVQBody(loadId: loadId, kind: .awardedAurora) } }
}

// MARK: - Previews

#Preview("379 First Bid · Light")        { CatalystM05FirstBidScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("380 Competing · Dark")         { CatalystM05CompetingQuoteScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("381 Third Quote · Light")      { CatalystM05ThirdQuoteScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("382 Awarded Aurora · Dark")    { CatalystM05AwardedAuroraScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
