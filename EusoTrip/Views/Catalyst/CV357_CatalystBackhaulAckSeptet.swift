//
//  CV357_CatalystBackhaulAckSeptet.swift
//  EusoTrip — Catalyst · Backhaul-ack septet (CV357-CV363).
//
//  Pixel-match to:
//    357 Catalyst Backhaul Tender
//    358 Catalyst Backhaul Tender Accepted
//    359 Catalyst BH Pickup Watch Armed
//    360 Catalyst BH Pickup On-Site Acked
//    361 Catalyst BH In-Transit Acked
//    362 Catalyst BH Delivery Approaching Acked
//    363 Catalyst BH At Delivery Acked
//
//  Single bundled file. All 7 share `CatalystBackhaulAckBody`
//  parameterized by `CatalystBackhaulKind`. Body reads
//  `loads.getById` for the backhaul load context. Bottom nav frozen.
//

import SwiftUI

private struct CBLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let trailerType: String?
    let rate: String?
    let dockNumber: String?
    let deliveryDate: String?
}

enum CatalystBackhaulKind: String {
    case tender, accepted, pickupWatch, onSite, inTransit, deliveryApproach, atDelivery
}

private struct CBConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let chainPill: String
}

private extension CatalystBackhaulKind {
    var config: CBConfig {
        switch self {
        case .tender:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · TENDER STAGED",
                         citation: "§298 · CATALYST BACKHAUL TENDER · CARRIER-DISPATCHED-OUTBOUND · NEXT-CHAIN 2/N",
                         title: "Backhaul tendered · awaiting accept",
                         subhead: "AURORA · MC942008 · §298 · TENDER 8m",
                         pillCopy: "Tender STAGED 0:00 ago · ME LIVE post-reset · CARRIER margin $172 preview · expires 8m",
                         chainPill: "§297 ME TENDER RECEIVED · §298 STAGED-AWAITING-ACCEPT · §295.3 POST 10H RESET")
        case .accepted:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · ACCEPTED",
                         citation: "§303 · CATALYST BACKHAUL ACCEPTED · CARRIER-DISPATCHED · NEXT-CHAIN 6/N",
                         title: "Tender accepted by ME",
                         subhead: "AURORA · MC942008 · §303 · AWARDED",
                         pillCopy: "Aurora dispatch locked · ME accepted 0:00 ago · 4:00 left on window · DVIR pending",
                         chainPill: "§297 RECEIVED · §298 STAGED · §302 ACCEPTED 0:00 AGO · §303 DISPATCH LOCKED")
        case .pickupWatch:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · PICKUP-WATCH",
                         citation: "§307 · CATALYST PICKUP-WATCH-ARMED · CARRIER-DISPATCHED · NEXT-CHAIN 10/N",
                         title: "Pickup watch armed for ME",
                         subhead: "AURORA · MC942008 · §307 · WATCH ARMED",
                         pillCopy: "Aurora · DVIR 1/14 IN PROGRESS · pickup opens 03:30 MST · ping -30 · in 13h 42m",
                         chainPill: "§302 ACCEPTED · §303 DISPATCH LOCKED · §306 DVIR 1/14 · §307 WATCH ARMED 0:00 AGO")
        case .onSite:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · PICKUP",
                         citation: "§321 · CATALYST PICKUP-ON-SITE-ACKED · QUARTET 2/4 · NEXT-CHAIN 24/N",
                         title: "ME on-site at dock 7B",
                         subhead: "AURORA · MC942008 · §321 · ON-SITE ACKED",
                         pillCopy: "Aurora · DVIR 14/14 COMPLETE · ME loading at PHX-WVDC dock 7B · 0:04 since on-site",
                         chainPill: "§303 DISPATCH LOCKED · §307 WATCH ARMED · §320 DVIR COMPLETE · §321 ON-SITE ACKED 0:04 AGO")
        case .inTransit:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · IN-TRANSIT",
                         citation: "§325 · CATALYST IN-TRANSIT-ACKED · QUARTET 2/4 · NEXT-CHAIN 28/N",
                         title: "ME in transit · 372 mi to LA",
                         subhead: "AURORA · MC942008 · §325 · IN-TRANSIT ACKED",
                         pillCopy: "Aurora · 12/12 sealed · ME driving I-10 WB · ETA 06:24 MST · 0:04 since IN-TRANSIT ack",
                         chainPill: "§321 ON-SITE · §322 LOADING · §324 SEAL CONFIRMED · §325 IN-TRANSIT ACKED 0:04 AGO")
        case .deliveryApproach:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · DELIVERY · 2/4",
                         citation: "§329 · CATALYST DELIVERY-ACKED · QUARTET 2/4 · NEXT-CHAIN 32/N",
                         title: "ME approaching · 28 mi to LA",
                         subhead: "AURORA · MC942008 · §329 · DELIVERY ACKED",
                         pillCopy: "Aurora · 12/12 sealed · ME 28 mi from RDC · ETA 06:24 MST · 0:02 since approach ack",
                         chainPill: "§325 IN-TRANSIT · §327 GATE-WATCH ARMED · §329 APPROACHING ACKED 0:02 AGO")
        case .atDelivery:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · AT-DELIVERY · 2/N",
                         citation: "§333 · CATALYST AT-DELIVERY-ACKED · SUB-AXIS 2/N · NEXT-CHAIN 36/N",
                         title: "ME at gate · DOCK 7B",
                         subhead: "AURORA · MC942008 · §333 · AT DELIVERY ACKED",
                         pillCopy: "Aurora · 12/12 sealed · ME at Naturipe RDC · DOCK 7B · 0:02 since gate-in ack",
                         chainPill: "§329 APPROACHING · §331 GATE-IN ARMED · §333 AT-DELIVERY ACKED 0:02 AGO · QUEUE 0")
        }
    }
}

private struct CatalystBackhaulShell<Content: View>: View {
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

private struct CatalystBackhaulAckBody: View {
    let loadId: String
    let kind: CatalystBackhaulKind

    @Environment(\.palette) private var palette
    @State private var load: CBLoadCtx?

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

    private func header(_ c: CBConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CBConfig) -> some View {
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

    private func chainPill(_ c: CBConfig) -> some View {
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
                    Text("USDOT 3 194 882 · AUR-MC942008 dispatch · margin $172").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .tender:
                return [
                    ("TENDER",  "8m",        "expires",                .orange),
                    ("MARGIN",  "$172",      "carrier preview",        .green),
                    ("ME",      "POST-RESET", "10h reset · live",      .green),
                    ("STATE",   "STAGED",    "awaiting accept",        .blue),
                ]
            case .accepted:
                return [
                    ("WINDOW",  "4:00",      "left on accept",         .green),
                    ("MARGIN",  "$172",      "LOCKED",                 .green),
                    ("DVIR",    "PENDING",   "opens at -60m",          .orange),
                    ("STATE",   "AWARDED",   "Aurora locked",          .green),
                ]
            case .pickupWatch:
                return [
                    ("WATCH",   "ARMED",      "ping -30",              .green),
                    ("PICKUP",  "13h 42m",     "opens 03:30 MST",      .blue),
                    ("DVIR",    "1/14",        "in progress",          .orange),
                    ("MARGIN",  "$172",        "LOCKED",                .green),
                ]
            case .onSite:
                return [
                    ("DOCK",    "7B",          "PHX-WVDC · loading",   .orange),
                    ("DVIR",    "14/14",       "COMPLETE · sealed",    .green),
                    ("ON-SITE", "0:04",        "since gate-in ack",    .blue),
                    ("MARGIN",  "$172",        "LOCKED",                .green),
                ]
            case .inTransit:
                return [
                    ("ROUTE",   "I-10 WB",     "372 mi to LA",         .blue),
                    ("ETA",     "06:24",       "MST · 2h 16m",         .blue),
                    ("SEAL",    "12/12",       "sealed in transit",    .green),
                    ("MARGIN",  "$172",        "LOCKED",                .green),
                ]
            case .deliveryApproach:
                return [
                    ("DIST",    "28 mi",       "to RDC",               .blue),
                    ("ETA",     "06:24",       "MST · 0:28 left",      .blue),
                    ("SEAL",    "12/12",       "sealed · live",        .green),
                    ("STATE",   "APPROACHING", "ack 0:02 ago",         .green),
                ]
            case .atDelivery:
                return [
                    ("DOCK",    "7B",          "GATE-IN · ME at gate", .green),
                    ("QUEUE",   "0",           "queue depth · ahead",  .green),
                    ("ETA",     "06:24",       "MST · on time",        .green),
                    ("SEAL",    "12/12",       "sealed at arrival",    .green),
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
            case .tender:           return "ME has 8 minutes to accept. If timer expires, Aurora releases tender back to the carrier pool."
            case .accepted:         return "Dispatch locked. DVIR opens 60 minutes before pickup; ESang queues pretrip on ME's watch."
            case .pickupWatch:      return "Watch armed. Pickup opens 03:30 MST; -30 ping confirms ME is en-route to PHX-WVDC."
            case .onSite:           return "ME loading at PHX-WVDC dock 7B. Seal confirmation arms IN-TRANSIT ack on gate-out."
            case .inTransit:        return "ME on I-10 WB. Long-haul leg holds 372mi to LA — watch ETA drift, ESang nudges if HOS tightens."
            case .deliveryApproach: return "Approach acked at 28mi. Confirm receiver dock + paperwork — DOCK 7B armed for gate-in."
            case .atDelivery:       return "Gate-in cleared. Receiver-bay queue is 0; POD chain arms on dock placement."
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

// MARK: - Screens (CV357-CV363)

struct CatalystBackhaulTenderScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulShell(theme: theme) { CatalystBackhaulAckBody(loadId: loadId, kind: .tender) } }
}
struct CatalystBackhaulAcceptedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulShell(theme: theme) { CatalystBackhaulAckBody(loadId: loadId, kind: .accepted) } }
}
struct CatalystBackhaulPickupWatchScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulShell(theme: theme) { CatalystBackhaulAckBody(loadId: loadId, kind: .pickupWatch) } }
}
struct CatalystBackhaulOnSiteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulShell(theme: theme) { CatalystBackhaulAckBody(loadId: loadId, kind: .onSite) } }
}
struct CatalystBackhaulInTransitScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulShell(theme: theme) { CatalystBackhaulAckBody(loadId: loadId, kind: .inTransit) } }
}
struct CatalystBackhaulDeliveryApproachScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulShell(theme: theme) { CatalystBackhaulAckBody(loadId: loadId, kind: .deliveryApproach) } }
}
struct CatalystBackhaulAtDeliveryScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulShell(theme: theme) { CatalystBackhaulAckBody(loadId: loadId, kind: .atDelivery) } }
}

// MARK: - Previews

#Preview("CV357 Tender · Dark")     { CatalystBackhaulTenderScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV358 Accepted · Light")  { CatalystBackhaulAcceptedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV359 Watch · Dark")      { CatalystBackhaulPickupWatchScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV360 OnSite · Light")    { CatalystBackhaulOnSiteScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV361 Transit · Dark")    { CatalystBackhaulInTransitScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV362 Approach · Light")  { CatalystBackhaulDeliveryApproachScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV363 AtDel · Dark")      { CatalystBackhaulAtDeliveryScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
