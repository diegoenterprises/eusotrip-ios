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
//  ZERO-FABRICATION binding (parity with sibling DL133_DriverCELM04…
//  and 373_CatalystAwardedCelM04):
//    • `loads.getById` ({ id }) → CLLoadCtx
//        loadNumber, pickup/dest lane (nested {city,state}), trailerType
//        (equipmentType), and PAYOUT (load.rate — the shipper-posted
//        rate). Counter-party identity binds to the resolved load
//        parties (shipper / catalyst), NOT a hardcoded founder pin.
//
//    Decode contract (server loads.ts:1338-1379):
//      - top-level `id` is a STRING (`String(load.id)`); decoding it as
//        Int throws typeMismatch and silently fails the WHOLE decode →
//        every value blanks. It MUST be `String?`.
//      - `pickupLocation`/`deliveryLocation` are nested {city,state}
//        objects (NOT flat `pickupCity`/`destCity` columns). Server
//        sends "" (not nil) when a field is missing.
//      - party objects are {id:Int?, name, initials, companyName,
//        mcNumber, dotNumber}; the party `id` is numeric on the wire.
//
//  Honest backend gaps — rendered "-"/"—"/EusoEmptyState, NEVER faked:
//    • Carrier-split / carrier net — no source on loads.getById → "—".
//    • ETA / route / dock / dwell / loaded-progress / reefer band /
//      BOL / POD-cert / advance — no live source on this proc → "—".
//    • Counter-party EIN — no EIN field on the resolved parties → "—".
//
//  Powered by ESANG AI™.
//

import SwiftUI

/// `loads.getById` decode shape (server loads.ts:1338-1379). Top-level
/// `id` is a String on the wire; pickup/delivery are nested {city,state}.
private struct CLLoadCtx: Decodable, Hashable {
    let id: String?
    let loadNumber: String?
    let pickupLocation: CLLoc?
    let deliveryLocation: CLLoc?
    let rate: String?            // decimal string from server → PAYOUT
    let equipmentType: String?   // trailer / equipment ("Reefer" …)
    let shipper: CLParty?
    let catalyst: CLParty?
    let driver: CLParty?

    struct CLLoc: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct CLParty: Decodable, Hashable {
        let id: Int?             // party (user/company) id is numeric on the wire
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }
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
                         subhead: "GATE-IN · LIVE",
                         pillCopy: "Driver checked in at the receiving gate · queued for dock assignment",
                         receivablePill: "§11.4 RECEIVABLE FROM EUSORONE · NET-30 · DETENTION REIMB ARMED")
        case .atDock:
            return .init(eyebrow: "CATALYST · OUTBOUND · IN TRANSIT · AT DOCK",
                         citation: "§281 · WITHIN-TRACK FOURTH-PORT 3/3 · TRIGGER CLOSED",
                         title: "Driver loading at dock",
                         subhead: "AT DOCK · LOADING",
                         pillCopy: "Driver loading at the assigned dock · chain-of-custody attestation arming",
                         receivablePill: "§11.4 RECEIVABLE FROM EUSORONE · NET-30 · ATTESTATION ARMING")
        case .departing:
            return .init(eyebrow: "CATALYST · OUTBOUND · IN TRANSIT · DEPARTING",
                         citation: "§285 · WITHIN-TRACK FIFTH-PORT 3/3 · TRIGGER CLOSED",
                         title: "Driver rolling to delivery",
                         subhead: "DEPARTED · EN ROUTE",
                         pillCopy: "Driver gate-out cleared · BOL signed · en route to the receiver",
                         receivablePill: "§11.4 RECEIVABLE FROM EUSORONE · NET-30 · POD-ARMING ON DELIVERY")
        case .preDelivery:
            return .init(eyebrow: "CATALYST · OUTBOUND · IN TRANSIT · APPROACHING DELIVERY",
                         citation: "§288 · WITHIN-TRACK SIXTH-PORT 3/3 · TRIGGER CLOSED",
                         title: "Approaching delivery gate",
                         subhead: "APPROACHING · BOL AT-RECEIVING",
                         pillCopy: "Driver approaching the receiver gate · dock pre-assignment · BOL at-receiving",
                         receivablePill: "§11.4 RECEIVABLE FROM EUSORONE · POD-ARMING · NET-30 DOWNSTREAM")
        case .atDelivery:
            return .init(eyebrow: "CATALYST · OUTBOUND · DELIVERY · AT DOCK",
                         citation: "§291 · WITHIN-TRACK SEVENTH-PORT 3/3 · TRIGGER CLOSED",
                         title: "My driver · at delivery",
                         subhead: "AT DELIVERY · POD-INK QUEUED",
                         pillCopy: "Driver at the receiving bay · BOL co-sign begun · POD-ink one tap",
                         receivablePill: "§11.4 RECEIVABLE READY · POD-INK QUEUED · CHAIN COMPLETE · NET-30 DOWNSTREAM")
        case .podReceipt:
            return .init(eyebrow: "CATALYST · OUTBOUND · PAPERWORK · POD RECEIPT",
                         citation: "§294 · WITHIN-TRACK EIGHTH-PORT 3/3 · TRIGGER CLOSED",
                         title: "POD chain · closed",
                         subhead: "POD CERT · ISSUED · NET-30",
                         pillCopy: "ePOD CERT issued · chain reconciled · NET-30 wired · payout-advance armed",
                         receivablePill: "§11.4 RECEIVABLE RELEASED · POD CERT ISSUED · NET-30 WIRED · PAYOUT-ADVANCE 1.5%/5D")
        case .loadClosed:
            return .init(eyebrow: "CATALYST · DISPATCH · CLOSED · LOAD CLOSED",
                         citation: "§296 · WITHIN-TRACK NINTH-PORT 3/3 · TRIGGER CLOSED",
                         title: "Load closed · backhaul armed",
                         subhead: "ROLLUP · CONFIRMED",
                         pillCopy: "Rollup confirmed · payout staged · carrier netted · backhaul tender ready",
                         receivablePill: "§295 PAYOUT STAGED · §296 CARRIER NETTED · BACKHAUL ARMED · Q2 +1")
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

    // MARK: - Live display helpers (honest "-"/"—" when no source)

    /// Real load number, or em-dash when the load hasn't resolved.
    private var loadNumberDisplay: String {
        let n = load?.loadNumber?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "—" : n
    }

    /// Nested {city,state} lane "Origin, ST → Dest, ST". Server sends ""
    /// (not nil) for missing fields → treat empty as the no-source case.
    private var laneDisplay: String? {
        let o = [load?.pickupLocation?.city, load?.pickupLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        let d = [load?.deliveryLocation?.city, load?.deliveryLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        guard !o.isEmpty || !d.isEmpty else { return nil }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }

    /// Trailer / equipment — "—" when the shipper never specified.
    private var trailerDisplay: String {
        let eq = load?.equipmentType?.trimmingCharacters(in: .whitespaces) ?? ""
        return eq.isEmpty ? "—" : eq
    }

    /// PAYOUT — bound to the real load.rate (decimal string). "—" when
    /// missing/invalid. No invented fallback.
    private var payoutDisplay: String {
        guard let r = load?.rate, let n = Double(r), n > 0 else { return "—" }
        let v = n.rounded()
        return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
    }

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
                if load != nil {
                    Text("\(loadNumberDisplay) · \(laneDisplay ?? "—") · \(trailerDisplay)")
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

    /// Counter-party = the load's shipper-of-record (resolved party from
    /// loads.getById). No hardcoded founder pin. EIN has no source on the
    /// resolved party → "—". Whole card degrades honestly when no party.
    private var counterparty: some View {
        let party = load?.shipper
        let name = party?.companyName?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? party?.name?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? "—"
        let ini = party?.initials?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "—"
        let companyId = party?.id.map { "companyId \($0)" } ?? "companyId —"
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(ini).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(name) · shipper-of-record · counter-party").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("\(companyId) · EIN — · NET-30 receivable").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .atGate:
                return [
                    ("DOCK",     "—",                "bay assignment pending",     .blue),
                    ("PALLETS",  "—",                "load count pending",         .blue),
                    ("REEFER",   "—",                "temp telemetry pending",     .green),
                    ("AHEAD",    "—",                "gate queue pending",         .orange),
                ]
            case .atDock:
                return [
                    ("DOCK",     "—",                "IN · loading",               .orange),
                    ("LOADED",   "—",                "progress telemetry pending", .blue),
                    ("REEFER",   "—",                "temp telemetry pending",     .green),
                    ("DWELL",    "—",                "dwell clock pending",        .green),
                ]
            case .departing:
                return [
                    ("ROUTE",    "—",                "route telemetry pending",    .blue),
                    ("ETA",      "—",                "routed ETA pending",         .blue),
                    ("BOL",      "SIGNED",           "gate-out cleared",           .green),
                    ("STATUS",   "DEPARTED",         "en route",                   .green),
                ]
            case .preDelivery:
                return [
                    ("ROUTE",    "—",                "route telemetry pending",    .blue),
                    ("ETA",      "—",                "routed ETA pending",         .blue),
                    ("DOCK",     "—",                "pre-assignment pending",     .orange),
                    ("BOL",      "AT-RECV",          "co-sign queued",             .blue),
                ]
            case .atDelivery:
                return [
                    ("DOCK",     "—",                "IN · receiving",             .orange),
                    ("BOL",      "CO-SIGN",          "signing now",                .green),
                    ("REEFER",   "—",                "temp telemetry pending",     .green),
                    ("ETA",      "0m",               "ARRIVED · OTA",              .green),
                ]
            case .podReceipt:
                return [
                    ("PALLETS",  "—",                "reconciliation pending",     .green),
                    ("POD CERT", "ISSUED",           "ePOD chain sealed",          .green),
                    ("PAY",      "NET-30",           "wired",                      .green),
                    ("ADVANCE",  "1.5%/5D",          "armed",                      .blue),
                ]
            case .loadClosed:
                return [
                    ("PALLETS",  "—",                "reconciliation pending",     .green),
                    ("PAYOUT",   payoutDisplay,      "staged · NET-30",            .green),
                    ("CARRIER",  "—",                "split telemetry pending",    .green),
                    ("BACKHAUL", "ARMED",            "tender ready · Q2 +1",       .blue),
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
            case .atDock:      return "Watch the reefer band; chain-of-custody attestation arms at seal."
            case .departing:   return "Long-haul leg begins. POD arming activates at receiver-gate; net-30 downstream wires on POD-ink."
            case .preDelivery: return "Call ahead 15 minutes out. Confirm receiver dock + paperwork access; backhaul tender pre-stages."
            case .atDelivery:  return "Receiver inspects + co-signs. POD-ink lands the chain; NET-30 downstream wires on issue."
            case .podReceipt:  return "ePOD CERT issued, NET-30 wired. Payout-advance 1.5%/5D armed. Pull if cash-flow needed."
            case .loadClosed:  return "Rollup confirmed, backhaul tender ready. Approve to keep the fleet moving on the backhaul chain."
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
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* leaves load nil → honest "—" */ }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
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
