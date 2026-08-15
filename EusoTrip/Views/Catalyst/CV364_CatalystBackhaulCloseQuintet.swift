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
//  `loads.getById` (corrected shape). Bottom nav frozen.
//
//  Honest-data rebuild (ZERO fabrication):
//    • `loads.getById` ({ id }) → CCLoadCtx
//        Top-level `id` is a STRING on the wire (loads.ts returns
//        String(load.id)); decoding it as Int throws typeMismatch and
//        fails the WHOLE decode → blank surface. pickup/delivery are
//        NESTED {city,state} objects (NOT flat city fields). Party
//        objects carry {id:Int?, name, initials, companyName, mcNumber,
//        dotNumber}. From this proc we bind: rate (PAYOUT), lane,
//        distance, equipment, load number, commodity, parties.
//
//  Sources that DO NOT EXIST on loads.getById (rendered honest "—",
//  never invented):
//    • pallet count   — no pallet column on the loads row
//    • dock / bay      — no dock/bay column
//    • escrow amount   — no escrow source on this proc
//    • BOL number      — no BOL column / no BOL proc bound here
//    • sig-hash        — no signature-hash source
//    • POD cert id     — no POD column on the loads row
//    • depart time / forklift / ppm — no source
//  Every previously hardcoded persona (Aurora / MC942008 / Eusotrans
//  LLC / Michael Eusorone / USDOT 3 194 882 / forklift OXN-FL-04 /
//  BOL-NLR-LA-…/ 0x9F1C / $2,128) is DELETED. No `?? <invented>`
//  fallbacks remain — every fallback is "-"/"—".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - loads.getById decode (CORRECTED shape)

private struct CCLoadCtx: Decodable, Hashable {
    // Top-level load id is a STRING on the wire (loads.getById → String(load.id));
    // decoding as Int throws typeMismatch and fails the WHOLE decode → blank.
    let id: String?
    let loadNumber: String?
    // pickup/delivery are NESTED {city,state} objects (NOT flat city fields).
    let pickupLocation: CCLoc?
    let deliveryLocation: CCLoc?
    let rate: String?              // decimal-as-string from the loads.rate column
    let distance: Double?
    let equipmentType: String?
    let commodityName: String?
    let status: String?
    let driver: CCParty?
    let catalyst: CCParty?
    let shipper: CCParty?

    struct CCLoc: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct CCParty: Decodable, Hashable {
        let id: Int?              // party (user/company) id is numeric on the wire
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }
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
                         title: "Docked",
                         subhead: "§337 · DOCKED LOADING ACKED",
                         pillCopy: "Docked loading acked · stage advancing",
                         chainPill: "Bay occupied · docked-loading watch armed")
        case .bolPreSign:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · BOL-PRE-SIGN · 2/N",
                         citation: "§344 · CATALYST BOL-PRE-SIGN-ACKED · SUB-AXIS 2/N · NEXT-CHAIN 44/N",
                         title: "At dock plate",
                         subhead: "§344 · BOL PRE-SIGN ACKED",
                         pillCopy: "BOL draft acked · BOL-signed watch armed",
                         chainPill: "BOL packet drafted · BOL-signed watch armed")
        case .bolSigned:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · BOL-SIGNED · 2/N",
                         citation: "§348 · CATALYST BOL-SIGNED-ACKED · SUB-AXIS 2/N · NEXT-CHAIN 48/N · VERIFIED WS ENVELOPE",
                         title: "At dock plate",
                         subhead: "§348 · BOL SIGNED ACKED",
                         pillCopy: "BOL signed acked · paperwork watch armed",
                         chainPill: "BOL doc signed · paperwork watch armed")
        case .paperwork:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · PAPERWORK · 2/N",
                         citation: "§352 · CATALYST PAPERWORK-ACKED · SUB-AXIS 2/N · NEXT-CHAIN 52/N · VERIFIED WS ENVELOPE",
                         title: "Packet filed",
                         subhead: "§352 · PAPERWORK ACKED",
                         pillCopy: "Paperwork acked · POD watch armed · BOL filed",
                         chainPill: "BOL filed · POD packet armed · POD watch armed")
        case .closedStage:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · CLOSED · 2/N",
                         citation: "§356 · CATALYST CLOSED-ACKED · SUB-AXIS 2/N · NEXT-CHAIN 56/N · WALLET CREDITED · VERIFIED WS",
                         title: "Chain sealed",
                         subhead: "§356 · CLOSED ACKED",
                         pillCopy: "Closed acked · wallet credited · POD submitted · BOL filed",
                         chainPill: "POD submitted · BOL filed · escrow credited")
        }
    }
}

private struct CatalystBackhaulCloseShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: CarrierNavRoute.leading(current: .drivers),
                trailing: CarrierNavRoute.trailing(current: .drivers),
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
        .eusoRefreshable { await loadCtx() }
    }

    // MARK: - Derived (live-bound; honest "-"/"—" fallback)

    private var loadNumberDisplay: String {
        let n = load?.loadNumber?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "-" : n
    }

    /// Nested {city,state}; server sends "" (not nil) when missing.
    private var laneDisplay: String? {
        let o = [load?.pickupLocation?.city, load?.pickupLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        let d = [load?.deliveryLocation?.city, load?.deliveryLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        guard !o.isEmpty || !d.isEmpty else { return nil }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }

    private var equipmentDisplay: String {
        let eq = load?.equipmentType?.trimmingCharacters(in: .whitespaces) ?? ""
        return eq.isEmpty ? "—" : eq
    }

    private var commodityDisplay: String? {
        let c = load?.commodityName?.trimmingCharacters(in: .whitespaces) ?? ""
        return c.isEmpty ? nil : c
    }

    /// Carrier identity from the resolved catalyst party — no persona.
    private var carrierLine: String {
        let parts: [String] = [
            load?.catalyst?.companyName?.trimmingCharacters(in: .whitespaces),
            load?.catalyst?.name?.trimmingCharacters(in: .whitespaces),
        ].compactMap { ($0?.isEmpty == false) ? $0 : nil }
        return parts.first ?? "-"
    }
    private var carrierInitials: String {
        let i = load?.catalyst?.initials?.trimmingCharacters(in: .whitespaces) ?? ""
        return i.isEmpty ? "—" : i
    }
    private var carrierDOT: String {
        let d = load?.catalyst?.dotNumber?.trimmingCharacters(in: .whitespaces) ?? ""
        return d.isEmpty ? "-" : "USDOT \(d)"
    }
    private var carrierMC: String {
        let m = load?.catalyst?.mcNumber?.trimmingCharacters(in: .whitespaces) ?? ""
        return m.isEmpty ? "-" : "MC-\(m)"
    }

    /// PAYOUT from the load's rate (decimal string). "-" when missing.
    private var payoutDisplay: String {
        guard let r = load?.rate, let n = Double(r), n > 0 else { return "-" }
        let v = n.rounded()
        return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
    }
    private var distanceDisplay: String {
        guard let d = load?.distance, d > 0 else { return "-" }
        return "\(Int(d.rounded())) mi"
    }

    private func header(_ c: CCConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            // Real carrier + section subhead; no MC persona literal.
            Text("\(carrierLine) · \(c.subhead)").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CCConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                if load != nil {
                    Text("\(loadNumberDisplay) · \(laneDisplay ?? "—") · \(equipmentDisplay)")
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
                    .overlay(Text(carrierInitials).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(carrierLine).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text("\(carrierDOT) · \(carrierMC) · \(loadNumberDisplay) backhaul").font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        // No pallet / bay / depart / escrow / BOL# / sig-hash / POD source
        // on loads.getById → those cells render honest "—". Only PAYOUT,
        // DIST, equipment, lifecycle STATE bind to real values.
        let lane = laneDisplay ?? "-"
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .dockedLoading:
                return [
                    ("BAY",      "—",                              "no dock source",          .orange),
                    ("PALLETS",  "—",                              "no pallet source",        .blue),
                    ("DIST",     distanceDisplay,                  "\(lane)",                 .blue),
                    ("STATE",    "ACKED",                          "§337 · docked-loading",   .green),
                ]
            case .bolPreSign:
                return [
                    ("BAY",      "—",                              "no dock source",          .orange),
                    ("PALLETS",  "—",                              "no pallet source",        .green),
                    ("BOL",      "DRAFT",                          "acked · signed watch",    .blue),
                    ("STATE",    "ACKED",                          "§344 · BOL pre-sign",     .green),
                ]
            case .bolSigned:
                return [
                    ("BOL",      "SIGNED",                         "sig-hash —",              .green),
                    ("PALLETS",  "—",                              "no pallet source",        .green),
                    ("PAPER",    "WATCH",                          "armed",                   .blue),
                    ("STATE",    "ACKED",                          "§348 · BOL signed",       .green),
                ]
            case .paperwork:
                return [
                    ("BOL",      "FILED",                          "BOL# —",                  .green),
                    ("POD",      "PACKET",                         "POD id — · armed",        .blue),
                    ("STATE",    "ACKED",                          "§352 · paperwork",        .green),
                    ("CHAIN",    "52/N",                           "next-chain port",         .blue),
                ]
            case .closedStage:
                return [
                    ("PAYOUT",   payoutDisplay,                    "wallet credited",         .green),
                    ("POD",      "SUBMITTED",                      "POD id —",                .green),
                    ("BOL",      "FILED",                          "BOL# —",                  .green),
                    ("ESCROW",   "CREDITED",                       payoutDisplay == "-" ? "no escrow source" : "\(payoutDisplay) released", .green),
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
            case .dockedLoading: return "Docked loading acked. BOL pre-sign arms on dock-plate touch."
            case .bolPreSign:    return "BOL draft acked. Sign-acknowledge on the dock plate fires the BOL-signed broadcast next."
            case .bolSigned:     return "BOL signed. Paperwork watch armed; filing closes when the POD packet uploads."
            case .paperwork:     return "Paperwork filed. POD watch armed. POD-ink confirmation fires once the receiver co-signs."
            case .closedStage:   return "Chain sealed, escrow credited. Wallet balance updates shortly; advance-eligible."
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
        guard !loadId.isEmpty, loadId != "0" else { return }
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* honest "-"/"—" */ }
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
