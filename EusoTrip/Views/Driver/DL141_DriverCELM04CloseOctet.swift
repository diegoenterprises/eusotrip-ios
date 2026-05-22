//
//  DL141_DriverCELM04CloseOctet.swift
//  EusoTrip — Driver · CEL M-04 close octet (DL141-DL148).
//
//  Pixel-match to:
//    141 Driver Pickup On-Site Cel M04        (§386 · 1/5)
//    142 Driver Pickup At-Dock CEL M04        (§390 · 2/5)
//    143 Driver Pickup Loading CEL M04        (§391 · 3/5)
//    144 Driver Pickup Bol Sign CEL M04       (§392 · 4/5)
//    145 Driver Pickup Departed CEL M04       (§393 · 5/5)
//    146 Driver In Transit CEL M04            (§394 · Rolling I-85 SE)
//    147 Driver At Delivery Arrival CEL M04   (§398 · On-Site CLT Newell)
//    148 Driver POD Sign Unload CEL M04       (§402 · POD Signed)
//
//  Closes the full CEL M-04 chain (DL126 → DL148). Single bundled file.
//  All 8 share `CELCloseBody`. Body reads `loads.getById`. Bottom nav
//  frozen.
//

import SwiftUI

private struct CMCLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let rate: String?
}

enum CELCloseKind: String {
    case onSite, atDock, loading, bolSign, departed, inTransit, atDelivery, podSigned
}

private struct CCConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let stagePill: String
    let chainPill: String
}

private extension CELCloseKind {
    var config: CCConfig {
        switch self {
        case .onSite:
            return .init(eyebrow: "DRIVER · TRIPS · PICKUP · ON-SITE · CEL · M-04",
                         citation: "§386 · PICKUP ON-SITE · 1/5 · DOCK 4A",
                         title: "On-site · dock 4A",
                         subhead: "ON-SITE · DOCK 4A · gated in 0:00 ago",
                         stagePill: "CEL · LD-M-04 · gated in 0:00 ago · pickup window 08:00 – 10:00 EDT",
                         chainPill: "LD-M-04 · ATL West Caswell DC · JR gated in · NC ops · DU shipper")
        case .atDock:
            return .init(eyebrow: "DRIVER · TRIPS · PICKUP · AT-DOCK · CEL · M-04",
                         citation: "§390 · PICKUP AT-DOCK · 2/5 · DOCK 4A",
                         title: "At dock 4A",
                         subhead: "AT-DOCK · DOCK 4A · dwell 0:12",
                         stagePill: "CEL · LD-M-04 · backed in 0:00 ago · dwell 0:12 · pickup window 08:00 – 10:00 EDT",
                         chainPill: "LD-M-04 · ATL West Caswell DC · JR backed in · NC ops · DU shipper")
        case .loading:
            return .init(eyebrow: "DRIVER · TRIPS · PICKUP · LOADING · CEL · M-04",
                         citation: "§391 · PICKUP LOADING · 3/5 · DOCK 4A",
                         title: "Loading dock 4A",
                         subhead: "LOADING · DOCK 4A · dwell 0:24",
                         stagePill: "CEL · LD-M-04 · loading commenced 0:06 ago · dwell 0:24 · pickup window 08:00 – 10:00 EDT",
                         chainPill: "LD-M-04 · forklift active · JR observing · NC ops · DU shipper")
        case .bolSign:
            return .init(eyebrow: "DRIVER · TRIPS · PICKUP · BOL-SIGN · CEL · M-04",
                         citation: "§392 · PICKUP BOL-SIGN · 4/5 · DOCK 4A",
                         title: "Sign the BOL",
                         subhead: "BOL-SIGN · DOCK 4A · dwell 0:34",
                         stagePill: "CEL · LD-M-04 · loaded + sealed · dwell 0:34 · BOL ready to sign · pickup window 08:00 – 10:00 EDT",
                         chainPill: "LD-M-04 · ATL West Caswell DC · JR signs BOL · gradient ink · DU shipper")
        case .departed:
            return .init(eyebrow: "DRIVER · TRIPS · TRANSIT · DEPARTED · CEL · M-04",
                         citation: "§393 · TRANSIT DEPARTED · 5/5 · ROLLING",
                         title: "In transit",
                         subhead: "DEPARTED · ROLLING · 245 mi to CLT Newell",
                         stagePill: "CEL · LD-M-04 · departed dock 4A · in_transit · 245 mi to CLT Newell · ETA 12:46 EDT",
                         chainPill: "LD-M-04 · ATL West Caswell DC · gate-out cleared · JR rolling · NC ops · DU shipper")
        case .inTransit:
            return .init(eyebrow: "DRIVER · TRIPS · TRANSIT · ROLLING · CEL · M-04",
                         citation: "§394 · IN TRANSIT · ROLLING · I-85 SE",
                         title: "On the road",
                         subhead: "ROLLING · I-85 SE · ETA 12:44 EDT",
                         stagePill: "CEL · LD-M-04 · rolling I-85 SE · in_transit · 199 mi to CLT Newell · ETA 12:44 EDT",
                         chainPill: "LD-M-04 · I-85 SE · in_transit holds · HOS driving 10:14 · DU shipper")
        case .atDelivery:
            return .init(eyebrow: "DRIVER · TRIPS · DELIVERY · ON-SITE · CEL · M-04",
                         citation: "§398 · AT DELIVERY · ARRIVED · CLT NEWELL",
                         title: "At delivery",
                         subhead: "ON-SITE · CLT NEWELL · appt 14:00 EDT",
                         stagePill: "CEL · LD-M-04 · arrived CLT Newell · at_delivery · appt 14:00 EDT · on-time",
                         chainPill: "LD-M-04 · CLT Newell Receiving · JR arrived · early · NC ops · DU shipper")
        case .podSigned:
            return .init(eyebrow: "DRIVER · TRIPS · PAPERWORK · POD SIGNED · CEL · M-04",
                         citation: "§402 · PAPERWORK · POD SIGNED · CLT NEWELL",
                         title: "POD signed",
                         subhead: "POD SIGNED · CLT · delivered FIRED",
                         stagePill: "CEL · LD-M-04 · unload complete · delivered · POD 13:34 EDT · early",
                         chainPill: "LD-M-04 · delivered FIRED · ring rolled · pod_pending → DU · HOS on_duty")
        }
    }
}

private struct CELCloseShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Trips", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct CELCloseBody: View {
    let loadId: String
    let kind: CELCloseKind

    @Environment(\.palette) private var palette
    @State private var load: CMCLoadCtx?

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
                Text(c.stagePill).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                if let l = load {
                    Text("\(l.loadNumber ?? "LD-M-04") · \(l.pickupCity ?? "ATL") → \(l.destCity ?? "CLT")")
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

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("JR").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("CEL · JR · driver").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("Carolina Express Logistics · MC-712 944 · Naomi Chen dispatcher · DU shipper").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .onSite:
                return [
                    ("DOCK",   "4A",                 "gated in · 0:00",      .orange),
                    ("WINDOW", "08:00-10:00",          "EDT pickup",         .blue),
                    ("PAYOUT", "$1,610",                "CEL margin",        .green),
                    ("STATE",  "ON-SITE",                "§386 · 1/5",       .green),
                ]
            case .atDock:
                return [
                    ("DOCK",   "4A",                       "BACKED IN",      .orange),
                    ("DWELL",  "0:12",                       "within free",  .green),
                    ("PAYOUT", "$1,610",                       "LOCKED",     .green),
                    ("STATE",  "AT-DOCK",                       "§390 · 2/5", .blue),
                ]
            case .loading:
                return [
                    ("DOCK",   "4A",                              "loading active", .orange),
                    ("DWELL",  "0:24",                              "within free",  .green),
                    ("LOAD",   "STARTED",                            "0:06 ago",    .blue),
                    ("STATE",  "LOADING",                              "§391 · 3/5", .blue),
                ]
            case .bolSign:
                return [
                    ("STATE",  "BOL-SIGN",                              "§392 · 4/5",  .green),
                    ("DWELL",  "0:34",                                    "within free", .green),
                    ("STATUS", "LOADED + SEALED",                          "ready to sign", .green),
                    ("PAYOUT", "$1,610",                                    "LOCKED",     .green),
                ]
            case .departed:
                return [
                    ("STATE",  "DEPARTED",                                    "§393 · 5/5",  .green),
                    ("DIST",   "245 mi",                                       "to CLT Newell", .blue),
                    ("ETA",    "12:46",                                         "EDT",        .blue),
                    ("PAYOUT", "$1,610",                                          "LOCKED",   .green),
                ]
            case .inTransit:
                return [
                    ("ROUTE",  "I-85 SE",                                         "rolling",   .blue),
                    ("DIST",   "199 mi",                                           "to CLT",  .blue),
                    ("ETA",    "12:44",                                              "EDT",   .blue),
                    ("HOS",    "10:14",                                                "driving · clean", .green),
                ]
            case .atDelivery:
                return [
                    ("STATE",  "ARRIVED",                                                "§398 · early",     .green),
                    ("APPT",   "14:00",                                                    "EDT · on-time",  .green),
                    ("RECV",   "CLT NEWELL",                                                  "Receiving",   .blue),
                    ("PAYOUT", "$1,610",                                                        "LOCKED",   .green),
                ]
            case .podSigned:
                return [
                    ("POD",    "SIGNED",                                                          "§402 · CLT",    .green),
                    ("DELIV",  "13:34",                                                            "EDT · early",  .green),
                    ("CHAIN",  "FIRED",                                                              "ring rolled · pod_pending → DU", .green),
                    ("PAYOUT", "$1,610",                                                                "release queued",  .green),
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
            case .onSite:     return "Gated in at dock 4A. Pickup window 08:00-10:00 EDT — back to the dock when receiver waves."
            case .atDock:     return "Backed in at 4A. Forklift will arrive within free-dwell; loading-state arms on first pallet."
            case .loading:    return "Loading commenced. Watch dwell against the 2h free window; ESang nudges if it threatens to spill."
            case .bolSign:    return "Loaded and sealed. Tap to sign BOL — gradient ink commits the pickup chain."
            case .departed:   return "Gate-out cleared. 245 mi long-haul leg begins; ETA holds 12:46 EDT to CLT Newell."
            case .inTransit:  return "Rolling I-85 SE with 199 mi left. ESang nudges if ETA drifts >10 min vs 12:44 target."
            case .atDelivery: return "Arrived CLT Newell at 12:43 — 17 min early. Receiver will dock-in for unload."
            case .podSigned:  return "POD signed at 13:34, delivered fired. Ring rolls to DU; payout release queues next."
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

// MARK: - Screens (DL141-DL148)

struct DriverCELM04OnSiteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELCloseShell(theme: theme) { CELCloseBody(loadId: loadId, kind: .onSite) } }
}
struct DriverCELM04AtDockScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELCloseShell(theme: theme) { CELCloseBody(loadId: loadId, kind: .atDock) } }
}
struct DriverCELM04LoadingScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELCloseShell(theme: theme) { CELCloseBody(loadId: loadId, kind: .loading) } }
}
struct DriverCELM04BOLSignScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELCloseShell(theme: theme) { CELCloseBody(loadId: loadId, kind: .bolSign) } }
}
struct DriverCELM04DepartedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELCloseShell(theme: theme) { CELCloseBody(loadId: loadId, kind: .departed) } }
}
struct DriverCELM04InTransitScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELCloseShell(theme: theme) { CELCloseBody(loadId: loadId, kind: .inTransit) } }
}
struct DriverCELM04AtDeliveryScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELCloseShell(theme: theme) { CELCloseBody(loadId: loadId, kind: .atDelivery) } }
}
struct DriverCELM04PODSignedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELCloseShell(theme: theme) { CELCloseBody(loadId: loadId, kind: .podSigned) } }
}

// MARK: - Previews

#Preview("DL141 OnSite · Dark")   { DriverCELM04OnSiteScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL142 AtDock · Light")  { DriverCELM04AtDockScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL143 Loading · Dark")  { DriverCELM04LoadingScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL144 BOL · Light")     { DriverCELM04BOLSignScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL145 Depart · Dark")   { DriverCELM04DepartedScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL146 Transit · Light") { DriverCELM04InTransitScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL147 Arrive · Dark")   { DriverCELM04AtDeliveryScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL148 POD · Light")     { DriverCELM04PODSignedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
