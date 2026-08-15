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
//  Dispatcher backhaul cards mirroring the driver/catalyst chains from the
//  dispatcher vantage. All 12 share `DispatcherBHCardBody`. Body reads
//  `loads.getById` via the canonical `LoadsAPI.LoadDetail` projection and
//  binds every business value (load number / lane / rate / distance / carrier
//  / driver) to that live record. Stage-only chrome (eyebrow / citation /
//  title / stage labels) describes the card lifecycle itself, never invented
//  business figures. Values with no live source render an honest em-dash —
//  no fabricated carrier names, USDOT/MC numbers, dollar amounts, miles,
//  docks, ETAs, pallet counts, BOL/POD ids, or signature hashes. Bottom nav
//  frozen.
//

import SwiftUI

enum DispatcherBHCardKind: String {
    case reassign, tenderResolved, pickupArmed, pickupFired, inTransit, deliveryApproach, atDelivery, dockedLoading, bolPreSign, bolSigned, paperwork, closed
}

// Stage-only chrome. These describe the lifecycle position of the card
// (which §-stage / which step in the chain) — they carry NO business data.
// Every load-specific value (load number, lane, rate, distance, carrier,
// driver) is bound at render time from `LoadsAPI.LoadDetail`.
private struct DBCConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let nextStep: String
}

private extension DispatcherBHCardKind {
    var config: DBCConfig {
        switch self {
        case .reassign:
            return .init(eyebrow: "DISPATCHER · BH REASSIGN · TENDER STAGED",
                         citation: "DISPATCHER BH REASSIGN · TENDER STAGE",
                         title: "Reassign backhaul",
                         subhead: "Tender staged · awaiting carrier response",
                         nextStep: "Carrier has not responded inside the accept window. Tap to reassign to the next fallback carrier in the pool.")
        case .tenderResolved:
            return .init(eyebrow: "DISPATCHER · TENDER · BACKHAUL · RESOLVED",
                         citation: "DISPATCHER BH RESOLVED · TRIPLET CLOSED",
                         title: "Tender resolved",
                         subhead: "Tender accepted · awarded",
                         nextStep: "Carrier accepted the tender. The triplet is closed; the DVIR sub-axis opens next.")
        case .pickupArmed:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · PICKUP-BOARD",
                         citation: "BOARD-CONSOLIDATED · PICKUP WATCH",
                         title: "Pickup board armed",
                         subhead: "Watch armed · pickup window",
                         nextStep: "Pickup board armed. The pre-arrival ping fires when the driver pulls toward the pickup dock.")
        case .pickupFired:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · PICKUP-FIRED",
                         citation: "BOARD · PICKUP FIRED · LOADING",
                         title: "Pickup board fired",
                         subhead: "On-site · loading",
                         nextStep: "Driver is on-site and loading. Advance the card to in-transit on gate-out.")
        case .inTransit:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · IN-TRANSIT",
                         citation: "IN-TRANSIT CARD · DRIVING",
                         title: "In-transit",
                         subhead: "In-transit · driving",
                         nextStep: "Driver is en route to the receiver. No intervention needed while HOS stays clean.")
        case .deliveryApproach:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · DELIVERY · APPROACH",
                         citation: "DELIVERY CARD · APPROACHING",
                         title: "Delivery card · approaching",
                         subhead: "Approaching receiver",
                         nextStep: "Approaching the receiver. Pre-arm dock + paperwork access; ESang nudges on final approach.")
        case .atDelivery:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · AT-DELIVERY",
                         citation: "AT-DELIVERY CARD · GATE-IN",
                         title: "At delivery",
                         subhead: "At delivery · docked",
                         nextStep: "Gate-in at the receiver. Receiver-bay attestation arms on dock placement.")
        case .dockedLoading:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · DOCKED-LOADING",
                         citation: "DOCKED-LOADING CARD",
                         title: "Delivery · docked loading",
                         subhead: "Docked · loading",
                         nextStep: "Docked and loading. BOL pre-sign arms on dock-plate touch.")
        case .bolPreSign:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · BOL-PRE-SIGN",
                         citation: "BOL-PRE-SIGN CARD",
                         title: "BOL pre-sign",
                         subhead: "Dock plate · BOL draft",
                         nextStep: "BOL draft loaded at the dock plate. The driver taps to sign next.")
        case .bolSigned:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · BOL-SIGNED",
                         citation: "BOL-SIGNED CARD · VERIFIED WS",
                         title: "BOL signed",
                         subhead: "BOL signed · sealed",
                         nextStep: "BOL signed and verified. Paperwork watch armed for filing.")
        case .paperwork:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · PAPERWORK",
                         citation: "PAPERWORK CARD",
                         title: "Paperwork",
                         subhead: "Packet open",
                         nextStep: "Paperwork open · BOL filed. POD watch armed; POD-ink fires when the receiver co-signs.")
        case .closed:
            return .init(eyebrow: "DISPATCHER · BOARD · BACKHAUL · CLOSED",
                         citation: "CLOSED CARD",
                         title: "Closed",
                         subhead: "Chain sealed",
                         nextStep: "Chain sealed. POD submitted; settlement releases per the load's net terms. Chain-seal available for archive.")
        }
    }
}

private struct DispatcherBHCardShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
                orbState: .idle
            )
        }
    }
}

private struct DispatcherBHCardBody: View {
    let loadId: String
    let kind: DispatcherBHCardKind

    @Environment(\.palette) private var palette
    @State private var load: LoadsAPI.LoadDetail?
    @State private var actionInFlight: Bool = false
    @State private var actionAck: String?
    @State private var actionError: String?

    // Em-dash placeholder for any business value with no live source.
    private let none = "—"

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                pill(c)
                chainPill(c)
                identityRow
                kpiGrid
                nextStepCard(c)
                if kind == .reassign { reassignActionRow }
                if let ack = actionAck {
                    LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(.green) }
                }
                if let err = actionError {
                    LifecycleCard { Text(err).font(EType.caption).foregroundStyle(.red) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .eusoRefreshable { await loadCtx() }
    }

    // MARK: - Live-bound helpers (no fabrication)

    /// "LD-…" load number, or em-dash until the record hydrates.
    private var loadNumberText: String { load?.loadNumber ?? none }

    /// "Phoenix, AZ → Los Angeles, CA" — em-dash when both ends are blank.
    private var laneText: String { load?.laneDisplay ?? none }

    /// "$2,440" — em-dash when the rate column is null/zero.
    private var rateText: String { load?.rateDisplay ?? none }

    /// "372 mi" — em-dash when distance is null/zero.
    private var distanceText: String { load?.distanceDisplay ?? none }

    /// Carrier line bound to the load's catalystId (no name field exists on
    /// the LoadDetail projection — honest "Catalyst #N" / pending state).
    private var carrierLine: String {
        if let id = load?.catalystId { return "Catalyst #\(id)" }
        return "Catalyst · pending"
    }

    /// Driver line bound to driverId — honest "Driver #N" / awaiting state.
    private var driverLine: String {
        if let id = load?.driverId { return "Driver #\(id)" }
        return "Driver · awaiting assignment"
    }

    /// Monogram for the identity chip. No catalyst-name field exists, so this
    /// keys off the load id rather than a hardcoded company initial.
    private var identityMonogram: String {
        if let id = load?.catalystId { return "C\(id % 100)" }
        if let n = load?.loadNumber, let first = n.uppercased().first(where: { $0.isLetter }) {
            return String(first)
        }
        return "—"
    }

    private var reassignActionRow: some View {
        Button { Task { await reassignLoad() } } label: {
            HStack(spacing: 6) {
                if actionInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                Text(actionInFlight ? "Reassigning…" : "Reassign to fallback carrier")
                    .font(EType.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(actionInFlight)
    }

    private func reassignLoad() async {
        actionInFlight = true; actionAck = nil; actionError = nil
        defer { actionInFlight = false }
        struct In: Encodable { let loadId: String; let fallbackCarrierId: String?; let reason: String? }
        struct Out: Decodable { let success: Bool?; let loadId: String?; let fallbackCarrierId: String?; let reassignedAt: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatchRole.reassignLoad",
                input: In(loadId: loadId, fallbackCarrierId: nil, reason: "Carrier did not respond inside the accept window — dispatcher reassigned via Dpch800")
            )
            if resp.success == true {
                actionAck = "Tender reassigned · returned to the pool · next fallback carrier armed for acceptance."
                await loadCtx()
            } else {
                actionError = "Reassign returned no success flag. Reload and try again."
            }
        } catch let err {
            actionError = (err as? LocalizedError)?.errorDescription ?? "Reassign failed: \(err)"
        }
    }

    private func header(_ c: DBCConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
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
                // Live-bound summary: load number · lane · rate. Em-dash for
                // any field the record hasn't supplied.
                Text("\(loadNumberText) · \(laneText) · \(rateText)")
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chainPill(_ c: DBCConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("BOARD CONTEXT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                // Live-bound lane + distance + carrier from the load record.
                Text("\(loadNumberText) · \(laneText) · \(distanceText) · \(carrierLine)")
                    .font(.caption2).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(identityMonogram).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(carrierLine) · \(driverLine)").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text("\(loadNumberText) · backhaul board").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        // KPI labels describe the lifecycle stage of the card (UI semantics:
        // STATE / DVIR / BOL / POD / SEAL etc.). Their VALUES bind to the live
        // load record where a real source exists (DIST → distanceDisplay,
        // LANE → laneDisplay, RATE → rateDisplay, LOAD → loadNumber). Every
        // value with no live source — margin, escrow, dock, ETA, HOS clocks,
        // pallet counts, BOL signature hashes, depart times — renders the
        // honest em-dash, never a fabricated literal.
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .reassign:
                return [
                    ("STATE",  "STAGED",        "tender staged",          .orange),
                    ("CARRIER", carrierLine,    "current assignment",     .blue),
                    ("RATE",   rateText,        "tender rate",            .blue),
                    ("DIST",   distanceText,    "lane distance",          .blue),
                ]
            case .tenderResolved:
                return [
                    ("STATE",  "AWARDED",       "tender accepted",        .green),
                    ("CARRIER", carrierLine,    "awarded to",             .green),
                    ("RATE",   rateText,        "awarded rate",           .green),
                    ("MARGIN", none,            "no live source",         .blue),
                ]
            case .pickupArmed:
                return [
                    ("WATCH",  "ARMED",         "pre-arrival ping",       .green),
                    ("DVIR",   none,            "no live source",         .orange),
                    ("LANE",   laneText,        "pickup lane",            .blue),
                    ("DIST",   distanceText,    "lane distance",          .blue),
                ]
            case .pickupFired:
                return [
                    ("STATE",  "FIRED",         "on-site · loading",      .green),
                    ("DVIR",   none,            "no live source",         .green),
                    ("DOCK",   none,            "no live source",         .orange),
                    ("LOAD",   loadNumberText,  "active card",            .blue),
                ]
            case .inTransit:
                return [
                    ("STATE",  "DRIVING",       "in-transit",             .blue),
                    ("DIST",   distanceText,    "lane distance",          .blue),
                    ("ETA",    none,            "no live source",         .blue),
                    ("HOS",    none,            "no live source",         .green),
                ]
            case .deliveryApproach:
                return [
                    ("STATE",  "APPROACH",      "approaching receiver",   .green),
                    ("DIST",   distanceText,    "lane distance",          .blue),
                    ("ETA",    none,            "no live source",         .blue),
                    ("HOS",    none,            "no live source",         .green),
                ]
            case .atDelivery:
                return [
                    ("STATE",  "GATE-IN",       "at receiver",            .orange),
                    ("ETA",    none,            "no live source",         .blue),
                    ("QUEUE",  none,            "no live source",         .green),
                    ("HOS",    none,            "no live source",         .green),
                ]
            case .dockedLoading:
                return [
                    ("DOCK",    none,           "no live source",         .orange),
                    ("PALLETS", none,           "no live source",         .blue),
                    ("DEPART",  none,           "no live source",         .blue),
                    ("HOS",     none,           "no live source",         .green),
                ]
            case .bolPreSign:
                return [
                    ("BOL",     "DRAFT",        "awaiting sign",          .blue),
                    ("PALLETS", none,           "no live source",         .green),
                    ("DEPART",  none,           "no live source",         .orange),
                    ("STATE",   "PRE-SIGN",     "dock plate",             .blue),
                ]
            case .bolSigned:
                return [
                    ("BOL",     "SIGNED",       "verified",               .green),
                    ("SIG",     none,           "no live source",         .green),
                    ("DEPART",  none,           "no live source",         .green),
                    ("STATE",   "SIGNED",       "paperwork watch",        .green),
                ]
            case .paperwork:
                return [
                    ("BOL",     "FILED",        "packet filed",           .green),
                    ("POD",     "PENDING",      "awaiting submit",        .orange),
                    ("WATCH",   "ARMED",        "POD packet",             .blue),
                    ("HOS",     none,           "no live source",         .green),
                ]
            case .closed:
                return [
                    ("POD",     "SUBMITTED",    "chain sealed",           .green),
                    ("PAYOUT",  rateText,       "load rate",              .green),
                    ("ESCROW",  none,           "no live source",         .green),
                    ("SEAL",    "AVAILABLE",    "chain-seal ready",       .green),
                ]
            }
        }()
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.0).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.1).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.3).lineLimit(1).minimumScaleFactor(0.6)
                    Text(k.2).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.3.opacity(0.3)))
            }
        }
    }

    private func nextStepCard(_ c: DBCConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.nextStep).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* leaves nil → em-dash render */ }
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
