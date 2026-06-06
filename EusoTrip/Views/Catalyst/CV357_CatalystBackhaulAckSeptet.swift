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
//  ── ZERO-FABRICATION REBUILD (2026-06-06) ───────────────────────
//  Every visible business value binds to a real `loads.getById`
//  field or paints an honest "-"/"—". The corrected `loads.getById`
//  decode shape (server loads.ts:1167) is used:
//    • top-level `id` is a String on the wire (String(load.id)) —
//      decoding it as Int throws typeMismatch and silently fails the
//      WHOLE decode → a blank surface;
//    • pickup/delivery are nested {city,state} objects, NOT flat
//      `pickupCity`/`destCity` strings;
//    • carrier name comes from the resolved `catalyst` party object
//      {id:Int?, name, initials, companyName, mcNumber, dotNumber}.
//  Deleted every hardcoded persona (AURORA · MC942008 · Eusotrans
//  LLC · Michael Eusorone · USDOT 3 194 882) and every invented
//  `?? <value>` (LD-BH7C3A / PHX / LA / Reefer / margin $172 / ETAs
//  / seal counts / dock numbers). The §-citation + chain-stage
//  scaffold strings are preserved as structural lifecycle labels
//  (sibling parity: DL133 CEL_SECTIONS citations, 373 node labels) —
//  they carry no load/business data. Visual layout/chrome/nav are
//  preserved verbatim.
//

import SwiftUI

/// Corrected `loads.getById` decode shape (server loads.ts:1338-1379).
/// Top-level `id` MUST be `String?` (server emits `String(load.id)`) —
/// an `Int?` here is a silent whole-decode failure. Pickup/delivery are
/// nested `{city,state}` objects (NOT flat city fields). Carrier identity
/// rides the resolved `catalyst` party object.
private struct CBLoadCtx: Decodable, Hashable {
    let id: String?
    let loadNumber: String?
    let pickupLocation: CBLoc?
    let deliveryLocation: CBLoc?
    let rate: String?              // DB decimal → JSON string
    let distance: Double?
    let equipmentType: String?
    let catalyst: CBParty?
    let driver: CBParty?
    let shipper: CBParty?

    struct CBLoc: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct CBParty: Decodable, Hashable {
        let id: Int?              // party (user) id is numeric on the wire
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }
}

enum CatalystBackhaulKind: String {
    case tender, accepted, pickupWatch, onSite, inTransit, deliveryApproach, atDelivery
}

private struct CBConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let chainPill: String
}

private extension CatalystBackhaulKind {
    /// Structural lifecycle scaffold only — §-citation chain + stage
    /// labels (no load/business data; sibling parity DL133/373). All
    /// persona/margin/ETA/seal/dock fabrications removed.
    var config: CBConfig {
        switch self {
        case .tender:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · TENDER STAGED",
                         citation: "§298 · CATALYST BACKHAUL TENDER · CARRIER-DISPATCHED-OUTBOUND · NEXT-CHAIN 2/N",
                         title: "Backhaul tendered · awaiting accept",
                         chainPill: "§297 ME TENDER RECEIVED · §298 STAGED-AWAITING-ACCEPT · §295.3 POST 10H RESET")
        case .accepted:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · ACCEPTED",
                         citation: "§303 · CATALYST BACKHAUL ACCEPTED · CARRIER-DISPATCHED · NEXT-CHAIN 6/N",
                         title: "Tender accepted by ME",
                         chainPill: "§297 RECEIVED · §298 STAGED · §302 ACCEPTED · §303 DISPATCH LOCKED")
        case .pickupWatch:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · PICKUP-WATCH",
                         citation: "§307 · CATALYST PICKUP-WATCH-ARMED · CARRIER-DISPATCHED · NEXT-CHAIN 10/N",
                         title: "Pickup watch armed for ME",
                         chainPill: "§302 ACCEPTED · §303 DISPATCH LOCKED · §306 DVIR IN PROGRESS · §307 WATCH ARMED")
        case .onSite:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · PICKUP",
                         citation: "§321 · CATALYST PICKUP-ON-SITE-ACKED · QUARTET 2/4 · NEXT-CHAIN 24/N",
                         title: "ME on-site at pickup",
                         chainPill: "§303 DISPATCH LOCKED · §307 WATCH ARMED · §320 DVIR COMPLETE · §321 ON-SITE ACKED")
        case .inTransit:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · IN-TRANSIT",
                         citation: "§325 · CATALYST IN-TRANSIT-ACKED · QUARTET 2/4 · NEXT-CHAIN 28/N",
                         title: "ME in transit",
                         chainPill: "§321 ON-SITE · §322 LOADING · §324 SEAL CONFIRMED · §325 IN-TRANSIT ACKED")
        case .deliveryApproach:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · DELIVERY · 2/4",
                         citation: "§329 · CATALYST DELIVERY-ACKED · QUARTET 2/4 · NEXT-CHAIN 32/N",
                         title: "ME approaching delivery",
                         chainPill: "§325 IN-TRANSIT · §327 GATE-WATCH ARMED · §329 APPROACHING ACKED")
        case .atDelivery:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · AT-DELIVERY · 2/N",
                         citation: "§333 · CATALYST AT-DELIVERY-ACKED · SUB-AXIS 2/N · NEXT-CHAIN 36/N",
                         title: "ME at delivery gate",
                         chainPill: "§329 APPROACHING · §331 GATE-IN ARMED · §333 AT-DELIVERY ACKED")
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

    // MARK: - Live-bound display helpers (honest "-"/"—" fallback)

    /// Real load number, or "-" until resolved. No invented "LD-BH7C3A".
    private var loadNumberDisplay: String {
        let n = load?.loadNumber?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "-" : n
    }

    /// Carrier (catalyst) display name from the resolved party object —
    /// companyName, then user name. "-" when no party is set. No AURORA.
    private var carrierDisplay: String {
        if let c = load?.catalyst?.companyName?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        if let n = load?.catalyst?.name?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        return "-"
    }

    /// Carrier MC# from the party object ("MC-942008" only if real). "—".
    private var carrierMC: String {
        if let mc = load?.catalyst?.mcNumber?.trimmingCharacters(in: .whitespaces), !mc.isEmpty { return "MC-\(mc)" }
        return "—"
    }

    /// Carrier USDOT# from the party object. "—" when unset. No "3 194 882".
    private var carrierDOT: String {
        if let dot = load?.catalyst?.dotNumber?.trimmingCharacters(in: .whitespaces), !dot.isEmpty { return "USDOT \(dot)" }
        return "—"
    }

    /// Carrier initials disc — real party initials, else "ME" placeholder
    /// disc text only (no fabricated name). "—" when neither resolves.
    private var carrierInitials: String {
        if let i = load?.catalyst?.initials?.trimmingCharacters(in: .whitespaces), !i.isEmpty { return i }
        return "—"
    }

    /// Nested {city,state} lane. Server sends "" (not nil) when missing.
    /// "—" placeholders per endpoint; nil when the whole lane is empty.
    private var laneDisplay: String? {
        let o = [load?.pickupLocation?.city, load?.pickupLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        let d = [load?.deliveryLocation?.city, load?.deliveryLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        guard !o.isEmpty || !d.isEmpty else { return nil }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }

    /// Equipment / trailer type — "—" when the shipper never specified.
    private var equipmentDisplay: String {
        let eq = load?.equipmentType?.trimmingCharacters(in: .whitespaces) ?? ""
        return eq.isEmpty ? "—" : eq
    }

    /// Subhead = real carrier · MC · load#. No persona.
    private var subhead: String {
        "\(carrierDisplay) · \(carrierMC) · \(loadNumberDisplay)"
    }

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
            Text(subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CBConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                // Pill copy is the real load context (carrier · load# ·
                // lifecycle stage) — no margin/ETA/seal fabrications.
                Text("\(carrierDisplay) · \(loadNumberDisplay) · \(c.title)")
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text("\(loadNumberDisplay) · \(laneDisplay ?? "—") · \(equipmentDisplay)")
                    .font(.caption2).foregroundStyle(palette.textSecondary)
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
                    .overlay(Text(carrierInitials).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    // Real carrier name from the catalyst party object.
                    Text("\(carrierDisplay) · carrier-dispatched").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    // USDOT · MC from the party object; "—" when unset. No
                    // "margin $172" — there is no margin source on getById.
                    Text("\(carrierDOT) · \(carrierMC) dispatch").font(.caption2).foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        // KPI tiles bind to real getById fields (lane / equipment / load#)
        // or render honest "—"/"-". No margin / ETA / seal / dock / window
        // fabrications — none of those have a source on loads.getById.
        let lane = laneDisplay ?? "—"
        let equip = equipmentDisplay
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .tender:
                return [
                    ("STATE",  "STAGED",            "awaiting accept",          .blue),
                    ("LANE",   lane,                 "backhaul",                .blue),
                    ("EQUIP",  equip,                "trailer",                 .blue),
                    ("LOAD",   loadNumberDisplay,    "tendered",                .blue),
                ]
            case .accepted:
                return [
                    ("STATE",  "ACCEPTED",          "dispatch locked",          .green),
                    ("LANE",   lane,                 "backhaul",                .green),
                    ("EQUIP",  equip,                "trailer",                 .blue),
                    ("LOAD",   loadNumberDisplay,    "awarded",                 .green),
                ]
            case .pickupWatch:
                return [
                    ("WATCH",  "ARMED",             "pickup watch",             .green),
                    ("LANE",   lane,                 "backhaul",                .blue),
                    ("EQUIP",  equip,                "trailer",                 .blue),
                    ("LOAD",   loadNumberDisplay,    "dispatched",              .green),
                ]
            case .onSite:
                return [
                    ("STATE",  "ON-SITE",           "at pickup",                .blue),
                    ("LANE",   lane,                 "backhaul",                .green),
                    ("EQUIP",  equip,                "trailer",                 .blue),
                    ("LOAD",   loadNumberDisplay,    "loading",                 .green),
                ]
            case .inTransit:
                return [
                    ("STATE",  "IN-TRANSIT",        "en route",                 .blue),
                    ("LANE",   lane,                 "backhaul",                .blue),
                    ("EQUIP",  equip,                "trailer",                 .blue),
                    ("LOAD",   loadNumberDisplay,    "rolling",                 .green),
                ]
            case .deliveryApproach:
                return [
                    ("STATE",  "APPROACHING",       "delivery",                 .green),
                    ("LANE",   lane,                 "backhaul",                .blue),
                    ("EQUIP",  equip,                "trailer",                 .blue),
                    ("LOAD",   loadNumberDisplay,    "approaching",             .green),
                ]
            case .atDelivery:
                return [
                    ("STATE",  "AT-DELIVERY",       "gate-in acked",            .green),
                    ("LANE",   lane,                 "backhaul",                .green),
                    ("EQUIP",  equip,                "trailer",                 .green),
                    ("LOAD",   loadNumberDisplay,    "at gate",                 .green),
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

    private var nextStepCard: some View {
        // Stage-narrative scaffold (no fabricated personas / dock numbers /
        // ETAs / mileage — those carry no getById source).
        let copy: String = {
            switch kind {
            case .tender:           return "Carrier has a window to accept this backhaul tender. If it expires, dispatch releases the tender back to the carrier pool."
            case .accepted:         return "Dispatch locked. DVIR opens ahead of pickup; ESang queues the pretrip on the driver's watch."
            case .pickupWatch:      return "Watch armed. The -30 ping confirms the driver is en-route to the pickup."
            case .onSite:           return "Driver loading at pickup. Seal confirmation arms the IN-TRANSIT ack on gate-out."
            case .inTransit:        return "Driver en route on the backhaul leg. Watch ETA drift; ESang nudges if HOS tightens."
            case .deliveryApproach: return "Approach acked. Confirm receiver dock + paperwork; gate-in arms on arrival."
            case .atDelivery:       return "Gate-in cleared. POD chain arms on dock placement."
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
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* leaves all values honest "-"/"—" */ }
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
