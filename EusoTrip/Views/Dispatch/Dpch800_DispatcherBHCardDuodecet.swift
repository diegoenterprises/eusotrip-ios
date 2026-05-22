//
//  Dpch800_DispatcherBHCardDuodecet.swift
//  EusoTrip — Dispatcher · BH-card duodecet (514-525).
//
//  Pixel-match to:
//    514 Dispatcher BH Reassignment Sheet
//    515 Dispatcher BH Tender Resolved
//    516 Dispatcher BH Pickup Board Armed
//    517 Dispatcher BH Pickup Board Fired
//    518 Dispatcher BH In-Transit Card
//    519 Dispatcher BH Delivery Card Approaching
//    520 Dispatcher BH At Delivery Card
//    521 Dispatcher BH Docked Loading Card
//    522 Dispatcher BH Bol Pre Sign Card
//    523 Dispatcher BH Bol Signed Card
//    524 Dispatcher BH Paperwork Card
//    525 Dispatcher BH Closed Stage Card
//
//  Aurora-board dispatcher cards mirroring the driver/catalyst
//  backhaul chains from the dispatcher vantage. All 12 share
//  `DispatcherBHCardBody`. Body reads `loads.getById`. Bottom nav
//  frozen.
//

import SwiftUI

private struct DBCLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let rate: String?
}

enum DispatcherBHCardKind: String {
    case reassign, tenderResolved, pickupArmed, pickupFired, inTransit, deliveryApproach, atDelivery, dockedLoading, bolPreSign, bolSigned, paperwork, closed
}

private struct DBCConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let chainPill: String
}

private extension DispatcherBHCardKind {
    var config: DBCConfig {
        switch self {
        case .reassign:
            return .init(eyebrow: "DISPATCHER · BH REASSIGN · TENDER STAGED · 4m LEFT",
                         citation: "BH-7C3A · ME silent · 4:00 of 8:00 elapsed",
                         title: "Reassign backhaul",
                         subhead: "BH-7C3A · ME NO RESPONSE 4:00",
                         pillCopy: "LD-260517-BH7C3A09F1 · parent LD-7C3A SEALED · PHX WVDC dock 7B → Naturipe LA RDC",
                         chainPill: "Tender risks expiry — pre-stage carrier B + carrier C as fallback")
        case .tenderResolved:
            return .init(eyebrow: "DISPATCHER · TENDER · BACKHAUL · RESOLVED",
                         citation: "§304 · DISPATCHER BH RESOLVED · TRIPLET 3/3 CLOSED · NEXT-CHAIN 7/N",
                         title: "Tender resolved by ME",
                         subhead: "AURORA · MC942008 · §304 · AWARDED",
                         pillCopy: "ME accepted 0:00 ago · 4:00 left on window · DVIR pending · row 3 cleared",
                         chainPill: "LD-BH7C3A · PHX-LA · 372 mi · ME accepted · margin $172 LOCKED · DVIR pending")
        case .pickupArmed:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · PICKUP-BOARD",
                         citation: "§308 · BOARD-CONSOLIDATED · NEXT-CHAIN 11/N",
                         title: "Pickup board armed · 1 in window",
                         subhead: "AURORA · MC942008 · §308 · WATCH ARMED",
                         pillCopy: "Aurora board · ME DVIR 2/14 · ping -30 ARMED · pickup in 13h 32m",
                         chainPill: "LD-BH7C3A · PHX-LA · ME DVIR 2/14 · PING -30 ARMED · BOARD 1 ACTIVE")
        case .pickupFired:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · PICKUP-FIRED",
                         citation: "§322 · QUARTET 3/4 · NEXT-CHAIN 25/N",
                         title: "Pickup board fired · 1 loading",
                         subhead: "AURORA · MC942008 · §322 · BOARD FIRED",
                         pillCopy: "Aurora board · ME ON-SITE · DVIR 14/14 · DOCK 7B LOADING · 0:08 AGO",
                         chainPill: "LD-BH7C3A · PHX-WVDC dock 7B · ME LOADING 0:08 AGO · DVIR 14/14 COMPLETE")
        case .inTransit:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · IN-TRANSIT",
                         citation: "§326 · IN-TRANSIT CARD · QUARTET 3/4 · NEXT-CHAIN 29/N",
                         title: "In-transit · 1 driving",
                         subhead: "AURORA · MC942008 · §326 · IN-TRANSIT · DRIVING",
                         pillCopy: "Aurora board · ME I-10 WB · HOS 00:00 · ETA 06:24 MST · 372 mi remaining",
                         chainPill: "LD-BH7C3A · I-10 WB · ME driving · 12/12 sealed · ETA 06:24 MST")
        case .deliveryApproach:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · DELIVERY · APPROACH",
                         citation: "§330 · DELIVERY CARD · QUARTET 3/4 · NEXT-CHAIN 33/N",
                         title: "Delivery card · approaching",
                         subhead: "AURORA · MC942008 · §330 · APPROACHING",
                         pillCopy: "Aurora board · ME 26mi to RDC · HOS 01:50 · ETA 06:24 MST · 0:30 left",
                         chainPill: "LD-BH7C3A · I-10 WB approaching · ME 26mi · ETA 06:24 MST · on-time")
        case .atDelivery:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · AT-DELIVERY",
                         citation: "§334 · AT-DELIVERY CARD · SUB-AXIS 3/N · NEXT-CHAIN 37/N",
                         title: "At delivery · 1 docked",
                         subhead: "AURORA · MC942008 · §334 · AT DELIVERY",
                         pillCopy: "Aurora board · ME at Naturipe RDC · DOCK 7B GATE-IN · HOS 02:14 · queue 0",
                         chainPill: "LD-BH7C3A · gate-in armed · DOCK 7B pre-assigned · queue depth 0 · ETA 06:24 MST")
        case .dockedLoading:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · DOCKED-LOADING · 3/N",
                         citation: "§338 · DOCKED-LOADING CARD · SUB-AXIS 3/N · NEXT-CHAIN 41/N",
                         title: "Delivery · 1 docked loading",
                         subhead: "AURORA · MC942008 · §338 · DOCKED LOADING CARD",
                         pillCopy: "Aurora board · ME in DOCK 7B · HOS 02:30 · pallets 12/72 · depart 06:42 MST · 0:24 left",
                         chainPill: "LD-BH7C3A · DOCK 7B occupied · forklift OXN-FL-04 · 4 ppm · depart 06:42 MST")
        case .bolPreSign:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · BOL-PRE-SIGN · 3/N",
                         citation: "§345 · BOL-PRE-SIGN CARD · SUB-AXIS 3/N · NEXT-CHAIN 45/N",
                         title: "BOL pre-sign · 1 dock plate",
                         subhead: "AURORA · MC942008 · §345 · BOL PRE-SIGN CARD",
                         pillCopy: "Aurora board · ME at dock plate · BOL draft loaded · pallets 72/72 LOADED · depart 06:42 MST · 0:04 left",
                         chainPill: "LD-BH7C3A · BOL packet BOL-NLR-LA-2026-05-19-BH7C3A · DRAFT · ME signing")
        case .bolSigned:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · BOL-SIGNED · 3/N",
                         citation: "§349 · BOL-SIGNED CARD · SUB-AXIS 3/N · NEXT-CHAIN 49/N · VERIFIED WS",
                         title: "BOL signed · 1 sealed",
                         subhead: "AURORA · MC942008 · §349 · BOL SIGNED CARD",
                         pillCopy: "Aurora board · BOL SIGNED 0x9F1C · pallets 72/72 sealed · depart 06:42 MST window closing",
                         chainPill: "LD-BH7C3A · BOL doc SIGNED · sig 0x9F1C · paperwork watch armed")
        case .paperwork:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · PAPERWORK · 3/N",
                         citation: "§353 · PAPERWORK CARD · SUB-AXIS 3/N · NEXT-CHAIN 53/N",
                         title: "Paperwork · 1 open",
                         subhead: "AURORA · MC942008 · §353 · PAPERWORK CARD",
                         pillCopy: "Aurora board · ME at packet desk · BOL FILED · POD pending submit · HOS 03:02",
                         chainPill: "LD-BH7C3A · BOL filed BH7C3A-FILED · POD packet BH7C3A-POD · POD watch armed")
        case .closed:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · CLOSED · 3/N",
                         citation: "§357 · CLOSED CARD · QUARTET 3/N · NEXT-CHAIN 57/N",
                         title: "Closed · 1 BH card",
                         subhead: "AURORA · MC942008 · §357 · CLOSED CARD",
                         pillCopy: "Aurora board · POD submitted · HOS 03:08 · WALLET CREDITED · CHAIN-SEAL AVAILABLE",
                         chainPill: "LD-BH7C3A · POD submitted · escrow CREDITED $2,128 · chain-seal available")
        }
    }
}

private struct DispatcherBHCardShell<Content: View>: View {
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

private struct DispatcherBHCardBody: View {
    let loadId: String
    let kind: DispatcherBHCardKind

    @Environment(\.palette) private var palette
    @State private var load: DBCLoadCtx?

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
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private func header(_ c: DBCConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func pill(_ c: DBCConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chainPill(_ c: DBCConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("BOARD CONTEXT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
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
                    Text("USDOT 3 482 119 · MC-942 008 · LD-BH7C3A backhaul board").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .reassign:
                return [
                    ("STAGE",   "4m LEFT",                                      "tender expiry imminent", .red),
                    ("ME",      "NO RESP",                                       "4:00 silent",            .red),
                    ("BOARD",   "1 BH",                                           "in reassign window",   .orange),
                    ("STATE",   "STAGED",                                          "carrier B armed",     .blue),
                ]
            case .tenderResolved:
                return [
                    ("STATE",   "AWARDED",                                          "ME accepted · 0:00",  .green),
                    ("WINDOW",  "4:00",                                              "left on accept",     .green),
                    ("MARGIN",  "$172",                                                "LOCKED",            .green),
                    ("ROW",     "3/3",                                                  "triplet closed",   .green),
                ]
            case .pickupArmed:
                return [
                    ("WATCH",   "ARMED",                                                "ping -30",          .green),
                    ("DVIR",    "2/14",                                                  "ME · in progress", .orange),
                    ("PICKUP",  "13h 32m",                                                 "to gate open",   .blue),
                    ("BOARD",   "1 ACTIVE",                                                  "consolidated", .blue),
                ]
            case .pickupFired:
                return [
                    ("STATE",   "FIRED",                                                    "ME on-site · 0:08",  .green),
                    ("DVIR",    "14/14",                                                      "COMPLETE",        .green),
                    ("DOCK",    "7B",                                                          "loading · live", .orange),
                    ("QUARTET", "3/4",                                                          "§322",          .blue),
                ]
            case .inTransit:
                return [
                    ("STATE",   "DRIVING",                                                      "I-10 WB",       .blue),
                    ("DIST",    "372 mi",                                                        "remaining",    .blue),
                    ("ETA",     "06:24",                                                          "MST",         .blue),
                    ("HOS",     "00:00",                                                           "/ 11h clean", .green),
                ]
            case .deliveryApproach:
                return [
                    ("STATE",   "APPROACH",                                                       "26mi to RDC",  .green),
                    ("ETA",     "06:24",                                                            "MST · 0:30 left", .blue),
                    ("HOS",     "01:50",                                                             "/ 9h 10m",    .green),
                    ("BOARD",   "1 IN",                                                                "approach",  .blue),
                ]
            case .atDelivery:
                return [
                    ("STATE",   "GATE-IN",                                                              "DOCK 7B armed", .orange),
                    ("ETA",     "06:24",                                                                 "MST · on-time", .green),
                    ("QUEUE",   "0",                                                                       "depth ahead", .green),
                    ("HOS",     "02:14",                                                                    "/ 11h clean", .green),
                ]
            case .dockedLoading:
                return [
                    ("DOCK",    "7B",                                                                        "occupied",    .orange),
                    ("PALLETS", "12/72",                                                                       "loading 4 ppm", .blue),
                    ("DEPART",  "06:42",                                                                        "MST · 0:24 left", .blue),
                    ("HOS",     "02:30",                                                                          "/ 8h 30m",     .green),
                ]
            case .bolPreSign:
                return [
                    ("BOL",     "DRAFT",                                                                          "ME signing",    .blue),
                    ("PALLETS", "72/72",                                                                            "LOADED · sealed", .green),
                    ("DEPART",  "06:42",                                                                              "MST · 0:04 left", .orange),
                    ("STATE",   "PRE-SIGN",                                                                            "card 3/N",     .blue),
                ]
            case .bolSigned:
                return [
                    ("BOL",     "SIGNED",                                                                              "0x9F1C verified",  .green),
                    ("PALLETS", "72/72",                                                                                  "sealed in transit", .green),
                    ("DEPART",  "WINDOW",                                                                                  "closing",         .green),
                    ("STATE",   "SIGNED",                                                                                   "§349 · verified", .green),
                ]
            case .paperwork:
                return [
                    ("BOL",     "FILED",                                                                                    "BH7C3A-FILED",      .green),
                    ("POD",     "PENDING",                                                                                    "ME at packet desk", .orange),
                    ("WATCH",   "ARMED",                                                                                       "POD packet",      .blue),
                    ("HOS",     "03:02",                                                                                          "/ 7h 58m",     .green),
                ]
            case .closed:
                return [
                    ("POD",     "SUBMITTED",                                                                                      "ME at payout review", .green),
                    ("WALLET",  "CREDITED",                                                                                         "$2,128 NET-30",      .green),
                    ("SEAL",    "AVAILABLE",                                                                                          "chain-seal ready", .green),
                    ("HOS",     "03:08",                                                                                                "/ 7h 52m",       .green),
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
            case .reassign:        return "ME silent 4:00 of 8:00. Tap to reassign to carrier B; carrier C armed as second fallback."
            case .tenderResolved:  return "ME accepted at §304. Triplet 3/3 closed; DVIR sub-axis opens next."
            case .pickupArmed:     return "Pickup board armed. DVIR 2/14 in progress; -30 ping fires when ME pulls toward dock 7B."
            case .pickupFired:     return "ME loading at dock 7B (0:08 ago). DVIR 14/14 sealed; advance card to in-transit on gate-out."
            case .inTransit:       return "ME on I-10 WB, 372 mi to RDC. ETA holds 06:24 MST; clean HOS — no intervention needed."
            case .deliveryApproach:return "26 mi to receiver. Pre-arm DOCK 7B + paperwork access; ESang nudges 5 min out."
            case .atDelivery:      return "Gate-in at DOCK 7B. Queue 0 ahead; receiver-bay attestation arms on dock placement."
            case .dockedLoading:   return "Bay 7B occupied · 12/72 at 4 ppm. Depart at 06:42 MST; BOL pre-sign arms on dock-plate touch."
            case .bolPreSign:      return "BOL DRAFT loaded · pallets 72/72 sealed. Window closing in 0:04 — ME taps to sign next."
            case .bolSigned:       return "BOL SIGNED + verified (0x9F1C). Window closes; paperwork watch armed for filing."
            case .paperwork:       return "Paperwork open · BOL filed. POD watch armed; POD-ink fires when receiver co-signs."
            case .closed:          return "Chain sealed. POD submitted, wallet credited $2,128 NET-30. Chain-seal available for archive."
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

// MARK: - Screens (514-525)

struct DispatcherBHReassignScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherBHCardShell(theme: theme) { DispatcherBHCardBody(loadId: loadId, kind: .reassign) } }
}
struct DispatcherBHTenderResolvedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherBHCardShell(theme: theme) { DispatcherBHCardBody(loadId: loadId, kind: .tenderResolved) } }
}
struct DispatcherBHPickupArmedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherBHCardShell(theme: theme) { DispatcherBHCardBody(loadId: loadId, kind: .pickupArmed) } }
}
struct DispatcherBHPickupFiredScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherBHCardShell(theme: theme) { DispatcherBHCardBody(loadId: loadId, kind: .pickupFired) } }
}
struct DispatcherBHInTransitScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherBHCardShell(theme: theme) { DispatcherBHCardBody(loadId: loadId, kind: .inTransit) } }
}
struct DispatcherBHDeliveryApproachScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherBHCardShell(theme: theme) { DispatcherBHCardBody(loadId: loadId, kind: .deliveryApproach) } }
}
struct DispatcherBHAtDeliveryScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherBHCardShell(theme: theme) { DispatcherBHCardBody(loadId: loadId, kind: .atDelivery) } }
}
struct DispatcherBHDockedLoadingScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherBHCardShell(theme: theme) { DispatcherBHCardBody(loadId: loadId, kind: .dockedLoading) } }
}
struct DispatcherBHBOLPreSignScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherBHCardShell(theme: theme) { DispatcherBHCardBody(loadId: loadId, kind: .bolPreSign) } }
}
struct DispatcherBHBOLSignedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherBHCardShell(theme: theme) { DispatcherBHCardBody(loadId: loadId, kind: .bolSigned) } }
}
struct DispatcherBHPaperworkScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherBHCardShell(theme: theme) { DispatcherBHCardBody(loadId: loadId, kind: .paperwork) } }
}
struct DispatcherBHClosedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherBHCardShell(theme: theme) { DispatcherBHCardBody(loadId: loadId, kind: .closed) } }
}

// MARK: - Previews

#Preview("514 Reassign · Dark")    { DispatcherBHReassignScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("515 Resolved · Light")   { DispatcherBHTenderResolvedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("516 Armed · Dark")       { DispatcherBHPickupArmedScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("517 Fired · Light")      { DispatcherBHPickupFiredScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("518 Transit · Dark")     { DispatcherBHInTransitScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("519 Approach · Light")   { DispatcherBHDeliveryApproachScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("520 AtDel · Dark")       { DispatcherBHAtDeliveryScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("521 Dock · Light")       { DispatcherBHDockedLoadingScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("522 BOL Pre · Dark")     { DispatcherBHBOLPreSignScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("523 BOL Sign · Light")   { DispatcherBHBOLSignedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("524 Paper · Dark")       { DispatcherBHPaperworkScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("525 Closed · Light")     { DispatcherBHClosedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
