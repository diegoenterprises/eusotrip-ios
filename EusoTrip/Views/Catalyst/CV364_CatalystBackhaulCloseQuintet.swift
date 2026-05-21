//
//  CV364_CatalystBackhaulCloseQuintet.swift
//  EusoTrip — Catalyst · Backhaul-close quintet (CV364-CV368).
//
//  Pixel-match to:
//    364 Catalyst BH Docked Loading Acked
//    365 Catalyst BH Bol Pre Sign Acked
//    366 Catalyst BH Bol Signed Acked
//    367 Catalyst BH Paperwork Acked
//    368 Catalyst BH Closed Stage Acked
//
//  Single bundled file. All 5 share `CatalystBackhaulCloseBody`
//  parameterized by `CatalystBackhaulCloseKind`. Body reads
//  `loads.getById`. Bottom nav frozen.
//

import SwiftUI

private struct CCLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let trailerType: String?
    let rate: String?
    let palletCount: Int?
    let dockNumber: String?
    let podCertId: String?
}

enum CatalystBackhaulCloseKind: String {
    case dockedLoading, bolPreSign, bolSigned, paperwork, closedStage
}

private struct CCConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let chainPill: String
}

private extension CatalystBackhaulCloseKind {
    var config: CCConfig {
        switch self {
        case .dockedLoading:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · DOCKED-LOADING · 2/N",
                         citation: "§337 · CATALYST DOCKED-LOADING-ACKED · SUB-AXIS 2/N · NEXT-CHAIN 40/N",
                         title: "ME docked · BAY 7B",
                         subhead: "AURORA · MC942008 · §337 · DOCKED LOADING ACKED",
                         pillCopy: "Aurora · pallets 12/72 · 4 ppm · DEPART 06:42 MST · 0:24 LEFT · 0:02 since ack",
                         chainPill: "BAY 7B OCCUPIED · forklift OXN-FL-04 · pallets 12/72 · DEPART 06:42 MST")
        case .bolPreSign:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · BOL-PRE-SIGN · 2/N",
                         citation: "§344 · CATALYST BOL-PRE-SIGN-ACKED · SUB-AXIS 2/N · NEXT-CHAIN 44/N",
                         title: "ME at dock plate · BAY 7B",
                         subhead: "AURORA · MC942008 · §344 · BOL PRE-SIGN ACKED",
                         pillCopy: "Aurora · BOL DRAFT acked · pallets 72/72 LOADED · DEPART 06:42 MST · 0:04 LEFT · 0:02 since ack",
                         chainPill: "BOL packet BOL-NLR-LA-2026-05-19-BH7C3A · DRAFT acked · BOL-signed watch armed")
        case .bolSigned:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · BOL-SIGNED · 2/N",
                         citation: "§348 · CATALYST BOL-SIGNED-ACKED · SUB-AXIS 2/N · NEXT-CHAIN 48/N · VERIFIED WS ENVELOPE",
                         title: "ME at dock plate · BAY 7B",
                         subhead: "AURORA · MC942008 · §348 · BOL SIGNED ACKED",
                         pillCopy: "Aurora · BOL SIGNED acked · sig-hash 0x9F1C · DEPART 06:42 MST · CLOSING NOW · 0:02 since broadcast",
                         chainPill: "BOL doc BOL-NLR-LA-2026-05-19-BH7C3A-SIGNED · sig 0x9F1C · paperwork watch armed")
        case .paperwork:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · PAPERWORK · 2/N",
                         citation: "§352 · CATALYST PAPERWORK-ACKED · SUB-AXIS 2/N · NEXT-CHAIN 52/N · VERIFIED WS ENVELOPE",
                         title: "ME packet filed · BAY 7B",
                         subhead: "AURORA · MC942008 · §352 · PAPERWORK ACKED",
                         pillCopy: "Aurora · paperwork acked · POD watch armed · BOL filed · 0:01 since stage roll",
                         chainPill: "BOL filed BH7C3A-FILED · POD packet BH7C3A-POD · POD watch armed")
        case .closedStage:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · CLOSED · 2/N",
                         citation: "§356 · CATALYST CLOSED-ACKED · SUB-AXIS 2/N · NEXT-CHAIN 56/N · WALLET CREDITED · VERIFIED WS",
                         title: "ME chain sealed · PAYOUT $2,128",
                         subhead: "AURORA · MC942008 · §356 · CLOSED ACKED",
                         pillCopy: "Aurora · CLOSED acked · wallet credited · POD submitted · BOL filed · 0:01 since stage roll",
                         chainPill: "POD submitted BH7C3A-SUBMITTED · BOL filed BH7C3A-FILED · escrow CREDITED $2,128")
        }
    }
}

private struct CatalystBackhaulCloseShell<Content: View>: View {
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

private struct CatalystBackhaulCloseBody: View {
    let loadId: String
    let kind: CatalystBackhaulCloseKind

    @Environment(\.palette) private var palette
    @State private var load: CCLoadCtx?

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                chainPill(c)
                meRow
                kpiGrid
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private func header(_ c: CCConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CCConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                if let l = load {
                    Text("\(l.loadNumber ?? "LD-BH7C3A") · \(l.pickupCity ?? "PHX") → \(l.destCity ?? "LA") · \(l.trailerType ?? "Reefer")")
                        .font(.caption2).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func chainPill(_ c: CCConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("DISPATCH CHAIN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.chainPill).font(.caption2).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var meRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("ME").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eusotrans LLC · Michael Eusorone · solo owner-operator").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("USDOT 3 194 882 · AUR-MC942008 dispatch · LD-BH7C3A backhaul").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let pal = load?.palletCount ?? 72
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .dockedLoading:
                return [
                    ("BAY",      "7B",                           "OCCUPIED · live",         .orange),
                    ("PALLETS",  "12/\(pal)",                    "4 ppm · forklift OXN-FL-04", .blue),
                    ("DEPART",   "06:42",                          "MST · 0:24 left",        .blue),
                    ("ACK",      "0:02",                            "since ack",            .green),
                ]
            case .bolPreSign:
                return [
                    ("BAY",      "7B",                            "occupied · dock plate", .orange),
                    ("PALLETS",  "\(pal)/\(pal)",                  "LOADED · sealed",      .green),
                    ("BOL",      "DRAFT",                           "acked · signed watch", .blue),
                    ("DEPART",   "06:42",                            "MST · 0:04 left",     .blue),
                ]
            case .bolSigned:
                return [
                    ("BOL",      "SIGNED",                         "0x9F1C · verified",     .green),
                    ("PALLETS",  "\(pal)/\(pal)",                   "sealed in transit",    .green),
                    ("PAPER",    "WATCH",                            "armed",              .blue),
                    ("DEPART",   "06:42",                            "MST · closing now",    .green),
                ]
            case .paperwork:
                return [
                    ("BOL",      "FILED",                          "BH7C3A-FILED",         .green),
                    ("POD",      "PACKET",                          "BH7C3A-POD · armed",   .blue),
                    ("STATUS",   "ACKED",                            "stage roll · 0:01",   .green),
                    ("CHAIN",    "52/N",                              "next-chain port",     .blue),
                ]
            case .closedStage:
                return [
                    ("PAYOUT",   "$\(load?.rate ?? "2,128")",        "wallet credited",       .green),
                    ("POD",      "SUBMITTED",                         "BH7C3A-SUBMITTED",     .green),
                    ("BOL",      "FILED",                              "BH7C3A-FILED",         .green),
                    ("ESCROW",   "CREDITED",                            "$2,128 released",     .green),
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
            case .dockedLoading: return "Bay 7B occupied at 4 ppm. Load completes at 06:42 MST; BOL pre-sign arms on dock-plate touch."
            case .bolPreSign:    return "BOL draft acked. ME taps sign-acknowledge on dock plate; BOL-signed broadcast fires next."
            case .bolSigned:     return "BOL SIGNED + sig-hash verified. Paperwork watch armed; filing closes when POD packet uploads."
            case .paperwork:     return "Paperwork filed. POD watch is armed — POD-ink confirmation fires once receiver co-signs."
            case .closedStage:   return "Chain sealed, escrow credited $2,128. ME wallet balance updates within 30s; advance-eligible."
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

// MARK: - Screens (CV364-CV368)

struct CatalystBackhaulDockedLoadingScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulCloseShell(theme: theme) { CatalystBackhaulCloseBody(loadId: loadId, kind: .dockedLoading) } }
}
struct CatalystBackhaulBOLPreSignScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulCloseShell(theme: theme) { CatalystBackhaulCloseBody(loadId: loadId, kind: .bolPreSign) } }
}
struct CatalystBackhaulBOLSignedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulCloseShell(theme: theme) { CatalystBackhaulCloseBody(loadId: loadId, kind: .bolSigned) } }
}
struct CatalystBackhaulPaperworkScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulCloseShell(theme: theme) { CatalystBackhaulCloseBody(loadId: loadId, kind: .paperwork) } }
}
struct CatalystBackhaulClosedStageScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulCloseShell(theme: theme) { CatalystBackhaulCloseBody(loadId: loadId, kind: .closedStage) } }
}

// MARK: - Previews

#Preview("CV364 Dock · Dark")      { CatalystBackhaulDockedLoadingScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV365 BOL Pre · Light")  { CatalystBackhaulBOLPreSignScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV366 BOL Sign · Dark")  { CatalystBackhaulBOLSignedScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV367 Paper · Light")    { CatalystBackhaulPaperworkScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV368 Closed · Dark")    { CatalystBackhaulClosedStageScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
