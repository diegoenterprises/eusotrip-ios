//
//  SH256_ShipperBackhaulEchoCloseQuintet.swift
//  EusoTrip — Shipper · Backhaul-echo close quintet (SH256-SH260).
//
//  Pixel-match to:
//    256 Shipper BH Docked Loading Echo Closed
//    257 Shipper BH Bol Pre Sign Echo Closed
//    258 Shipper BH Bol Signed Echo Closed
//    259 Shipper BH Paperwork Echo Closed
//    260 Shipper BH Closed Echo Closed
//
//  Closes the Shipper backhaul-echo chain that began at SH250.
//  Shipper-vantage echo of the Catalyst CV364-CV368 close quintet.
//  All 5 share `ShipperBackhaulEchoCloseBody`. Body reads
//  `loads.getById`. Bottom nav frozen (Shipper: Home / Loads / ESANG
//  / Me).
//

import SwiftUI

private struct SCLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let rate: String?
    let podCertId: String?
}

enum ShipperBackhaulEchoCloseKind: String {
    case dockedLoading, bolPreSign, bolSigned, paperwork, closedSeal
}

private struct SCConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let chainPill: String
    let echoState: String
}

private extension ShipperBackhaulEchoCloseKind {
    var config: SCConfig {
        switch self {
        case .dockedLoading:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · DOCKED LOADING ECHO",
                         citation: "§339 · BH-7C3A · DOCKED 4/N · SUB-AXIS 4/N",
                         title: "Delivery · ME at bay 7B",
                         subhead: "BH-7C3A · §339 · DOCKED 4/N",
                         pillCopy: "Pallets 12/72 · DEPART 06:42 MST · 0:24 left · HOS 02:30 ON-DUTY · 8h 30m left · ledger sealed",
                         chainPill: "BACKHAUL DELIVERY · MC-942 008 · ME BAY 7B PALLETS 12/72 · SUB-AXIS 4/N",
                         echoState: "DOCKED LOADING")
        case .bolPreSign:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · BOL PRE-SIGN ECHO",
                         citation: "§346 · BH-7C3A · BOL 4/N · SUB-AXIS 4/N",
                         title: "Delivery · ME at bay 7B",
                         subhead: "BH-7C3A · §346 · BOL 4/N",
                         pillCopy: "BOL DRAFT · packet BOL-NLR-LA · DEPART 06:42 MST · 0:02 left · HOS 02:52 · ledger sealed",
                         chainPill: "BACKHAUL DELIVERY · MC-942 008 · ME BAY 7B BOL DRAFT 4 OF 4 · SUB-AXIS 4/N",
                         echoState: "BOL PRE-SIGN")
        case .bolSigned:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · BOL SIGNED ECHO",
                         citation: "§350 · BH-7C3A · BOL SIGNED 4/N · SUB-AXIS 4/N",
                         title: "Delivery · ME at bay 7B",
                         subhead: "BH-7C3A · §350 · BOL SIGNED 4/N",
                         pillCopy: "BOL SIGNED 0x9F1C · packet BOL-NLR-LA SIGNED · DEPART 06:42 MST window closed · HOS 03:01 · ledger sealed",
                         chainPill: "BACKHAUL DELIVERY · MC-942 008 · ME BAY 7B BOL SIGNED 4 OF 4 · SUB-AXIS 4/N",
                         echoState: "BOL SIGNED")
        case .paperwork:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · PAPERWORK ECHO",
                         citation: "§354 · BH-7C3A · PAPERWORK 4/4 · QUARTET SEALED",
                         title: "Paperwork · quartet 4 of 4 sealed",
                         subhead: "BH-7C3A · §354 · PAPERWORK 4/4",
                         pillCopy: "PAPERWORK OPEN · packet FILED · POD watch armed · DEPART 06:42 MST · HOS 03:05 · ledger sealed",
                         chainPill: "BACKHAUL PAPERWORK · MC-942 008 · ME BAY 7B CLEARED · QUARTET 4 OF 4 · SEALED",
                         echoState: "PAPERWORK")
        case .closedSeal:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · CHAIN SEAL",
                         citation: "§358 · BH-7C3A · CLOSED 4/4 · CHAIN SEALED",
                         title: "Closed · chain sealed at four of four",
                         subhead: "BH-7C3A · §358 · CLOSED 4/4 · CHAIN SEALED",
                         pillCopy: "CLOSED SEALED · POD archived · wallet CREDITED · NET-30 · HOS 03:09 · BH-7C3A sealed",
                         chainPill: "BACKHAUL CLOSED · MC-942 008 · ME BAY 7B CLEARED · CHAIN SEALED · QUARTET 4 OF 4",
                         echoState: "CLOSED SEAL")
        }
    }
}

private struct ShipperBackhaulEchoCloseShell<Content: View>: View {
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

private struct ShipperBackhaulEchoCloseBody: View {
    let loadId: String
    let kind: ShipperBackhaulEchoCloseKind

    @Environment(\.palette) private var palette
    @State private var load: SCLoadCtx?

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

    private func header(_ c: SCConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: SCConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text("LD-BH7C3A · PHX-WVDC dock 7B → Naturipe LA RDC").font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func chainPill(_ c: SCConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(c.echoState) · ECHO CLOSED").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.green)
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

    private func kpiGrid(_ c: SCConfig) -> some View {
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .dockedLoading:
                return [
                    ("BAY",     "7B",                 "OCCUPIED · live",         .orange),
                    ("PALLETS", "12/72",                "loading · 4 ppm",        .blue),
                    ("DEPART",  "06:42",                 "MST · 0:24 left",       .blue),
                    ("LEDGER",  "SEALED",                  "your chain · closed", .green),
                ]
            case .bolPreSign:
                return [
                    ("BOL",     "DRAFT",                 "BOL-NLR-LA · ME signing", .blue),
                    ("PALLETS", "72/72",                  "LOADED · sealed",       .green),
                    ("DEPART",  "06:42",                   "MST · 0:02 left",      .orange),
                    ("LEDGER",  "SEALED",                    "your chain · closed", .green),
                ]
            case .bolSigned:
                return [
                    ("BOL",     "SIGNED",                  "0x9F1C · verified",   .green),
                    ("DEPART",  "WINDOW",                   "closed · departing", .green),
                    ("HOS",     "03:01",                     "ON-DUTY · clean",   .green),
                    ("LEDGER",  "SEALED",                      "your chain · closed", .green),
                ]
            case .paperwork:
                return [
                    ("PACKET",  "FILED",                    "BH7C3A-FILED",       .green),
                    ("POD",     "WATCH",                      "armed",            .blue),
                    ("QUARTET", "4/4",                          "sealed · §354",    .green),
                    ("LEDGER",  "SEALED",                         "your chain · closed", .green),
                ]
            case .closedSeal:
                return [
                    ("POD",     "ARCHIVED",                       load?.podCertId ?? "BH7C3A-POD-archived", .green),
                    ("WALLET",  "CREDITED",                          "NET-30 wired", .green),
                    ("QUARTET", "4/4",                                "chain sealed",  .green),
                    ("LEDGER",  "SEALED",                                 "BH-7C3A closed", .green),
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
            case .dockedLoading: return "ME at bay 7B loading at 4 ppm. Echo closes on dock-out; no shipper action needed."
            case .bolPreSign:    return "BOL draft armed for ME signature. Echo closes when sig-hash lands."
            case .bolSigned:     return "BOL signed and verified (0x9F1C). ME rolls; paperwork-watch arms on packet filing."
            case .paperwork:     return "Paperwork filed and POD watch armed. POD-ink fires when receiver co-signs."
            case .closedSeal:    return "Chain sealed. POD archived to BH-7C3A, ME wallet credited NET-30. Backhaul echo fully closed."
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

// MARK: - Screens (SH256-SH260)

struct ShipperBackhaulDockedLoadingScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperBackhaulEchoCloseShell(theme: theme) { ShipperBackhaulEchoCloseBody(loadId: loadId, kind: .dockedLoading) } }
}
struct ShipperBackhaulBOLPreSignScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperBackhaulEchoCloseShell(theme: theme) { ShipperBackhaulEchoCloseBody(loadId: loadId, kind: .bolPreSign) } }
}
struct ShipperBackhaulBOLSignedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperBackhaulEchoCloseShell(theme: theme) { ShipperBackhaulEchoCloseBody(loadId: loadId, kind: .bolSigned) } }
}
struct ShipperBackhaulPaperworkScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperBackhaulEchoCloseShell(theme: theme) { ShipperBackhaulEchoCloseBody(loadId: loadId, kind: .paperwork) } }
}
struct ShipperBackhaulClosedSealScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { ShipperBackhaulEchoCloseShell(theme: theme) { ShipperBackhaulEchoCloseBody(loadId: loadId, kind: .closedSeal) } }
}

// MARK: - Previews

#Preview("SH256 Dock · Dark")     { ShipperBackhaulDockedLoadingScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("SH257 BOL Pre · Light") { ShipperBackhaulBOLPreSignScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("SH258 BOL Sign · Dark") { ShipperBackhaulBOLSignedScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("SH259 Paper · Light")   { ShipperBackhaulPaperworkScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("SH260 Seal · Dark")     { ShipperBackhaulClosedSealScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
