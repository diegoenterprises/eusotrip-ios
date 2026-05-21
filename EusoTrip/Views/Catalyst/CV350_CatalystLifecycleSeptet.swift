//
//  CV350_CatalystLifecycleSeptet.swift
//  EusoTrip — Catalyst · Outbound lifecycle septet (CV350-CV356).
//
//  Pixel-match to:
//    350 Catalyst At Gate
//    351 Catalyst At Dock
//    352 Catalyst Departing
//    353 Catalyst Pre-Delivery
//    354 Catalyst At Delivery
//    355 Catalyst POD Receipt
//    356 Catalyst Load Closed
//
//  Mirrors DL094-DL100 from the Catalyst vantage. All 7 share
//  `CatalystLifecycleBody` parameterized by `CatalystLifecycleKind`.
//  Body reads `loads.getById` for live shipment context. Bottom nav
//  frozen (Catalyst: Home / Fleet / Wallet / Me).
//

import SwiftUI

private struct CLLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let trailerType: String?
    let cargoType: String?
    let rate: String?
    let palletCount: Int?
    let temperatureF: Double?
    let dockNumber: String?
    let podCertId: String?
    let deliveryDate: String?
}

enum CatalystLifecycleKind: String {
    case atGate, atDock, departing, preDelivery, atDelivery, podReceipt, loadClosed
}

private struct CatalystLifecycleConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let receivablePill: String
}

private extension CatalystLifecycleKind {
    var config: CatalystLifecycleConfig {
        switch self {
        case .atGate:
            return .init(eyebrow: "CATALYST · OUTBOUND · IN TRANSIT · AT GATE",
                         citation: "§278 · WITHIN-TRACK THIRD-PORT 3/3 · TRIGGER CLOSED",
                         title: "Driver at the gate",
                         subhead: "DOCK 14 · DWELL 0:00 · LIVE",
                         pillCopy: "Naturipe LA RDC · ME at Gate 1 · 0:00 ago · 2 ahead",
                         receivablePill: "§11.4 RECEIVABLE FROM EUSORONE · NET-30 · DETENTION REIMB ARMED")
        case .atDock:
            return .init(eyebrow: "CATALYST · OUTBOUND · IN TRANSIT · AT DOCK",
                         citation: "§281 · WITHIN-TRACK FOURTH-PORT 3/3 · TRIGGER CLOSED",
                         title: "Driver loading at dock",
                         subhead: "DOCK 14 · DWELL 0:08 · 18/72",
                         pillCopy: "Naturipe LA RDC · ME at Dock 14 · 25% loaded · reefer 35°F",
                         receivablePill: "§11.4 RECEIVABLE FROM EUSORONE · NET-30 · ATTESTATION ARMING")
        case .departing:
            return .init(eyebrow: "CATALYST · OUTBOUND · IN TRANSIT · DEPARTING",
                         citation: "§285 · WITHIN-TRACK FIFTH-PORT 3/3 · TRIGGER CLOSED",
                         title: "Driver rolling to Phoenix",
                         subhead: "I-10 EAST · ETA 5H 28M",
                         pillCopy: "I-10 EAST · 372mi · ETA 5h 28m · BOL #BOL-7C3A signed",
                         receivablePill: "§11.4 RECEIVABLE FROM EUSORONE · NET-30 · POD-ARMING ON DELIVERY")
        case .preDelivery:
            return .init(eyebrow: "CATALYST · OUTBOUND · IN TRANSIT · APPROACHING DELIVERY",
                         citation: "§288 · WITHIN-TRACK SIXTH-PORT 3/3 · TRIGGER CLOSED",
                         title: "Approaching Phoenix gate",
                         subhead: "LOOP 202 W · ETA 22M",
                         pillCopy: "LOOP 202 W · 18mi to gate · ETA 22m · DOCK 7B pre-assigned · BOL at-receiving",
                         receivablePill: "§11.4 RECEIVABLE FROM EUSORONE · POD-ARMING · NET-30 DOWNSTREAM")
        case .atDelivery:
            return .init(eyebrow: "CATALYST · OUTBOUND · DELIVERY · AT DOCK",
                         citation: "§291 · WITHIN-TRACK SEVENTH-PORT 3/3 · TRIGGER CLOSED",
                         title: "My driver · at delivery",
                         subhead: "DOCK 7B IN · POD-INK QUEUED",
                         pillCopy: "DOCK 7B receiving bay · BOL co-sign begun · 36°F seal-at-arrival · POD-ink one tap",
                         receivablePill: "§11.4 RECEIVABLE READY · POD-INK QUEUED · CHAIN COMPLETE · NET-30 DOWNSTREAM")
        case .podReceipt:
            return .init(eyebrow: "CATALYST · OUTBOUND · PAPERWORK · POD RECEIPT",
                         citation: "§294 · WITHIN-TRACK EIGHTH-PORT 3/3 · TRIGGER CLOSED",
                         title: "POD chain · closed",
                         subhead: "POD CERT · ISSUED · NET-30",
                         pillCopy: "ePOD CERT ISSUED · 72/72 reconciled · DU timestamped · NET-30 wired · payout-advance armed",
                         receivablePill: "§11.4 RECEIVABLE RELEASED · POD CERT ISSUED · NET-30 WIRED · PAYOUT-ADVANCE 1.5%/5D")
        case .loadClosed:
            return .init(eyebrow: "CATALYST · DISPATCH · CLOSED · LOAD CLOSED",
                         citation: "§296 · WITHIN-TRACK NINTH-PORT 3/3 · TRIGGER CLOSED",
                         title: "Load closed · backhaul armed",
                         subhead: "AURORA · ROLLUP · CONFIRMED",
                         pillCopy: "ROLLUP CONFIRMED · CARRIER $211.75 NETTED · ME PAYOUT $2,649.25 STAGED · BACKHAUL TENDER READY",
                         receivablePill: "§295 ME PAYOUT STAGED · §296 CARRIER NETTED · BACKHAUL PHX-LA ARMED · Q2 +1")
        }
    }
}

private struct CatalystLifecycleShell<Content: View>: View {
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

private struct CatalystLifecycleBody: View {
    let loadId: String
    let kind: CatalystLifecycleKind

    @Environment(\.palette) private var palette
    @State private var load: CLLoadCtx?

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                receivablePill(c)
                counterparty
                kpiGrid
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private func header(_ c: CatalystLifecycleConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CatalystLifecycleConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                if let l = load {
                    Text("\(l.loadNumber ?? "LD-\(l.id ?? 0)") · \(l.pickupCity ?? "—") → \(l.destCity ?? "—") · \(l.trailerType ?? "—")")
                        .font(.caption2).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func receivablePill(_ c: CatalystLifecycleConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("RECEIVABLE / DOWNSTREAM").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.receivablePill).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var counterparty: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("DU").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eusorone Technologies · Diego Usoro · founder").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("companyId 1 · EIN 87-3104952 · NET-30 receivable · counter-party").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let l = load
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .atGate:
                return [
                    ("DOCK",     l?.dockNumber ?? "14",           "bay live · DWELL 0:00",      .blue),
                    ("PALLETS",  "\(l?.palletCount ?? 72)",        "ME to load",                .blue),
                    ("REEFER",   tempCL(l?.temperatureF, fallback: 35), "33-38°F window",     .green),
                    ("AHEAD",    "2",                              "trucks before ME",           .orange),
                ]
            case .atDock:
                return [
                    ("DOCK",     l?.dockNumber ?? "14",           "IN · loading",               .orange),
                    ("LOADED",   "18/72",                          "25% · live",                 .blue),
                    ("REEFER",   tempCL(l?.temperatureF, fallback: 35), "in-range · live",     .green),
                    ("DWELL",    "0:08",                           "within 2h free",             .green),
                ]
            case .departing:
                return [
                    ("ROUTE",    "I-10 E",                         "372mi to Phoenix",          .blue),
                    ("ETA",      "5h 28m",                          "to dock",                    .blue),
                    ("BOL",      "SIGNED",                          "#BOL-7C3A",                 .green),
                    ("STATUS",   "DEPARTED",                        "gate-out cleared",           .green),
                ]
            case .preDelivery:
                return [
                    ("ROUTE",    "LOOP 202 W",                     "18mi to gate",               .blue),
                    ("ETA",      "22m",                              "to receiver",              .blue),
                    ("DOCK",     "7B",                                "pre-assigned",            .orange),
                    ("BOL",      "AT-RECV",                            "co-sign queued",         .blue),
                ]
            case .atDelivery:
                return [
                    ("DOCK",     "7B",                                "IN · receiving",          .orange),
                    ("BOL",      "CO-SIGN",                           "TR signing now",          .green),
                    ("REEFER",   tempCL(l?.temperatureF, fallback: 36),"seal-at-arrival",       .green),
                    ("ETA",      "0m",                                "ARRIVED · OTA",          .green),
                ]
            case .podReceipt:
                return [
                    ("PALLETS",  "72/72",                              "RECONCILED · sealed",   .green),
                    ("POD CERT", "ISSUED",                              l?.podCertId ?? "ePOD chain sealed", .green),
                    ("PAY",      "NET-30",                              "wired",                .green),
                    ("ADVANCE",  "1.5%/5D",                              "armed",                .blue),
                ]
            case .loadClosed:
                return [
                    ("PALLETS",  "72/72",                              "FINAL · sealed",        .green),
                    ("PAYOUT",   "$\(l?.rate ?? "2,649.25")",           "ME staged · NET-30",   .green),
                    ("CARRIER",  "$211.75",                             "Aurora netted",        .green),
                    ("BACKHAUL", "ARMED",                                "PHX-LA · Q2 +1",      .blue),
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
            case .atGate:      return "Dock confirms in app. Pre-stage detention timer at 2h free; reimbursement armed via §11.4."
            case .atDock:      return "Live load on 25% progress. Watch reefer band; chain-of-custody attestation arms at seal."
            case .departing:   return "Long-haul leg begins. POD arming activates at receiver-gate; net-30 downstream wires on POD-ink."
            case .preDelivery: return "Call ahead 15 minutes out. Confirm receiver dock + paperwork access; backhaul tender pre-stages."
            case .atDelivery:  return "Receiver inspects + co-signs. POD-ink lands the chain; NET-30 downstream wires on issue."
            case .podReceipt:  return "ePOD CERT issued, NET-30 wired. Payout-advance 1.5%/5D armed — pull if cash-flow needed."
            case .loadClosed:  return "Rollup confirmed, backhaul tender ready. Approve to keep Aurora moving on the PHX-LA chain."
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

private func tempCL(_ raw: Double?, fallback: Int) -> String {
    if let raw, raw > 0 { return String(format: "%.0f°F", raw) }
    return "\(fallback)°F"
}

// MARK: - Screens (CV350-CV356)

struct CatalystAtGateScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystLifecycleShell(theme: theme) { CatalystLifecycleBody(loadId: loadId, kind: .atGate) } }
}
struct CatalystAtDockScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystLifecycleShell(theme: theme) { CatalystLifecycleBody(loadId: loadId, kind: .atDock) } }
}
struct CatalystDepartingScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystLifecycleShell(theme: theme) { CatalystLifecycleBody(loadId: loadId, kind: .departing) } }
}
struct CatalystPreDeliveryScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystLifecycleShell(theme: theme) { CatalystLifecycleBody(loadId: loadId, kind: .preDelivery) } }
}
struct CatalystAtDeliveryScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystLifecycleShell(theme: theme) { CatalystLifecycleBody(loadId: loadId, kind: .atDelivery) } }
}
struct CatalystPODReceiptScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystLifecycleShell(theme: theme) { CatalystLifecycleBody(loadId: loadId, kind: .podReceipt) } }
}
struct CatalystLoadClosedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystLifecycleShell(theme: theme) { CatalystLifecycleBody(loadId: loadId, kind: .loadClosed) } }
}

// MARK: - Previews

#Preview("CV350 Gate · Dark")       { CatalystAtGateScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV351 Dock · Light")      { CatalystAtDockScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV352 Departing · Dark")  { CatalystDepartingScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV353 PreDel · Light")    { CatalystPreDeliveryScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV354 AtDel · Dark")      { CatalystAtDeliveryScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV355 POD · Light")       { CatalystPODReceiptScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV356 Closed · Dark")     { CatalystLoadClosedScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
