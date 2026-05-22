//
//  Dpch820_DispatcherM04KanbanQuintet.swift
//  EusoTrip — Dispatcher · M-04 kanban quintet (526-530).
//
//  Pixel-match to:
//    526 Dispatcher Kanban Cel Awarded M04
//    527 Dispatcher Pickup On-Site Echo Cel M04
//    528 Dispatcher In Transit Kanban Cel M04
//    529 Dispatcher At Delivery Kanban Cel M04
//    530 Dispatcher Paperwork Kanban Cel M04
//
//  Closes the Dispatcher M-04 series — kanban-board view of the
//  CEL-awarded LD-E5C9 (Atlanta → Charlotte) as it advances through
//  lane swimlanes. All 5 share `DispatcherM04KanbanBody`. Body reads
//  `loads.getById`. Bottom nav frozen.
//

import SwiftUI

private struct DKLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
}

enum DispatcherM04KanbanKind: String {
    case awardedShift, pickupOnSite, inTransitRolling, atDeliveryArrived, paperworkSettling
}

private struct DKConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let boardPill: String
}

private extension DispatcherM04KanbanKind {
    var config: DKConfig {
        switch self {
        case .awardedShift:
            return .init(eyebrow: "DISPATCHER · BOARD · AWARDED · M-04 SHIFT",
                         citation: "§370 · KANBAN SHIFT BIDDING → AWARDED · M-04 · CHAIN PORT 12/N · SHIFT 0:08 AGO",
                         title: "Kanban · M-04 shifts BIDDING → AWARDED · CEL board",
                         subhead: "LD-E5C9 · §370 · AWARDED · 3/N · KANBAN",
                         pillCopy: "Atlanta GA → Charlotte NC · NC dispatching · $1,610 · assign ≤ 23h 36m",
                         boardPill: "LD-260427-E5C9A41B22 · CEL board · NC dispatching · 47 cards")
        case .pickupOnSite:
            return .init(eyebrow: "DISPATCHER · BOARD · PICKUP · M-04 ON-SITE",
                         citation: "§388 · PICKUP · ON-SITE ECHO · M-04 · QUARTET 3/N · ON-SITE 0:04 AGO",
                         title: "Kanban · M-04 in PICKUP lane · JR on-site dock 4A",
                         subhead: "LD-E5C9 · §388 · PICKUP · 3/N · ON-SITE",
                         pillCopy: "Atlanta GA → Charlotte NC · NC dispatching · on-site 08:04 · dwell 0:04",
                         boardPill: "LD-260427-E5C9A41B22 · CEL board · NC dispatching · 47 cards")
        case .inTransitRolling:
            return .init(eyebrow: "DISPATCHER · BOARD · IN-TRANSIT · M-04 ROLLING",
                         citation: "§396 · KANBAN · IN-TRANSIT LANE · M-04 · CHAIN PORT 13/N · ROLLING 1:19",
                         title: "Kanban · M-04 rolling in IN-TRANSIT lane · CEL board",
                         subhead: "LD-E5C9 · §396 · TRANSIT · 3/4 · KANBAN",
                         pillCopy: "Atlanta GA → Charlotte NC · NC dispatching · JR rolling · 74/245 mi · ETA 12:43 EDT",
                         boardPill: "LD-260427-E5C9A41B22 · CEL board · NC dispatching · 14 in-transit cards")
        case .atDeliveryArrived:
            return .init(eyebrow: "DISPATCHER · BOARD · AT-DELIVERY · M-04 ARRIVED",
                         citation: "§400 · KANBAN · DELIVERY LANE · M-04 · CHAIN PORT 14/N · ARRIVED 0:00",
                         title: "Kanban · M-04 in DELIVERY lane · CEL board",
                         subhead: "LD-E5C9 · §400 · DELIVERY · 3/4 · KANBAN",
                         pillCopy: "Atlanta GA → Charlotte NC · NC dispatching · JR on-site · 245/245 mi · arr 12:43 EDT",
                         boardPill: "LD-260427-E5C9A41B22 · CEL board · NC dispatching · 1 at-delivery card")
        case .paperworkSettling:
            return .init(eyebrow: "DISPATCHER · BOARD · PAPERWORK · M-04 SETTLING",
                         citation: "§404 · KANBAN · PAPERWORK LANE · M-04 · CHAIN PORT 15/N · SETTLING 0:00",
                         title: "Kanban · M-04 in PAPERWORK lane · CEL board",
                         subhead: "LD-E5C9 · §404 · PAPERWORK · 3/4 · KANBAN",
                         pillCopy: "Atlanta GA → Charlotte NC · NC dispatching · delivered · settlement queued · POD 13:34 EDT",
                         boardPill: "LD-260427-E5C9A41B22 · CEL board · NC dispatching · 1 settlement card")
        }
    }
}

private struct DispatcherM04KanbanShell<Content: View>: View {
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

private struct DispatcherM04KanbanBody: View {
    let loadId: String
    let kind: DispatcherM04KanbanKind

    @Environment(\.palette) private var palette
    @State private var load: DKLoadCtx?

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                pill(c)
                boardPill(c)
                identityRow
                kpiGrid
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private func header(_ c: DKConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func pill(_ c: DKConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func boardPill(_ c: DKConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("BOARD STATE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.boardPill).font(.caption2).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("NC").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("CEL · Naomi Chen · dispatcher").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("Carolina Express Logistics · MC-712 944 · JR driver · DU shipper").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .awardedShift:
                return [
                    ("LANE-IN",    "AWARDED",          "from BIDDING · 0:08",  .green),
                    ("CARDS",      "47",                 "CEL board",          .blue),
                    ("PAYOUT",     "$1,610",              "CEL win",           .green),
                    ("ASSIGN",     "≤ 23h 36m",            "to driver",         .blue),
                ]
            case .pickupOnSite:
                return [
                    ("LANE-IN",    "PICKUP",                "on-site echo",     .green),
                    ("DOCK",       "4A",                     "dwell 0:04",      .orange),
                    ("CARDS",      "47",                      "CEL board",      .blue),
                    ("STATE",      "ON-SITE",                  "JR · CEL",      .green),
                ]
            case .inTransitRolling:
                return [
                    ("LANE",       "IN-TRANSIT",                "rolling · §396", .blue),
                    ("DIST",       "74/245",                     "30% leg",       .blue),
                    ("ETA",        "12:43",                       "EDT · rolling 1:19", .blue),
                    ("CARDS",      "14",                            "in-transit lane", .blue),
                ]
            case .atDeliveryArrived:
                return [
                    ("LANE",       "DELIVERY",                       "arrived · §400",  .green),
                    ("DIST",       "245/245",                          "100% leg",       .green),
                    ("ARRIVED",    "12:43",                              "EDT · 0:00",   .green),
                    ("CARDS",      "1",                                    "at-delivery lane", .blue),
                ]
            case .paperworkSettling:
                return [
                    ("LANE",       "PAPERWORK",                              "settling · §404",  .green),
                    ("POD",        "13:34",                                    "EDT · delivered",  .green),
                    ("PAYOUT",     "$1,610",                                     "settlement queued", .green),
                    ("CARDS",      "1",                                            "settlement lane", .blue),
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
            case .awardedShift:      return "M-04 shifted from BIDDING to AWARDED lane. CEL captures the $1,610 win; assign within 23h 36m."
            case .pickupOnSite:      return "JR on-site at dock 4A. Dwell timer live; advance kanban card to LOADING when receiver waves to plate."
            case .inTransitRolling:  return "JR rolling at 30% leg. ETA holds 12:43 EDT; ESang nudges if drift exceeds 10 min."
            case .atDeliveryArrived: return "Arrived CLT Newell at 12:43 (17 min early). Auto-advance to PAPERWORK lane on dock placement."
            case .paperworkSettling: return "POD signed at 13:34; settlement queued. Card auto-archives when wallet credit confirms."
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

// MARK: - Screens (526-530)

struct DispatcherM04AwardedKanbanScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherM04KanbanShell(theme: theme) { DispatcherM04KanbanBody(loadId: loadId, kind: .awardedShift) } }
}
struct DispatcherM04PickupKanbanScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherM04KanbanShell(theme: theme) { DispatcherM04KanbanBody(loadId: loadId, kind: .pickupOnSite) } }
}
struct DispatcherM04InTransitKanbanScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherM04KanbanShell(theme: theme) { DispatcherM04KanbanBody(loadId: loadId, kind: .inTransitRolling) } }
}
struct DispatcherM04AtDeliveryKanbanScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherM04KanbanShell(theme: theme) { DispatcherM04KanbanBody(loadId: loadId, kind: .atDeliveryArrived) } }
}
struct DispatcherM04PaperworkKanbanScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherM04KanbanShell(theme: theme) { DispatcherM04KanbanBody(loadId: loadId, kind: .paperworkSettling) } }
}

// MARK: - Previews

#Preview("526 Awarded · Dark")    { DispatcherM04AwardedKanbanScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("527 Pickup · Light")    { DispatcherM04PickupKanbanScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("528 Transit · Dark")    { DispatcherM04InTransitKanbanScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("529 AtDel · Light")     { DispatcherM04AtDeliveryKanbanScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("530 Paperwork · Dark")  { DispatcherM04PaperworkKanbanScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
