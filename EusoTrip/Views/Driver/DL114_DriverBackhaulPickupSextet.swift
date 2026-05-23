//
//  DL114_DriverBackhaulPickupSextet.swift
//  EusoTrip — Driver · Backhaul-pickup sextet (DL114-DL119).
//
//  Pixel-match to:
//    114 Driver DVIR Composite S13 S14 Acked Pickup Roll
//    115 Driver Pickup Loaded Departed
//    116 Driver Approaching Destination
//    117 Driver At Delivery
//    118 Driver Docked Loading
//    119 Driver Loading In Progress
//
//  Closes the Driver pretrip DVIR with the S13+S14 composite at 114,
//  then transitions through pickup-departed, approach, at-delivery,
//  docked-loading, loading-in-progress. All 6 share
//  `BHPickupBody` parameterized by `BHPickupKind`. Body reads
//  `loads.getById`. Bottom nav frozen.
//

import SwiftUI

private struct BHPLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let rate: String?
    let distance: Double?
}

enum BHPickupKind: String {
    case dvirComplete, loadedDeparted, approaching, atDelivery, dockedLoading, loadingInProgress
}

private struct BPConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let stagePill: String
    let chainPill: String
}

private extension BHPickupKind {
    var config: BPConfig {
        switch self {
        case .dvirComplete:
            return .init(eyebrow: "DRIVER · TRIPS · BACKHAUL · DVIR · COMPLETE",
                         citation: "§320 · COMPOSITE S13-S14 + PICKUP ROLL · 23/N · DVIR COMPLETE",
                         title: "DVIR complete · pickup",
                         subhead: "COMPLETE · 14/14 sections",
                         stagePill: "Aurora · session DVIR-BH7C3A-09F1 · 14/14 sections · composite S13 + S14 · ON-SITE armed at dock 7B",
                         chainPill: "LD-BH7C3A · PHX-LA · PICKUP · DVIR 14/14 · ME drives · DU parent-chain co-anchor · ON-SITE armed")
        case .loadedDeparted:
            return .init(eyebrow: "DRIVER · TRIPS · BACKHAUL · IN-TRANSIT · 1/4",
                         citation: "§324 · LOADED + DEPARTED · 27/N · 1/4 QUARTET OPEN",
                         title: "Loaded · in transit",
                         subhead: "LOADED DEPARTED · 0:08 ago",
                         stagePill: "ME loaded 12/12 sealed · BOL signed · departed dock 7B · 0:08 ago",
                         chainPill: "LD-BH7C3A · PHX-LA · IN-TRANSIT · 12/12 pallets sealed · ME drives · ETA 06:24 MST")
        case .approaching:
            return .init(eyebrow: "DRIVER · TRIPS · BACKHAUL · DELIVERY · 1/4",
                         citation: "§328 · APPROACHING · 31/N · 1/4 QUARTET OPEN",
                         title: "Approaching · Naturipe LA",
                         subhead: "APPROACHING · 30 mi to RDC",
                         stagePill: "ME drives I-10 WB · 30 mi to RDC · ETA 06:24 MST · 0:30 left · HOS 01:46 / 11h",
                         chainPill: "LD-BH7C3A · I-10 WB · 30 mi to Naturipe LA RDC · ME drives · ETA 06:24 MST · 0:30 left")
        case .atDelivery:
            return .init(eyebrow: "DRIVER · TRIPS · BACKHAUL · AT-DELIVERY",
                         citation: "§332 · INNER-RING 0.5 MI CROSSED · 35/N · SUB-AXIS 1/N",
                         title: "At Delivery · Naturipe LA",
                         subhead: "AT DELIVERY · DOCK 7B · ON TIME",
                         stagePill: "ME at Naturipe RDC · gate inbound · DOCK 7B · ETA 06:24 MST · ON TIME · HOS 02:14 / 11h",
                         chainPill: "LD-BH7C3A · gate-in armed · DOCK 7B pre-assigned · queue depth 0 · ETA 06:24 MST · ON TIME")
        case .dockedLoading:
            return .init(eyebrow: "DRIVER · TRIPS · BACKHAUL · DOCKED-LOADING",
                         citation: "§336 · BACKED IN BAY 7B · 39/N · SUB-AXIS 1/N OPEN",
                         title: "Docked · Loading bay 7B",
                         subhead: "DOCKED · LOADING · 12/72",
                         stagePill: "ME backed in 0:09 ago · forklift active · pallets 12/72 · DEPART 06:42 MST in 0:24 · HOS 02:30 / 8h 30m",
                         chainPill: "LD-BH7C3A · forklift OXN-FL-04 active · pallets 12/72 · 4 ppm · DEPART 06:42 MST · 0:24 left")
        case .loadingInProgress:
            return .init(eyebrow: "DRIVER · TRIPS · BACKHAUL · LOADING-IN-PROGRESS",
                         citation: "§340 · IN-FLIGHT TICK 1 · 42/N PRESERVED · SUB-AXIS 4/N CLOSED",
                         title: "Loading 32/72 · bay 7B",
                         subhead: "LOADING · IN PROGRESS · 4 ppm",
                         stagePill: "ME forklift active · 4 ppm · 40 pallets left · 10 min ETA · DEPART 06:42 MST in 0:19 · HOS 02:35 / 8h 25m",
                         chainPill: "LD-BH7C3A · forklift OXN-FL-04 holds 4 ppm · pallets 32/72 · 40 left · 10 min ETA · DEPART 06:42 MST · 0:19 left")
        }
    }
}

private struct BHPickupShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: DriverTab.home.label,  systemImage: DriverTab.home.systemImage,  isCurrent: false),
                          NavSlot(label: DriverTab.trips.label, systemImage: DriverTab.trips.systemImage, isCurrent: true)],
                trailing: [NavSlot(label: DriverTab.wallet.label, systemImage: DriverTab.wallet.systemImage, isCurrent: false),
                           NavSlot(label: DriverTab.me.label,     systemImage: DriverTab.me.systemImage,     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct BHPickupBody: View {
    let loadId: String
    let kind: BHPickupKind

    @Environment(\.palette) private var palette
    @State private var load: BHPLoadCtx?

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
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

    private func header(_ c: BPConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: BPConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.stagePill).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                if let l = load {
                    Text("\(l.loadNumber ?? "LD-BH7C3A") · \(l.pickupCity ?? "PHX") → \(l.destCity ?? "LA")")
                        .font(.caption2).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func chainPill(_ c: BPConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("DISPATCH CHAIN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
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
                    Text("USDOT 3 482 119 · MC-942 008 · LD-BH7C3A backhaul").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .dvirComplete:
                return [
                    ("DVIR",    "14/14",                            "COMPLETE · sealed",     .green),
                    ("STAGE",   "PICKUP ROLL",                       "§320 · armed",          .green),
                    ("DOCK",    "7B",                                  "ON-SITE armed",       .blue),
                    ("PAYOUT",  "$\(load?.rate ?? "2,128")",            "NET-30 LOCKED",      .green),
                ]
            case .loadedDeparted:
                return [
                    ("PALLETS", "12/12",                                "SEALED · BOL signed", .green),
                    ("ETA",     "06:24",                                  "MST · 2h 16m",     .blue),
                    ("DEPART",  "0:08",                                    "ago · dock 7B",   .green),
                    ("QUARTET", "1/4",                                       "§324 OPEN",     .blue),
                ]
            case .approaching:
                return [
                    ("DIST",    "30 mi",                                    "to RDC",          .blue),
                    ("ETA",     "06:24",                                      "MST · 0:30 left", .blue),
                    ("HOS",     "01:46",                                       "/ 11h clean",  .green),
                    ("ROUTE",   "I-10 WB",                                       "ME driving",  .blue),
                ]
            case .atDelivery:
                return [
                    ("DOCK",    "7B",                                            "pre-assigned · armed", .orange),
                    ("ETA",     "06:24",                                            "MST · ON TIME",      .green),
                    ("QUEUE",   "0",                                                  "depth · ahead",    .green),
                    ("HOS",     "02:14",                                                "/ 11h clean",    .green),
                ]
            case .dockedLoading:
                return [
                    ("BAY",     "7B",                                                  "BACKED IN · 0:09",  .orange),
                    ("PALLETS", "12/72",                                                 "4 ppm · OXN-FL-04", .blue),
                    ("DEPART",  "06:42",                                                   "MST · 0:24 left", .blue),
                    ("HOS",     "02:30",                                                     "/ 8h 30m",      .green),
                ]
            case .loadingInProgress:
                return [
                    ("PALLETS", "32/72",                                                     "44% loaded",     .blue),
                    ("REMAIN",  "40",                                                          "pallets · 10 min ETA", .blue),
                    ("DEPART",  "06:42",                                                          "MST · 0:19 left",     .blue),
                    ("FORKLIFT","OXN-FL-04",                                                      "4 ppm steady",        .green),
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
            case .dvirComplete:      return "DVIR closed at 14/14 with the S13+S14 composite. ON-SITE armed at dock 7B; pickup roll begins on gate-in."
            case .loadedDeparted:    return "Loaded and rolling. 12/12 pallets sealed, BOL signed. Long-haul leg holds 372mi to LA."
            case .approaching:       return "30 mi to Naturipe LA RDC. Inner-ring 0.5 mi crosses at the gate; gate-in armed on entry."
            case .atDelivery:        return "Gate inbound to DOCK 7B. Queue is 0 ahead — back in when receiver waves you to plate."
            case .dockedLoading:     return "Backed into bay 7B 0:09 ago. Forklift OXN-FL-04 active at 4 ppm; depart at 06:42 MST."
            case .loadingInProgress: return "32/72 loaded, 40 left. Forklift cadence steady at 4 ppm — on track to depart in 0:19."
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

// MARK: - Screens (DL114-DL119)

struct DriverDVIRCompleteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHPickupShell(theme: theme) { BHPickupBody(loadId: loadId, kind: .dvirComplete) } }
}
struct DriverLoadedDepartedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHPickupShell(theme: theme) { BHPickupBody(loadId: loadId, kind: .loadedDeparted) } }
}
struct DriverApproachingDestinationScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHPickupShell(theme: theme) { BHPickupBody(loadId: loadId, kind: .approaching) } }
}
struct DriverAtDeliveryBHScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHPickupShell(theme: theme) { BHPickupBody(loadId: loadId, kind: .atDelivery) } }
}
struct DriverDockedLoadingScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHPickupShell(theme: theme) { BHPickupBody(loadId: loadId, kind: .dockedLoading) } }
}
struct DriverLoadingInProgressScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHPickupShell(theme: theme) { BHPickupBody(loadId: loadId, kind: .loadingInProgress) } }
}

// MARK: - Previews

#Preview("DL114 DVIR · Dark")     { DriverDVIRCompleteScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL115 Departed · Light"){ DriverLoadedDepartedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL116 Approach · Dark") { DriverApproachingDestinationScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL117 AtDel · Light")   { DriverAtDeliveryBHScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL118 Docked · Dark")   { DriverDockedLoadingScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL119 Loading · Light") { DriverLoadingInProgressScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
