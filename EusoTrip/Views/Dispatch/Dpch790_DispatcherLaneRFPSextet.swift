//
//  Dpch790_DispatcherLaneRFPSextet.swift
//  EusoTrip — Dispatcher · Lane + RFP + Contract sextet (508-513).
//
//  Pixel-match to:
//    508 Dispatcher Lane Board
//    509 Dispatcher Lane Drill (KC → Omaha · 4 hauls)
//    510 Dispatcher Haul Detail (ME · LD B417)
//    511 Dispatcher RFP Tender Inbox
//    512 Dispatcher Catalyst Catalog Match Up
//    513 Dispatcher Contract Write Surface
//
//  All 6 share `DispatcherLaneRFPBody`. Body reads
//  `dispatchRole.getDispatchBoard` for live load list. Bottom nav
//  frozen (Dispatcher: Home / Board / ESANG / Me).
//

import SwiftUI

private struct DLRLoad: Decodable, Hashable {
    let id: String
    let loadNumber: String?
    let status: String?
    let shipper: String?
    let origin: String?
    let destination: String?
    let rate: Double?
    let pickupDate: String?
}

private struct DLRBoard: Decodable, Hashable {
    let loads: [DLRLoad]?
    let summary: Summary?
    struct Summary: Decodable, Hashable {
        let total: Int?
        let byStatus: ByStatus?
        struct ByStatus: Decodable, Hashable {
            let unassigned: Int?
            let inTransit: Int?
            let loading: Int?
        }
    }
}

enum DispatcherLaneRFPKind: String {
    case laneBoard, laneDrill, haulDetail, rfpInbox, matchUp, contractWrite
}

private struct DLRConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let chainPill: String
}

private extension DispatcherLaneRFPKind {
    var config: DLRConfig {
        switch self {
        case .laneBoard:
            return .init(eyebrow: "DISPATCHER · BOARD · LANES",
                         citation: "DISPATCHER LANE BOARD · 5 LANES · 14 HAULS · §508",
                         title: "Lane board",
                         subhead: "LANES 5 · LIVE 14 · OTR 94.6%",
                         pillCopy: "Renée routes lane-flow · KC→Omaha 4-haul concentration",
                         chainPill: "Aurora Freight Lines · 14 active hauls across 5 lanes")
        case .laneDrill:
            return .init(eyebrow: "DISPATCHER · BOARD · KC → OMA · 4 HAULS",
                         citation: "DISPATCHER LANE DRILL · KC → OMA · §509",
                         title: "KC → Omaha",
                         subhead: "HAULS 4 · OTR 100% · NEXT 18 MIN",
                         pillCopy: "Renée holds 4 hauls · §11.4 EUSORONE NH₃ DEDICATED · 1 founder pin",
                         chainPill: "Aurora Freight Lines · 4 active hauls · MC-331 NH₃ UN1005")
        case .haulDetail:
            return .init(eyebrow: "DISPATCHER · BOARD · ME · LD B417",
                         citation: "DISPATCHER HAUL DETAIL · ME · LD B417 · §510",
                         title: "ME · Michael Eusorone",
                         subhead: "ETA 42 MIN · HOS 6h 24m · $842 PAY",
                         pillCopy: "§11.4 EUSORONE NH₃ DEDICATED · escort cleared · 200 mi · 78 to dest",
                         chainPill: "Eusotrans LLC · LD-260427-B41782FF02 · KC → Omaha")
        case .rfpInbox:
            return .init(eyebrow: "DISPATCHER · BOARD · INBOX · 3 IN + 1 OUT",
                         citation: "DISPATCHER INBOX · ACQUISITION + BACKHAUL · §511 / §299",
                         title: "RFP inbox",
                         subhead: "BOOK $9,650 · HIT 76% · NEXT 8 MIN",
                         pillCopy: "Renée holds 3 inbound RFPs · 1 outbound BH tender STAGED · ME 8m",
                         chainPill: "Aurora Freight · 3 inbound from Eusorone + 1 outbound BH · sorted by expiry")
        case .matchUp:
            return .init(eyebrow: "DISPATCHER · BOARD · MATCH · 6 CANDIDATES",
                         citation: "DISPATCHER MATCH UP · §512 · ACQUISITION PORT 2/3",
                         title: "Match capacity",
                         subhead: "BEST $2,950 · FIT 96 · NH₃ MC-331",
                         pillCopy: "Aurora · KC→Omaha NH₃ · 6 candidates ranked by fit",
                         chainPill: "LD-B417 KC→Omaha · NH₃ MC-331 · $3,200 · DU EUSORONE · §11.4 ACCEPTED RFP 0:42 AGO")
        case .contractWrite:
            return .init(eyebrow: "DISPATCHER · BOARD · CONTRACT · WRITE",
                         citation: "DISPATCHER CONTRACT WRITE · §513 · ACQUISITION PORT 3/3 · TRIGGER CLOSE",
                         title: "Write counter",
                         subhead: "COUNTER $2,425 · DELTA +$225 · 26m",
                         pillCopy: "Aurora · LA→Phoenix Reefer · 6 terms to commit",
                         chainPill: "LD-7C3A LA→Phoenix · Reefer 33-38°F · $2,200 → $2,425 · DU EUSORONE · §11.4 RFP UNDER COUNTER")
        }
    }
}

private struct DispatcherLaneRFPShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.stack.fill", isCurrent: true)],
                trailing: [NavSlot(label: "ESANG", systemImage: "sparkles", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",   isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct DispatcherLaneRFPBody: View {
    let kind: DispatcherLaneRFPKind

    @Environment(\.palette) private var palette
    @State private var board: DLRBoard?

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                pill(c)
                chainPill(c)
                identityRow
                kpiGrid
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func header(_ c: DLRConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func pill(_ c: DLRConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chainPill(_ c: DLRConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("CHAIN CONTEXT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.chainPill).font(.caption2).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("RM").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aurora Freight Lines · Renée Marquette · senior dispatcher").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("USDOT 3 482 119 · MC-942 008 · LIVE \(board?.summary?.total ?? 14) hauls").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let total = board?.summary?.total ?? 14
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .laneBoard:
                return [
                    ("LANES",     "5",                              "live corridors",       .blue),
                    ("HAULS",     "\(total)",                        "active · live",      .blue),
                    ("OTR",       "94.6%",                            "on-the-road",      .green),
                    ("BUSY",      "KC→OMA",                            "4 hauls · top lane", .blue),
                ]
            case .laneDrill:
                return [
                    ("HAULS",     "4",                                  "KC → OMA · live",  .blue),
                    ("OTR",       "100%",                                "lane clean",      .green),
                    ("NEXT",      "18m",                                 "to next gate",    .orange),
                    ("HAZMAT",    "NH₃",                                  "MC-331 escort",   .blue),
                ]
            case .haulDetail:
                return [
                    ("ETA",       "42 min",                              "to dest",           .blue),
                    ("HOS",       "6h 24m",                                "headroom · clean", .green),
                    ("PAY",       "$842",                                    "ME · LD B417",  .green),
                    ("MILES",     "78/200",                                    "39% remaining", .blue),
                ]
            case .rfpInbox:
                return [
                    ("INBOX",     "4",                                          "3 in + 1 out",  .blue),
                    ("BOOK",      "$9,650",                                       "in-flight",   .green),
                    ("HIT-RATE",  "76%",                                            "90d",       .green),
                    ("NEXT",      "8m",                                                "ME BH",  .orange),
                ]
            case .matchUp:
                return [
                    ("CAND",      "6",                                                "ranked · §512",  .blue),
                    ("BEST",      "$2,950",                                            "fit 96 · NH₃",  .green),
                    ("RFP",       "$3,200",                                              "DU EUSORONE",  .blue),
                    ("CITATION",  "§11.4",                                                "ACCEPTED RFP",  .green),
                ]
            case .contractWrite:
                return [
                    ("COUNTER",   "$2,425",                                                "from $2,200", .green),
                    ("DELTA",     "+$225",                                                   "+10.2%",     .green),
                    ("TIMER",     "26m",                                                       "to commit",  .orange),
                    ("TERMS",     "6",                                                          "to commit",  .blue),
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
            case .laneBoard:    return "5 lanes live with 14 hauls. KC→Omaha holds 4 of 14; drill in for the NH₃ escort detail."
            case .laneDrill:    return "KC→Omaha at 100% OTR. Next gate in 18 min; pre-clear the founder-pin haul (ME LD B417)."
            case .haulDetail:   return "ME on LD B417 · 78 mi to dest · 6h 24m HOS headroom. Confirm escort handoff at next gate."
            case .rfpInbox:     return "3 inbound RFPs + 1 outbound BH tender STAGED. Next decision in 8m for ME backhaul."
            case .matchUp:      return "6 candidates ranked. Best is $2,950 · fit 96 vs $3,200 RFP — capture the $250 margin."
            case .contractWrite:return "Counter $2,425 (+$225 vs $2,200). 26m to commit. 6 terms remain; ESang flags hazmat addendum."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func load() async {
        struct In: Encodable { let status: String?; let priority: String? }
        do { board = try await EusoTripAPI.shared.query("dispatchRole.getDispatchBoard", input: In(status: nil, priority: "all")) } catch { /* */ }
    }
}

// MARK: - Screens (508-513)

struct DispatcherLaneBoardScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherLaneRFPShell(theme: theme) { DispatcherLaneRFPBody(kind: .laneBoard) } }
}
struct DispatcherLaneDrillScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherLaneRFPShell(theme: theme) { DispatcherLaneRFPBody(kind: .laneDrill) } }
}
struct DispatcherHaulDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherLaneRFPShell(theme: theme) { DispatcherLaneRFPBody(kind: .haulDetail) } }
}
struct DispatcherRFPInboxScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherLaneRFPShell(theme: theme) { DispatcherLaneRFPBody(kind: .rfpInbox) } }
}
struct DispatcherMatchUpScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherLaneRFPShell(theme: theme) { DispatcherLaneRFPBody(kind: .matchUp) } }
}
struct DispatcherContractWriteScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherLaneRFPShell(theme: theme) { DispatcherLaneRFPBody(kind: .contractWrite) } }
}

// MARK: - Previews

#Preview("508 Board · Dark")    { DispatcherLaneBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("509 Drill · Light")   { DispatcherLaneDrillScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("510 Haul · Dark")     { DispatcherHaulDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("511 Inbox · Light")   { DispatcherRFPInboxScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("512 Match · Dark")    { DispatcherMatchUpScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("513 Contract · Light"){ DispatcherContractWriteScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
