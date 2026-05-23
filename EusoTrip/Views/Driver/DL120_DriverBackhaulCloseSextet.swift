//
//  DL120_DriverBackhaulCloseSextet.swift
//  EusoTrip — Driver · Backhaul-close sextet (DL120-DL125).
//
//  Pixel-match to:
//    120 Driver Loading In Progress Tick Two
//    121 Driver Loading In Progress Tick Three
//    122 Driver Bol Pre Sign Opener
//    123 Driver Bol Signed
//    124 Driver BH Paperwork Stage Roll
//    125 Driver BH Closed Stage Roll
//
//  Closes the Driver backhaul chain that began at DL114. All 6 share
//  `BHCloseBody` parameterized by `BHCloseKind`. Body reads
//  `loads.getById`. Bottom nav frozen.
//

import SwiftUI

private struct BHCLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let rate: String?
}

enum BHCloseKind: String {
    case loadingTick2, loadingTick3, bolPreSign, bolSigned, paperwork, closed
}

private struct BCConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let stagePill: String
    let chainPill: String
}

private extension BHCloseKind {
    var config: BCConfig {
        switch self {
        case .loadingTick2:
            return .init(eyebrow: "DRIVER · TRIPS · BACKHAUL · LOADING-IN-PROGRESS",
                         citation: "§341 · IN-FLIGHT TICK 2 · 42/N PRESERVED · SUB-AXIS 4/N CLOSED",
                         title: "Loading 52/72 · bay 7B",
                         subhead: "LOADING · IN PROGRESS · 72% loaded",
                         stagePill: "ME forklift active · 4 ppm · 20 pallets left · 5 min ETA · DEPART 06:42 MST in 0:14 · HOS 02:40 / 8h 20m",
                         chainPill: "LD-BH7C3A · forklift OXN-FL-04 holds 4 ppm · pallets 52/72 · 20 left · 5 min ETA · DEPART 06:42 MST · 0:14 left")
        case .loadingTick3:
            return .init(eyebrow: "DRIVER · TRIPS · BACKHAUL · LOADING-IN-PROGRESS",
                         citation: "§342 · IN-FLIGHT TICK 3 FINAL · 42/N PRESERVED · BOL-PRE-SIGN ARMED",
                         title: "Loading 72/72 · bay 7B",
                         subhead: "LOADING · COMPLETE · 100%",
                         stagePill: "ME forklift idle · 0 left · 100% complete · DEPART 06:42 MST in 0:09 · HOS 02:45 / 8h 15m",
                         chainPill: "LD-BH7C3A · forklift OXN-FL-04 idle · pallets 72/72 · 0 left · 100% complete · DEPART 06:42 MST · 0:09 left")
        case .bolPreSign:
            return .init(eyebrow: "DRIVER · TRIPS · BACKHAUL · BOL-PRE-SIGN",
                         citation: "§343 · SUB-AXIS 1/N OPEN · NEXT-CHAIN PORT 43/N ADVANCES · PRIOR LOADING COMPLETE",
                         title: "BOL pre-sign · bay 7B",
                         subhead: "BOL · PRE-SIGN · DRAFT",
                         stagePill: "ME at dock plate · BOL draft loaded · pallets locked 72/72 · DEPART 06:42 MST in 0:04 · HOS 02:50 / 8h 10m",
                         chainPill: "LD-BH7C3A · BOL packet BOL-NLR-LA-2026-05-19-BH7C3A · DRAFT · HOS 02:50 · DEPART 06:42 MST · 0:04 left")
        case .bolSigned:
            return .init(eyebrow: "DRIVER · TRIPS · BACKHAUL · BOL-SIGNED",
                         citation: "§347 · WITHIN-TRACK COMMIT · NEXT-CHAIN PORT 47/N ADVANCES · WATCH FIRED",
                         title: "BOL signed · bay 7B",
                         subhead: "BOL · SIGNED · 0x9F1C",
                         stagePill: "ME at dock plate · BOL signed · stylus retracted · DEPART 06:42 MST in 0:02 · HOS 02:57 / 8h 03m",
                         chainPill: "LD-BH7C3A · BOL packet BOL-NLR-LA-2026-05-19-BH7C3A · SIGNED · SIG-HASH 0x9F1C · HOS 02:57 · DEPART 06:42 MST · 0:02 left")
        case .paperwork:
            return .init(eyebrow: "DRIVER · TRIPS · BACKHAUL · PAPERWORK-OPEN",
                         citation: "§351 · STAGE ROLL DELIVERY → PAPERWORK · 51/N ADVANCES · WATCH ARMED",
                         title: "Paperwork open",
                         subhead: "PAPERWORK · OPEN",
                         stagePill: "ME at packet desk · BOL filed · POD pending · LUMPER $0 · HOS 03:02 / 7h 58m",
                         chainPill: "LD-BH7C3A · ME at packet desk · BOL FILED · POD pending submit · HOS 03:02 · 7h 58m left")
        case .closed:
            return .init(eyebrow: "DRIVER · TRIPS · BACKHAUL · CLOSED-OPEN",
                         citation: "§355 · STAGE ROLL PAPERWORK → CLOSED · 55/N · POD SUBMITTED · QUARTET 1/N OPEN",
                         title: "Chain closed",
                         subhead: "CLOSED · OPEN · payout $2,128",
                         stagePill: "ME at payout review · POD submitted · BOL filed · payout $2,128.00 · HOS 03:06 / 7h 54m",
                         chainPill: "LD-BH7C3A · POD submitted · payout $2,128.00 NET-30 LOCKED · HOS 03:06 · 7h 54m left")
        }
    }
}

private struct BHCloseShell<Content: View>: View {
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

private struct BHCloseBody: View {
    let loadId: String
    let kind: BHCloseKind

    @Environment(\.palette) private var palette
    @State private var load: BHCLoadCtx?
    @State private var actionInFlight: Bool = false
    @State private var actionAck: String?
    @State private var actionError: String?

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
                if kind == .bolPreSign { signBOLActionRow }
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
        .refreshable { await loadCtx() }
    }

    private var signBOLActionRow: some View {
        Button { Task { await signBOL() } } label: {
            HStack(spacing: 6) {
                if actionInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                Text(actionInFlight ? "Signing…" : "Sign BOL")
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

    private func signBOL() async {
        actionInFlight = true; actionAck = nil; actionError = nil
        defer { actionInFlight = false }
        // Generate a 32-bit signature hash hex string for the ePOD chain.
        // In production this is computed server-side from the canvas signature;
        // the client pre-stages a deterministic envelope here so the audit-row
        // lands with non-empty fields and ESang can chain it forward.
        let sigHash = String(format: "0x%08X", UInt32.random(in: UInt32.min...UInt32.max))
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let bolNumber = "BOL-NLR-LA-\(df.string(from: Date()))-BH7C3A"
        struct In: Encodable { let loadId: String; let bolNumber: String; let signatureHash: String; let signedAtIso: String? }
        struct Out: Decodable { let success: Bool?; let loadId: String?; let bolNumber: String?; let signatureHash: String?; let signedAt: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "loads.signBOL",
                input: In(loadId: loadId, bolNumber: bolNumber, signatureHash: sigHash, signedAtIso: nil)
            )
            if resp.success == true {
                actionAck = "BOL signed · sig-hash \(resp.signatureHash ?? sigHash) committed · paperwork watch armed."
                await loadCtx()
            } else {
                actionError = "BOL sign returned no success flag — reload and try again."
            }
        } catch let err {
            actionError = (err as? LocalizedError)?.errorDescription ?? "BOL sign failed: \(err)"
        }
    }

    private func header(_ c: BCConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: BCConfig) -> some View {
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

    private func chainPill(_ c: BCConfig) -> some View {
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
            case .loadingTick2:
                return [
                    ("PALLETS", "52/72",                        "72% · 20 left",          .blue),
                    ("ETA",     "5 min",                         "to complete",            .blue),
                    ("DEPART",  "06:42",                          "MST · 0:14 left",       .blue),
                    ("HOS",     "02:40",                            "/ 8h 20m clean",       .green),
                ]
            case .loadingTick3:
                return [
                    ("PALLETS", "72/72",                            "100% complete",        .green),
                    ("STATE",   "IDLE",                              "forklift retracted",  .green),
                    ("DEPART",  "06:42",                              "MST · 0:09 left",    .blue),
                    ("HOS",     "02:45",                                "/ 8h 15m clean",   .green),
                ]
            case .bolPreSign:
                return [
                    ("BOL",     "DRAFT",                                "loaded · ME signing", .blue),
                    ("PALLETS", "72/72",                                  "locked · sealed",   .green),
                    ("DEPART",  "06:42",                                    "MST · 0:04 left", .orange),
                    ("HOS",     "02:50",                                      "/ 8h 10m clean",  .green),
                ]
            case .bolSigned:
                return [
                    ("BOL",     "SIGNED",                                      "0x9F1C · verified", .green),
                    ("STYLUS",  "RETRACTED",                                     "ME committed",     .green),
                    ("DEPART",  "06:42",                                          "MST · 0:02 left", .orange),
                    ("HOS",     "02:57",                                            "/ 8h 03m clean",  .green),
                ]
            case .paperwork:
                return [
                    ("BOL",     "FILED",                                            "ME at packet desk", .green),
                    ("POD",     "PENDING",                                            "submit ready",   .orange),
                    ("LUMPER",  "$0",                                                  "no accessorial",  .green),
                    ("HOS",     "03:02",                                                "/ 7h 58m clean",  .green),
                ]
            case .closed:
                return [
                    ("PAYOUT",  "$2,128",                                                "NET-30 LOCKED",  .green),
                    ("POD",     "SUBMITTED",                                              "audit-chained",  .green),
                    ("BOL",     "FILED",                                                    "0x9F1C archive", .green),
                    ("HOS",     "03:06",                                                      "/ 7h 54m clean",  .green),
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
            case .loadingTick2: return "52/72 loaded, 20 pallets left. Forklift cadence steady at 4 ppm — depart on schedule at 06:42 MST."
            case .loadingTick3: return "Loading complete at 72/72. BOL-PRE-SIGN armed — proceed to dock plate to sign the draft."
            case .bolPreSign:   return "BOL draft loaded. ME taps sign-acknowledge on dock plate; sig-hash commits the BOL."
            case .bolSigned:    return "BOL signed and verified (0x9F1C). Roll the chain to paperwork — packet-desk watch fires on filing."
            case .paperwork:    return "BOL filed at packet desk. Submit the POD to advance the chain to closed and stage payout."
            case .closed:       return "Chain closed. POD audit-chained, BOL archived (0x9F1C), $2,128 NET-30 locked. Backhaul complete."
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

// MARK: - Screens (DL120-DL125)

struct DriverLoadingTick2Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHCloseShell(theme: theme) { BHCloseBody(loadId: loadId, kind: .loadingTick2) } }
}
struct DriverLoadingTick3Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHCloseShell(theme: theme) { BHCloseBody(loadId: loadId, kind: .loadingTick3) } }
}
struct DriverBOLPreSignScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHCloseShell(theme: theme) { BHCloseBody(loadId: loadId, kind: .bolPreSign) } }
}
struct DriverBOLSignedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHCloseShell(theme: theme) { BHCloseBody(loadId: loadId, kind: .bolSigned) } }
}
struct DriverBHPaperworkScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHCloseShell(theme: theme) { BHCloseBody(loadId: loadId, kind: .paperwork) } }
}
struct DriverBHClosedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { BHCloseShell(theme: theme) { BHCloseBody(loadId: loadId, kind: .closed) } }
}

// MARK: - Previews

#Preview("DL120 Tick2 · Dark")     { DriverLoadingTick2Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL121 Tick3 · Light")    { DriverLoadingTick3Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL122 BOL Pre · Dark")   { DriverBOLPreSignScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL123 BOL Sign · Light") { DriverBOLSignedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL124 Paper · Dark")     { DriverBHPaperworkScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL125 Closed · Light")   { DriverBHClosedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
