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
//  docked-loading, loading-in-progress. All 6 share `BHPickupBody`
//  parameterized by `BHPickupKind`. Body reads `loads.getById`.
//  Bottom nav frozen.
//
//  Honest binding parity with sibling DL126_DriverCELM04Septet /
//  DL133_DriverCELM04DVIRContinuationOctet:
//   • Top-level load `id` is a String on the wire (loads.getById ->
//     String(load.id)); decoding as Int throws typeMismatch and fails
//     the WHOLE decode -> blank screen. So `id: String?`.
//   • pickup/delivery arrive as nested {city,state} objects (NOT flat
//     city fields); server sends "" (not nil) when missing.
//   • driver / catalyst / shipper resolve to real PARTY objects
//     {id, name, initials, companyName, mcNumber, dotNumber} — the UI
//     binds NAMES to these, never to a hardcoded persona.
//   • rate is a DECIMAL String; distance a Double.
//  Every rendered business value binds to live fetched data; anything
//  without a live source renders an honest "-" / "—".
//

import SwiftUI

private struct BHPLoadCtx: Decodable, Hashable {
    // Top-level load id is a String on the wire; Int throws and blanks.
    let id: String?
    let loadNumber: String?
    // Nested {city,state}; NOT flat city fields.
    let pickupLocation: BHPLoc?
    let deliveryLocation: BHPLoc?
    let rate: String?
    let distance: Double?
    let equipmentType: String?
    let driver: BHPParty?
    let catalyst: BHPParty?
    let shipper: BHPParty?
    struct BHPLoc: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct BHPParty: Decodable, Hashable {
        let id: Int?            // party (user/company) id is numeric on the wire
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }
}

enum BHPickupKind: String {
    case dvirComplete, loadedDeparted, approaching, atDelivery, dockedLoading, loadingInProgress
}

/// Stage-only chrome — canonical citation / eyebrow / title / state copy.
/// No scenario data is baked in; the live load number, parties, lane,
/// payout and distance are composed at render time from `loads.getById`.
/// Stage-progression details with NO server source (ETA times, RDC name,
/// dock / bay numbers, forklift id, pallet counts, session ids, HOS clocks)
/// render an honest "—".
private struct BPConfig {
    let eyebrowStage: String   // "DVIR COMPLETE" / "IN-TRANSIT" / …
    let citation: String       // §number canonical stage citation
    let title: String          // UX title
    let subhead: String        // stage state line
    let stageNote: String      // composed after carrier + loadNumber
}

private extension BHPickupKind {
    var config: BPConfig {
        switch self {
        case .dvirComplete:
            return .init(eyebrowStage: "BACKHAUL · DVIR · COMPLETE",
                         citation: "§320 · COMPOSITE S13-S14 + PICKUP ROLL · DVIR COMPLETE",
                         title: "DVIR complete · pickup",
                         subhead: "COMPLETE · 14/14 sections",
                         stageNote: "DVIR 14/14 · composite S13 + S14 · pickup roll armed")
        case .loadedDeparted:
            return .init(eyebrowStage: "BACKHAUL · IN-TRANSIT · 1/4",
                         citation: "§324 · LOADED + DEPARTED · 1/4 QUARTET OPEN",
                         title: "Loaded · in transit",
                         subhead: "LOADED · DEPARTED",
                         stageNote: "loaded · BOL signed · departed pickup")
        case .approaching:
            return .init(eyebrowStage: "BACKHAUL · DELIVERY · 1/4",
                         citation: "§328 · APPROACHING · 1/4 QUARTET OPEN",
                         title: "Approaching delivery",
                         subhead: "APPROACHING · inner-ring pending",
                         stageNote: "in transit · approaching delivery RDC")
        case .atDelivery:
            return .init(eyebrowStage: "BACKHAUL · AT-DELIVERY",
                         citation: "§332 · INNER-RING 0.5 MI CROSSED · SUB-AXIS 1/N",
                         title: "At delivery",
                         subhead: "AT DELIVERY · gate inbound",
                         stageNote: "at delivery RDC · gate inbound · queue forming")
        case .dockedLoading:
            return .init(eyebrowStage: "BACKHAUL · DOCKED-LOADING",
                         citation: "§336 · BACKED IN · SUB-AXIS 1/N OPEN",
                         title: "Docked · loading",
                         subhead: "DOCKED · LOADING",
                         stageNote: "backed in · loading in progress")
        case .loadingInProgress:
            return .init(eyebrowStage: "BACKHAUL · LOADING-IN-PROGRESS",
                         citation: "§340 · IN-FLIGHT TICK 1 · SUB-AXIS 4/N CLOSED",
                         title: "Loading in progress",
                         subhead: "LOADING · IN PROGRESS",
                         stageNote: "loading underway · forklift cadence steady")
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
                kpiGrid(c)
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    // MARK: - Dynamic display helpers (live-bound; honest "-"/"—" fallback)

    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }
    private var carrierCodeDisplay: String {
        load?.catalyst?.companyName ?? load?.catalyst?.name ?? "-"
    }
    private var laneDisplay: String? {
        // Nested {city,state}; server sends "" (not nil) when missing.
        let o = [load?.pickupLocation?.city, load?.pickupLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        let d = [load?.deliveryLocation?.city, load?.deliveryLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        guard !o.isEmpty || !d.isEmpty else { return nil }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }

    private func header(_ c: BPConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DRIVER · TRIPS · \(c.eyebrowStage) · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: BPConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("\(carrierCodeDisplay) · \(loadNumberDisplay) · \(c.stageNote)")
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(loadNumberDisplay) · \(laneDisplay ?? "—")")
                    .font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func chainPill(_ c: BPConfig) -> some View {
        let driverIni = load?.driver?.initials ?? "—"
        let dispIni   = load?.catalyst?.initials ?? "—"
        let shipIni   = load?.shipper?.initials ?? "—"
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("DISPATCH CHAIN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("\(loadNumberDisplay) · \(laneDisplay ?? "—") · \(c.stageNote) · \(driverIni) drives · \(dispIni) ops · \(shipIni) shipper")
                    .font(.caption2).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var identityRow: some View {
        let dispIni     = load?.catalyst?.initials ?? "—"
        let dispName    = load?.catalyst?.name ?? "-"
        let carrierFull = load?.catalyst?.companyName ?? load?.catalyst?.name ?? "-"
        let dot         = load?.catalyst?.dotNumber.map { "USDOT \($0)" } ?? "-"
        let mc          = load?.catalyst?.mcNumber.map { "MC-\($0)" } ?? "-"
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(dispIni).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(carrierFull) · \(dispName) · dispatcher")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("\(dot) · \(mc) · \(loadNumberDisplay) backhaul")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: BPConfig) -> some View {
        let payout = Self.payoutDisplay(load?.rate)
        let dist = Self.distanceDisplay(load?.distance)
        let lane = laneDisplay ?? "—"
        let equip = load?.equipmentType ?? "—"
        // Stage-progression metrics (ETA times, dock / bay numbers, pallet
        // counts, forklift id, HOS clocks, queue depth) have NO source in
        // loads.getById, so they render an honest "—".
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .dvirComplete:
                return [
                    ("DVIR",    "14/14",  "COMPLETE · S13+S14",                    .green),
                    ("STAGE",   "PICKUP", "§320 · roll armed",                     .green),
                    ("DIST",    dist,     lane,                                    .blue),
                    ("PAYOUT",  payout,   "\(carrierCodeDisplay) · \(loadNumberDisplay)", .green),
                ]
            case .loadedDeparted:
                return [
                    ("STAGE",   "DEPARTED", "loaded · BOL signed",                 .green),
                    ("DIST",    dist,       lane,                                  .blue),
                    ("EQUIP",   equip,      "\(carrierCodeDisplay) fleet",         .blue),
                    ("QUARTET", "1/4",      "§324 OPEN",                           .blue),
                ]
            case .approaching:
                return [
                    ("STAGE",   "APPROACH", "delivery RDC",                        .blue),
                    ("DIST",    dist,       lane,                                  .blue),
                    ("ETA",     "—",        "no live source",                      .blue),
                    ("HOS",     "—",        "no live source",                      .blue),
                ]
            case .atDelivery:
                return [
                    ("STAGE",   "AT-DEL",   "gate inbound",                        .orange),
                    ("DOCK",    "—",        "no live source",                      .orange),
                    ("DIST",    dist,       lane,                                  .blue),
                    ("PAYOUT",  payout,     "\(carrierCodeDisplay)",               .green),
                ]
            case .dockedLoading:
                return [
                    ("STAGE",   "DOCKED",   "loading",                             .orange),
                    ("BAY",     "—",        "no live source",                      .orange),
                    ("PALLETS", "—",        "no live source",                      .blue),
                    ("DEPART",  "—",        "no live source",                      .blue),
                ]
            case .loadingInProgress:
                return [
                    ("STAGE",   "LOADING",  "in progress",                         .blue),
                    ("PALLETS", "—",        "no live source",                      .blue),
                    ("FORKLIFT","—",        "no live source",                      .blue),
                    ("DEPART",  "—",        "no live source",                      .blue),
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
            case .dvirComplete:      return "DVIR closed at 14/14 with the S13+S14 composite. Pickup roll arms on gate-in."
            case .loadedDeparted:    return "Loaded and rolling. BOL signed; the long-haul leg to delivery begins."
            case .approaching:       return "Approaching the delivery RDC. Inner-ring 0.5 mi crosses at the gate; gate-in arms on entry."
            case .atDelivery:        return "Gate inbound. Back in when the receiver waves you to plate."
            case .dockedLoading:     return "Backed in. Loading is underway at the dock."
            case .loadingInProgress: return "Loading in progress. Cadence is steady; on track to depart on completion."
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

    /// Format the load's rate (decimal string from server) as a
    /// payout display. Falls back to "-" when missing/invalid.
    private static func payoutDisplay(_ rate: String?) -> String {
        guard let r = rate, let n = Double(r), n > 0 else { return "-" }
        let v = n.rounded()
        return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
    }

    /// Format the load's distance in miles. Falls back to "—".
    private static func distanceDisplay(_ d: Double?) -> String {
        guard let d, d > 0 else { return "—" }
        return "\(Int(d.rounded())) mi"
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
