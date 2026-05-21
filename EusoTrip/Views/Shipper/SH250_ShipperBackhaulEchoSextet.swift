//
//  SH250_ShipperBackhaulEchoSextet.swift
//  EusoTrip — Shipper · Backhaul-echo sextet (SH250-SH255).
//
//  Pixel-match to:
//    250 Shipper Backhaul Eyebrow
//    251 Shipper Backhaul Annex Update
//    252 Shipper BH Pickup Echo Annex
//    253 Shipper BH Pickup Echo Fired
//    254 Shipper BH In-Transit Echo
//    255 Shipper BH Delivery Echo
//
//  Shipper-vantage mirror of Catalyst CV357-CV363 — same backhaul
//  chain but framed as a closed shipper load that surfaces a sealed
//  "ledger remains sealed" echo card. IDs prefixed `SH` to avoid
//  collision with the Shipper Post-Load wizard at 250-260. Body
//  reads `loads.getById`. Bottom nav frozen (Shipper: Home / Loads /
//  ESANG / Me — per shipper-bottom-nav doctrine).
//

import SwiftUI

private struct SBLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let trailerType: String?
    let rate: String?
    let distance: Double?
}

enum ShipperBackhaulEchoKind: String {
    case eyebrow, awarded, pickupAnnex, pickupFired, inTransit, delivery
}

private struct SBConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let chainPill: String
    let echoState: String   // "STAGED" / "AWARDED" / "WATCH ARMED" / "ECHO CLOSED"
}

private extension ShipperBackhaulEchoKind {
    var config: SBConfig {
        switch self {
        case .eyebrow:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · BACKHAUL ECHO",
                         citation: "§300 · BH-7C3A · QUARTET 4/4 · BACKHAUL DISPATCHED FROM YOUR CHAIN",
                         title: "Closed · backhaul echo",
                         subhead: "BH-7C3A · §300 · QUARTET 4/4",
                         pillCopy: "Aurora dispatched a backhaul from your sealed chain · QUARTET 4/4 · ledger remains sealed",
                         chainPill: "BACKHAUL DISPATCHED FROM YOUR CHAIN · MC-942 008 · ME STAGED · QUARTET 4/4",
                         echoState: "STAGED")
        case .awarded:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · BACKHAUL AWARDED",
                         citation: "§305 · BH-7C3A · AWARDED 4/4 · DISPATCH-RESOLVED",
                         title: "Closed · backhaul awarded",
                         subhead: "BH-7C3A · §305 · AWARDED 4/4",
                         pillCopy: "Aurora tender ACCEPTED by ME · AWARDED QUARTET 4/4 · ledger remains sealed",
                         chainPill: "BACKHAUL DISPATCH-RESOLVED · MC-942 008 · ME ACCEPTED · AWARDED 4/4",
                         echoState: "AWARDED")
        case .pickupAnnex:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · BACKHAUL PICKUP-ECHO",
                         citation: "§309 · BH-7C3A · PICKUP 4/4 · PICKUP-FORERUNNER",
                         title: "Closed · backhaul pickup armed",
                         subhead: "BH-7C3A · §309 · PICKUP 4/4",
                         pillCopy: "Aurora ping armed · ME DVIR 2/14 · pickup in 13h 20m · ledger sealed",
                         chainPill: "BACKHAUL PICKUP-FORERUNNER · MC-942 008 · ME DVIR 2/14 · PICKUP 4/4",
                         echoState: "WATCH ARMED")
        case .pickupFired:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · BACKHAUL PICKUP-FIRED",
                         citation: "§323 · BH-7C3A · PICKUP 4/4 · PICKUP-PROPER",
                         title: "Pickup closed · dock 7B loading",
                         subhead: "BH-7C3A · §323 · PICKUP 4/4",
                         pillCopy: "ME loading · DVIR 14/14 COMPLETE · Aurora board fired · 0:12 ago · ledger sealed",
                         chainPill: "BACKHAUL PICKUP-PROPER · MC-942 008 · ME DVIR 14/14 COMPLETE · QUARTET 4/4",
                         echoState: "ECHO CLOSED")
        case .inTransit:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · BACKHAUL IN-TRANSIT",
                         citation: "§327 · BH-7C3A · IN-TRANSIT 4/4 · I-10 WB",
                         title: "In-transit · ME driving",
                         subhead: "BH-7C3A · §327 · IN-TRANSIT 4/4",
                         pillCopy: "372 mi remaining · ETA 06:24 MST · 2h 16m · HOS 00:00 / 11h left · ledger sealed",
                         chainPill: "BACKHAUL IN-TRANSIT · MC-942 008 · ME I-10 WB DRIVING · QUARTET 4/4",
                         echoState: "ECHO CLOSED")
        case .delivery:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · BACKHAUL DELIVERY",
                         citation: "§331 · BH-7C3A · DELIVERY 4/4 · I-10 WB APPROACHING",
                         title: "Delivery · ME approaching",
                         subhead: "BH-7C3A · §331 · DELIVERY 4/4",
                         pillCopy: "26 mi remaining · ETA 06:24 MST · 0:26 left · HOS 01:50 / 9h 10m left · ledger sealed",
                         chainPill: "BACKHAUL DELIVERY · MC-942 008 · ME I-10 WB APPROACHING · QUARTET 4/4",
                         echoState: "ECHO CLOSED")
        }
    }
}

private struct ShipperBackhaulEchoShell<Content: View>: View {
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

private struct ShipperBackhaulEchoBody: View {
    let loadId: String
    let kind: ShipperBackhaulEchoKind

    @Environment(\.palette) private var palette
    @State private var load: SBLoadCtx?

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                chainPill(c)
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

    private func header(_ c: SBConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: SBConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text("LD-BH7C3A · PHX-WVDC dock 7B → Naturipe LA RDC · 372 mi · 0 deadhead").font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func chainPill(_ c: SBConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("ECHO · \(c.echoState)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(echoColor(c.echoState))
                Text(c.chainPill).font(.caption2).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("DU").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eusorone Technologies · Diego Usoro · shipper-of-record").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("companyId 1 · LD-BH7C3A · ledger sealed · backhaul echo only").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: SBConfig) -> some View {
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .eyebrow:
                return [
                    ("STATE",   "STAGED",                  "Aurora ready to tender",   .blue),
                    ("PAYOUT",  "$\(load?.rate ?? "2,300")", "to ME · NET-30",         .green),
                    ("DIST",    "372 mi",                    "0 deadhead",             .green),
                    ("LEDGER",  "SEALED",                     "your chain · closed",   .green),
                ]
            case .awarded:
                return [
                    ("STATE",   "AWARDED",                  "ME accepted · 4/4",       .green),
                    ("WINDOW",  "4:00",                      "left on accept",          .green),
                    ("DIST",    "372 mi",                    "0 deadhead",              .green),
                    ("LEDGER",  "SEALED",                     "your chain · closed",   .green),
                ]
            case .pickupAnnex:
                return [
                    ("STATE",   "WATCH ARMED",                "pickup · ping ready",  .green),
                    ("DVIR",    "2/14",                        "ME · in progress",     .orange),
                    ("PICKUP",  "13h 20m",                      "to gate open",         .blue),
                    ("LEDGER",  "SEALED",                       "your chain · closed", .green),
                ]
            case .pickupFired:
                return [
                    ("STATE",   "ECHO CLOSED",                  "Aurora board fired",  .green),
                    ("DVIR",    "14/14",                          "COMPLETE",          .green),
                    ("DOCK",    "7B",                              "loading · 0:12 ago", .orange),
                    ("LEDGER",  "SEALED",                            "your chain · closed", .green),
                ]
            case .inTransit:
                return [
                    ("STATE",   "ROLLING",                          "I-10 WB",          .green),
                    ("ETA",     "06:24",                              "MST · 2h 16m",   .blue),
                    ("HOS",     "11h",                                  "left · clean", .green),
                    ("LEDGER",  "SEALED",                                "your chain · closed", .green),
                ]
            case .delivery:
                return [
                    ("STATE",   "APPROACHING",                          "26 mi to RDC", .green),
                    ("ETA",     "06:24",                                  "MST · 0:26 left", .blue),
                    ("HOS",     "9h 10m",                                   "left · clean",  .green),
                    ("LEDGER",  "SEALED",                                    "your chain · closed", .green),
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
            case .eyebrow:      return "Read-only echo. Your sealed chain triggered Aurora's backhaul tender; ledger stays sealed regardless of outcome."
            case .awarded:      return "ME accepted Aurora's tender on your sealed chain. The award is logged; ledger remains sealed."
            case .pickupAnnex:  return "Pickup watch armed. ME is mid-DVIR. You see this for chain-of-custody only — no action required."
            case .pickupFired:  return "Pickup fired at dock 7B. DVIR cleared; loading begins. Echo will close on POD."
            case .inTransit:    return "ME driving I-10 WB toward LA. You retain audit visibility; chain-of-custody auto-attests."
            case .delivery:     return "ME 26 mi from receiver. Delivery echo will close on dock-7B touch; POD chain seals automatically."
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

private func echoColor(_ state: String) -> Color {
    switch state {
    case "STAGED":      return .blue
    case "AWARDED":     return .green
    case "WATCH ARMED": return .green
    case "ECHO CLOSED": return .green
    default:            return .gray
    }
}

// MARK: - Screens (SH250-SH255)

struct ShipperBackhaulEyebrowScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperBackhaulEchoShell(theme: theme) { ShipperBackhaulEchoBody(loadId: loadId, kind: .eyebrow) } }
}
struct ShipperBackhaulAwardedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperBackhaulEchoShell(theme: theme) { ShipperBackhaulEchoBody(loadId: loadId, kind: .awarded) } }
}
struct ShipperBackhaulPickupAnnexScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperBackhaulEchoShell(theme: theme) { ShipperBackhaulEchoBody(loadId: loadId, kind: .pickupAnnex) } }
}
struct ShipperBackhaulPickupFiredScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperBackhaulEchoShell(theme: theme) { ShipperBackhaulEchoBody(loadId: loadId, kind: .pickupFired) } }
}
struct ShipperBackhaulInTransitScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperBackhaulEchoShell(theme: theme) { ShipperBackhaulEchoBody(loadId: loadId, kind: .inTransit) } }
}
struct ShipperBackhaulDeliveryScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperBackhaulEchoShell(theme: theme) { ShipperBackhaulEchoBody(loadId: loadId, kind: .delivery) } }
}

// MARK: - Previews

#Preview("SH250 Eyebrow · Dark")    { ShipperBackhaulEyebrowScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("SH251 Awarded · Light")   { ShipperBackhaulAwardedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("SH252 PickAnnex · Dark")  { ShipperBackhaulPickupAnnexScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("SH253 PickFired · Light") { ShipperBackhaulPickupFiredScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("SH254 Transit · Dark")    { ShipperBackhaulInTransitScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("SH255 Delivery · Light")  { ShipperBackhaulDeliveryScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
