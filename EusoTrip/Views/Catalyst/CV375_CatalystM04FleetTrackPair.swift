//
//  CV375_CatalystM04FleetTrackPair.swift
//  EusoTrip — Catalyst · M-04 fleet-track pair (CV375-CV376).
//
//  Pixel-match to:
//    375 Catalyst In Transit Fleet Track Cel M04
//    376 Catalyst At Delivery Fleet Track Cel M04
//
//  Closes the M-04 scenario chain (CV369-CV376). Both screens track the
//  dispatched fleet over the live load's lane. Body reads `loads.getById`
//  (parties, rate, distance, lane, equipment). Every rendered business
//  value binds to the live fetched record; anything without a live source
//  (live progress fraction, live ETA) renders an honest "-"/"—". Bottom
//  nav frozen.
//
//  Honest binding parity with the corrected sibling
//  DL133_DriverCELM04DVIRContinuationOctet (loads.getById: String
//  top-level id, nested pickup/delivery {city,state}, party objects with
//  numeric ids) and DL126_DriverCELM04Septet.
//

import SwiftUI

private struct CFLoadCtx: Decodable, Hashable {
    // Top-level load id is a String on the wire (loads.getById -> String(load.id));
    // decoding as Int throws typeMismatch and fails the WHOLE decode -> blank screen.
    // pickup/delivery are nested {city,state} objects (NOT flat city fields).
    let id: String?
    let loadNumber: String?
    let pickupLocation: CFLoc?
    let deliveryLocation: CFLoc?
    let rate: String?
    let distance: Double?
    let equipmentType: String?
    let driver: CFParty?
    let catalyst: CFParty?
    let shipper: CFParty?
    struct CFLoc: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct CFParty: Decodable, Hashable {
        let id: Int?            // party (user/company) id is numeric on the wire
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
    }
}

enum CatalystM04TrackKind: String {
    case inTransit, atDelivery
}

/// Stage-only labels — no scenario data baked in. The view body composes
/// these with the live `load` (lane, parties, equipment, distance) at
/// render time. Carries NO fabricated lane / ETA / progress / carrier.
private struct CTConfig {
    let eyebrowStage: String   // "IN-TRANSIT · FLEET-TRACK" / "AT-DELIVERY · FLEET-TRACK"
    let citation: String       // canonical stage citation
    let title: String          // UX title
    let subhead: String        // stage state line (no scenario data)
    let stageNote: String      // composed after carrier + loadNumber
    let stage: String          // "IN-TRANSIT" / "AT-DELIVERY"
    let isDelivery: Bool
}

private extension CatalystM04TrackKind {
    var config: CTConfig {
        switch self {
        case .inTransit:
            return .init(eyebrowStage: "IN-TRANSIT · FLEET-TRACK",
                         citation: "§395 · CHAIN PORT 20/N · TRANSIT · 2/4 · FLEET ROLLING",
                         title: "In-transit · fleet rolling",
                         subhead: "IN-TRANSIT · fleet en route",
                         stageNote: "fleet rolling · in-transit · live track armed",
                         stage: "IN-TRANSIT",
                         isDelivery: false)
        case .atDelivery:
            return .init(eyebrowStage: "AT-DELIVERY · FLEET-TRACK",
                         citation: "§399 · CHAIN PORT 21/N · DELIVERY · 2/4 · FLEET ARRIVED",
                         title: "At delivery · fleet arrived",
                         subhead: "AT-DELIVERY · fleet on receiver dock",
                         stageNote: "fleet arrived · at-delivery · receiver-bay queue armed",
                         stage: "AT-DELIVERY",
                         isDelivery: true)
        }
    }
}

private struct CatalystM04TrackShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",          isCurrent: false),
                          NavSlot(label: "Fleet", systemImage: "truck.box.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Fleet",  systemImage: "truck.box.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct CatalystM04TrackBody: View {
    let loadId: String
    let kind: CatalystM04TrackKind

    @Environment(\.palette) private var palette
    @State private var load: CFLoadCtx?

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
    private var equipDisplay: String { load?.equipmentType ?? "-" }
    private var distanceDisplay: String { Self.distanceDisplay(load?.distance) }

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                progressCard(c)
                identityRow
                kpiGrid(c)
                nextStepCard(c)
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private func header(_ c: CTConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DISPATCH · \(c.eyebrowStage) · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            // Lane · equipment · distance from the live record; "—" leg-state has no live source.
            Text("\(laneDisplay ?? "-") · \(equipDisplay) · \(distanceDisplay)")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CTConfig) -> some View {
        let driverIni = load?.driver?.initials ?? "-"
        let dispIni   = load?.catalyst?.initials ?? "-"
        let shipIni   = load?.shipper?.initials ?? "-"
        return LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("\(carrierCodeDisplay) · \(loadNumberDisplay) · \(c.stageNote)")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(loadNumberDisplay) · \(laneDisplay ?? "-") · \(driverIni) driver · \(dispIni) dispatch · \(shipIni) shipper")
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Leg progress has NO live source (no live odometer/position feed on
    /// loads.getById) → renders honest "—" with an empty track; never a
    /// fabricated 62/245 fraction.
    private func progressCard(_ c: CTConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("LEG PROGRESS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("— / \(distanceDisplay)").font(.caption2.weight(.semibold)).foregroundStyle(palette.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(palette.bgPage).frame(height: 8)
                        // No live progress fraction → no fill.
                    }
                }
                .frame(height: 8)
                Text("\(carrierCodeDisplay) · \(c.stage) · ETA —").font(.caption2).foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var identityRow: some View {
        let dispIni     = load?.catalyst?.initials ?? "-"
        let dispName    = load?.catalyst?.name ?? "-"
        let carrierFull = load?.catalyst?.companyName ?? load?.catalyst?.name ?? "-"
        let mc          = load?.catalyst?.mcNumber.map { "MC-\($0)" } ?? "-"
        let driverName  = load?.driver?.name ?? "-"
        let shipperName = load?.shipper?.name ?? "-"
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(dispIni).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(carrierCodeDisplay) · \(dispName) · dispatcher")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("\(carrierFull) · \(mc) · \(driverName) (driver) · \(shipperName) (shipper) · \(equipDisplay)")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: CTConfig) -> some View {
        let lane = laneDisplay ?? "-"
        let dist = distanceDisplay
        let equip = equipDisplay
        let payout = Self.payoutDisplay(load?.rate)
        let kpis: [(String, String, String, Color)] = [
            // ETA + leg progress have no live source → honest "—".
            ("ETA",    "—",     c.isDelivery ? "appt · no live feed" : "rolling · no live feed", .blue),
            ("DIST",   dist,    lane,                                                            .blue),
            ("STAGE",  c.stage, equip,                                                           .green),
            ("PAYOUT", payout,  "LOCKED · \(carrierCodeDisplay) · §371",                         .green),
        ]
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

    private func nextStepCard(_ c: CTConfig) -> some View {
        let copy: String = {
            switch kind {
            case .inTransit:  return "\(carrierCodeDisplay) fleet is in-transit on \(laneDisplay ?? "the awarded lane"). ESang arms a drift nudge when a live ETA feed is available."
            case .atDelivery: return "\(carrierCodeDisplay) fleet arrived at the delivery stop on \(laneDisplay ?? "the awarded lane"). Receiver-bay queue arms on dock placement."
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

    /// Format the load's rate (decimal string from server) as a payout
    /// display. Falls back to "-" when missing/invalid.
    private static func payoutDisplay(_ rate: String?) -> String {
        guard let r = rate, let n = Double(r), n > 0 else { return "-" }
        let v = n.rounded()
        return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
    }

    /// Format the load's distance in miles. Falls back to "-".
    private static func distanceDisplay(_ d: Double?) -> String {
        guard let d, d > 0 else { return "-" }
        return "\(Int(d.rounded())) mi"
    }
}

// MARK: - Screens (CV375-CV376)

struct CatalystM04InTransitTrackScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystM04TrackShell(theme: theme) { CatalystM04TrackBody(loadId: loadId, kind: .inTransit) } }
}
struct CatalystM04AtDeliveryTrackScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystM04TrackShell(theme: theme) { CatalystM04TrackBody(loadId: loadId, kind: .atDelivery) } }
}

// MARK: - Previews

#Preview("CV375 Transit · Dark")   { CatalystM04InTransitTrackScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV376 Delivered · Light"){ CatalystM04AtDeliveryTrackScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
