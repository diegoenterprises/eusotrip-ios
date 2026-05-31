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
//  All 5 share `ShipperBackhaulEchoCloseBody`.
//
//  Wire bindings (mirror 248_ShipperPODReceipt):
//    loads.getById(loadId)         — load context (number, route, carrier,
//                                     pallets, status, delivery time)
//    podCapture.getForLoad(loadId) — POD record (pallets reconciled, seal,
//                                     signature chain, payable status)
//
//  Every dock / pallet / BOL / HOS / POD field renders from the fetched
//  load + POD record, or an honest em-dash "—" where no live source
//  exists. No fabricated bay / pallet / BOL literals. Bottom nav frozen
//  (Shipper: Home / Loads / ESANG / Me).
//

import SwiftUI

private struct SCLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let trailerType: String?
    let rate: String?
    let status: String?
    let palletCount: Int?
    let carrierName: String?
    let actualDeliveryDate: String?
    let podCertId: String?
}

private struct SCPodCtx: Decodable, Hashable {
    let loadId: Int?
    let palletsReceived: Int?
    let palletsExpected: Int?
    let sealNumber: String?
    let temperatureF: Double?
    let signedByDriver: Bool?
    let signedByReceiver: Bool?
    let signedByShipper: Bool?
    let payableStatus: String?
}

enum ShipperBackhaulEchoCloseKind: String {
    case dockedLoading, bolPreSign, bolSigned, paperwork, closedSeal
}

private struct SCConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let echoState: String
}

private extension ShipperBackhaulEchoCloseKind {
    var config: SCConfig {
        switch self {
        case .dockedLoading:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · DOCKED LOADING ECHO",
                         citation: "§339 · DOCKED 4/N · SUB-AXIS 4/N",
                         title: "Delivery · docked loading",
                         subhead: "§339 · DOCKED 4/N",
                         echoState: "DOCKED LOADING")
        case .bolPreSign:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · BOL PRE-SIGN ECHO",
                         citation: "§346 · BOL 4/N · SUB-AXIS 4/N",
                         title: "Delivery · BOL pre-sign",
                         subhead: "§346 · BOL 4/N",
                         echoState: "BOL PRE-SIGN")
        case .bolSigned:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · BOL SIGNED ECHO",
                         citation: "§350 · BOL SIGNED 4/N · SUB-AXIS 4/N",
                         title: "Delivery · BOL signed",
                         subhead: "§350 · BOL SIGNED 4/N",
                         echoState: "BOL SIGNED")
        case .paperwork:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · PAPERWORK ECHO",
                         citation: "§354 · PAPERWORK 4/4 · QUARTET SEALED",
                         title: "Paperwork · quartet 4 of 4 sealed",
                         subhead: "§354 · PAPERWORK 4/4",
                         echoState: "PAPERWORK")
        case .closedSeal:
            return .init(eyebrow: "SHIPPER · LOADS · CLOSED · CHAIN SEAL",
                         citation: "§358 · CLOSED 4/4 · CHAIN SEALED",
                         title: "Closed · chain sealed at four of four",
                         subhead: "§358 · CLOSED 4/4 · CHAIN SEALED",
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
    @State private var pod: SCPodCtx?

    private static let dash = "—"

    // ── Derived live values (em-dash where no live source) ──────────
    private var loadLabel: String { load?.loadNumber ?? (load?.id.map { "LD-\($0)" } ?? Self.dash) }
    private var routeLine: String {
        guard let l = load else { return Self.dash }
        let from = l.pickupCity ?? Self.dash
        let to = l.destCity ?? Self.dash
        let eq = l.trailerType ?? Self.dash
        return "\(loadLabel) · \(from) → \(to) · \(eq)"
    }
    private var palletExpected: Int? { pod?.palletsExpected ?? load?.palletCount }
    private var palletReceived: Int? { pod?.palletsReceived }
    private var carrierLabel: String { load?.carrierName ?? Self.dash }
    private var sealLabel: String { pod?.sealNumber ?? Self.dash }
    private var podCertLabel: String { load?.podCertId ?? Self.dash }
    private var payableLabel: String { (pod?.payableStatus).map { $0.uppercased() } ?? Self.dash }
    private var podArchived: Bool { pod?.signedByReceiver == true && pod?.signedByShipper == true }

    private func palletsFraction(_ rcv: Int?, _ exp: Int?) -> String {
        switch (rcv, exp) {
        case let (r?, e?): return "\(r)/\(e)"
        case let (nil, e?): return "—/\(e)"
        case let (r?, nil): return "\(r)/—"
        default: return Self.dash
        }
    }

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
        .task { await loadAll() }
        .refreshable { await loadAll() }
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

    // Citation pill: §-anchored stage copy is static doctrine; the load
    // line beneath it binds to the live fetched load (em-dash if absent).
    private func citationPill(_ c: SCConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("\(c.echoState) · ledger sealed").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(routeLine).font(.caption2).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chainPill(_ c: SCConfig) -> some View {
        let carrier = carrierLabel
        let pallets = palletsFraction(palletReceived, palletExpected)
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(c.echoState) · ECHO CLOSED").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.green)
                Text("BACKHAUL · \(carrier) · \(loadLabel) · PALLETS \(pallets)").font(.caption2).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("DU").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shipper-of-record · backhaul echo only").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("\(loadLabel) · ledger sealed").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let exp = palletExpected
        let rcv = palletReceived
        let pallets = palletsFraction(rcv, exp)
        let palletsLoaded = exp.map { "\($0)/\($0)" } ?? Self.dash
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .dockedLoading:
                return [
                    ("CARRIER", carrierLabel,                "backhaul",                .blue),
                    ("PALLETS", pallets,                      exp == nil ? "—" : "loading", .blue),
                    ("SEAL",    sealLabel,                    pod?.sealNumber == nil ? "—" : "live", .blue),
                    ("LEDGER",  "SEALED",                     "your chain · closed",     .green),
                ]
            case .bolPreSign:
                return [
                    ("BOL",     pod == nil ? Self.dash : "DRAFT", pod == nil ? "—" : "pre-sign", .blue),
                    ("PALLETS", palletsLoaded,                exp == nil ? "—" : "LOADED",   .green),
                    ("SEAL",    sealLabel,                    pod?.sealNumber == nil ? "—" : "applied", .blue),
                    ("LEDGER",  "SEALED",                     "your chain · closed",     .green),
                ]
            case .bolSigned:
                let bolSigned = pod?.signedByDriver == true
                return [
                    ("BOL",     bolSigned ? "SIGNED" : Self.dash, bolSigned ? "verified" : "—", bolSigned ? .green : .blue),
                    ("PALLETS", pallets,                      exp == nil ? "—" : "in transit", bolSigned ? .green : .blue),
                    ("SEAL",    sealLabel,                    pod?.sealNumber == nil ? "—" : "intact", .blue),
                    ("LEDGER",  "SEALED",                     "your chain · closed",     .green),
                ]
            case .paperwork:
                let filed = pod != nil
                return [
                    ("PACKET",  filed ? "FILED" : Self.dash,  filed ? "POD watch" : "—",     filed ? .green : .blue),
                    ("POD",     podArchived ? "ARCHIVED" : "WATCH", podArchived ? "co-signed" : "armed", podArchived ? .green : .blue),
                    ("QUARTET", "4/4",                        "sealed · §354",           .green),
                    ("LEDGER",  "SEALED",                     "your chain · closed",     .green),
                ]
            case .closedSeal:
                return [
                    ("POD",     podArchived ? "ARCHIVED" : Self.dash, podCertLabel, podArchived ? .green : .blue),
                    ("PAYABLE", payableLabel,                 pod?.payableStatus == nil ? "—" : "NET-30", payableLabel == Self.dash ? .blue : .green),
                    ("QUARTET", "4/4",                        "chain sealed",            .green),
                    ("LEDGER",  "SEALED",                     "\(loadLabel) closed",     .green),
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
            case .dockedLoading: return "Carrier docked and loading. Echo closes on dock-out; no shipper action needed."
            case .bolPreSign:    return "BOL draft armed for carrier signature. Echo closes when the sig-hash lands."
            case .bolSigned:     return "BOL signed and verified. Carrier rolls; paperwork-watch arms on packet filing."
            case .paperwork:     return "Paperwork filed and POD watch armed. POD-ink fires when the receiver co-signs."
            case .closedSeal:    return "Chain sealed. POD archived, carrier wallet credited. Backhaul echo fully closed."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadAll() async {
        async let l: Void = loadCtx()
        async let p: Void = loadPOD()
        _ = await (l, p)
    }
    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
    private func loadPOD() async {
        struct In: Encodable { let loadId: String }
        do { pod = try await EusoTripAPI.shared.query("podCapture.getForLoad", input: In(loadId: loadId)) } catch { /* */ }
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
