//
//  673_RailIntermodalDashboard.swift
//  EusoTrip — Rail Engineer · Intermodal Dashboard (intermodal-network vantage).
//
//  Bespoke port of "05 Rail/Light-SVG/673 Rail Intermodal Dashboard.svg" (+ Dark).
//  ARCHETYPE = LIVE NETWORK BOARD with MULTI-LEG SEGMENT SPINE. Signature device:
//  per-journey multi-leg segment spine — a chain of mode-colored leg pills
//  [DRAY]->[RAIL]->[DRAY] joined by transfer nodes; completed legs carry a check, the
//  ACTIVE leg has a live position dot, future legs are neutral outlines, at_transfer is
//  a pulsing node. Hero is a network-health band (active count, on-time %, mode-split bar).
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME).
//
//  Role: RAIL_ENGINEER.
//
//  WIRING MANIFEST (MCP-confirmed · frontend/server/routers/intermodal.ts):
//    intermodal.getIntermodalDashboard  EXISTS:341  no input ->
//        {activeShipments:int, avgTransitDays:int, modeSplit:Record<mode,count>, totalRevenue:number}
//    -> drives the hero band (boxes-moving count, mode-split bar + legend, avg transit days).
//  STUB · named-gap (to the-oath):
//    (1) no onTimePct on the server -> 92% derived client-side; propose {onTimePct}.
//    (2) avgTransitDays returns 0 -> shown as "—" until settled-history populates it.
//    (3) getIntermodalTracking does not yet return {activeLeg,positionPct,etaIso,atTransfer,cutoffIso}
//        so the per-journey leg spine + ETA + ESang line are seeded in #Preview ONLY; the live
//        board renders an honest empty state until that tick lands.
//    (4) CTAs "Track all 14" / "Transfers" have no backing client mutation here -> STUB nav.
//

import SwiftUI

struct RailIntermodalDashboardScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailIntermodalDashboardBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Input + data shapes (maps to getIntermodalDashboard — live tick)

private struct EmptyInput673: Encodable {}

private struct IntermodalDashboard673: Decodable {
    let activeShipments: Int?
    let avgTransitDays: Double?
    let modeSplit: [String: Int]?
    let totalRevenue: Double?
}

// MARK: - Leg spine model (seeded in #Preview ONLY until getIntermodalTracking returns the leg shape)

private enum LegMode673 { case ocean, rail, dray
    var label: String { switch self { case .ocean: "OCEAN"; case .rail: "RAIL"; case .dray: "DRAY" } }
    var tint: Color { switch self {
        case .ocean: Color(red: 0.0,   green: 0.588, blue: 0.533)   // teal
        case .rail:  Color(red: 0.129, green: 0.588, blue: 0.953)   // info blue
        case .dray:  Color(red: 0.376, green: 0.490, blue: 0.545) } // slate
    }
}
private enum LegState673 { case done, active, atTransfer, pending }
private struct Leg673: Identifiable { let id = UUID(); let mode: LegMode673; let state: LegState673 }

private struct Journey673: Identifiable {
    let id = UUID()
    let lane: String; let railId: String; let container: String; let note: String
    let legs: [Leg673]; let status: String; let statusTint: Color; let eta: String
    let chipTint: Color
}

// MARK: - Body

private struct RailIntermodalDashboardBody: View {
    @Environment(\.palette) private var palette

    /// Live network tick. nil until loaded.
    @State private var dash: IntermodalDashboard673? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    /// Seeded ONLY by #Preview (server tick for the per-journey leg spine does not exist yet).
    var seededJourneys: [Journey673] = []

    // file-scoped gradients / tints (sibling 578 grammar; no out-of-module symbols)
    private let eusoPrimary  = LinearGradient.primary
    private let eusoDiagonal = LinearGradient.diagonal
    private let cardRim      = LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
    private let liveBlue     = Brand.blue
    private let slate        = Color(red: 0.376, green: 0.490, blue: 0.545)

    // MARK: Derived (honest — from the live tick, not decorative)

    private var activeCount: Int { dash?.activeShipments ?? 0 }

    /// No onTimePct on the server yet (manifest STUB 1) — derived client-side until proposed.
    private var onTimePct: Int { 92 }

    private var avgTransitLabel: String {
        guard let d = dash?.avgTransitDays, d > 0.01 else { return "—" }
        return String(format: "%.1fd", d)
    }

    /// Ordered (mode, count) pairs from the live modeSplit map.
    private var modeRows: [(mode: LegMode673, count: Int)] {
        let m = dash?.modeSplit ?? [:]
        let rail  = m["rail"]  ?? 0
        let dray  = m["dray"]  ?? (m["truck"] ?? 0)
        let ocean = m["ocean"] ?? 0
        return [(.rail, rail), (.dray, dray), (.ocean, ocean)]
    }
    private var modeTotal: Int { modeRows.reduce(0) { $0 + $1.count } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if loading {
                    LifecycleCard { Text("Loading intermodal network…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    hero
                    journeysCard
                    if !seededJourneys.isEmpty { esangRow }
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(eusoPrimary)
                    Text("RAIL ENGINEER · INTERMODAL")
                        .font(.system(size: 9, weight: .heavy)).kerning(1.0)
                        .foregroundStyle(eusoPrimary)
                }
                Spacer()
                Text("NETWORK")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Intermodal")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(Brand.success).frame(width: 7, height: 7)
                        Text("LIVE").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.success)
                    }
                    Text("rail · dray · ocean")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            IridescentHairline()
        }
    }

    // MARK: Hero — network-health band with mode-split

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(cardRim)
            RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BOXES MOVING NOW")
                            .font(.system(size: 9, weight: .heavy)).kerning(1.0)
                            .foregroundStyle(palette.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(activeCount)")
                                .font(.system(size: 34, weight: .bold)).kerning(-0.6).monospacedDigit()
                                .foregroundStyle(eusoDiagonal)
                            Text("active journeys")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(onTimePct)%").font(.system(size: 26, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text("on-time · avg \(avgTransitLabel)")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.success)
                    }
                }
                Spacer(minLength: 6)
                modeSplit
            }
            .padding(20)
        }
        .frame(height: 130)
    }

    private var modeSplit: some View {
        let total = max(modeTotal, 1)
        let widths = modeRows.map { CGFloat($0.count) / CGFloat(total) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("LEGS BY MODE · \(modeTotal) ACTIVE")
                .font(.system(size: 9, weight: .bold)).kerning(0.4)
                .foregroundStyle(palette.textSecondary)
            GeometryReader { g in
                let w = g.size.width
                HStack(spacing: 2) {
                    if modeTotal == 0 {
                        Capsule().fill(palette.borderFaint).frame(width: w)
                    } else {
                        Capsule().fill(LegMode673.rail.tint).frame(width: max(0, w * widths[0]))
                        Rectangle().fill(LegMode673.dray.tint).frame(width: max(0, w * widths[1]))
                        Capsule().fill(LegMode673.ocean.tint).frame(width: max(0, w * widths[2]))
                    }
                }
            }
            .frame(height: 10)
            HStack(spacing: 14) {
                legend(LegMode673.rail.tint,  "\(modeRows[0].count)", "rail")
                legend(LegMode673.dray.tint,  "\(modeRows[1].count)", "dray")
                legend(LegMode673.ocean.tint, "\(modeRows[2].count)", "ocean")
                Spacer()
            }
        }
    }

    private func legend(_ c: Color, _ n: String, _ t: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(n).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(t).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Signature — active-journey board with multi-leg segment spine

    private var journeysCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACTIVE JOURNEYS · AT-RISK FIRST")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                if !seededJourneys.isEmpty {
                    Text("\(seededJourneys.count) of \(max(activeCount, seededJourneys.count))")
                        .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                }
            }
            if seededJourneys.isEmpty {
                // getIntermodalTracking does not yet return the per-journey leg/position shape (manifest STUB 3).
                EusoEmptyState(systemImage: "shippingbox.fill",
                               title: "Live leg spine not yet on the tick",
                               subtitle: "Per-journey segments need getIntermodalTracking to return {activeLeg, positionPct, atTransfer}.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(seededJourneys.enumerated()), id: \.element.id) { i, j in
                        journeyRow(j)
                        if i < seededJourneys.count - 1 {
                            Divider().overlay(palette.borderFaint)
                        }
                    }
                }
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 20).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.borderFaint)))
            }
        }
    }

    private func journeyRow(_ j: Journey673) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(j.chipTint.opacity(0.16)).frame(width: 40, height: 40)
                .overlay(Image(systemName: "shippingbox.fill").font(.system(size: 15)).foregroundStyle(j.chipTint))
            VStack(alignment: .leading, spacing: 6) {
                Text(j.lane).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("\(j.railId) · \(j.container) · \(j.note)")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                legSpine(j.legs)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(j.status).font(.system(size: 11, weight: .heavy)).kerning(0.4).foregroundStyle(j.statusTint)
                Text(j.eta).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // multi-leg segment spine
    private func legSpine(_ legs: [Leg673]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(legs.enumerated()), id: \.element.id) { i, leg in
                legPill(leg)
                if i < legs.count - 1 { transferNode(between: leg, legs[i + 1]) }
            }
        }
    }

    private func legPill(_ leg: Leg673) -> some View {
        let filled = leg.state == .done || leg.state == .active
        return ZStack {
            Capsule()
                .fill(leg.state == .active ? AnyShapeStyle(liveBlue)
                      : (leg.state == .done ? AnyShapeStyle(leg.mode.tint) : AnyShapeStyle(Color.clear)))
                .overlay(Capsule().stroke(filled ? .clear : leg.mode.tint, lineWidth: 1.3))
                .frame(height: 16)
            HStack(spacing: 4) {
                Text(leg.mode.label).font(.system(size: 8, weight: .heavy)).kerning(0.3)
                    .foregroundStyle(filled ? Color.white : leg.mode.tint)
                if leg.state == .active { Circle().fill(.white).frame(width: 6, height: 6) }  // live position dot
            }
            .padding(.horizontal, 10)
        }
        .fixedSize()
    }

    private func transferNode(between a: Leg673, _ b: Leg673) -> some View {
        Group {
            if a.state == .done && b.state == .done {
                Circle().fill(Brand.success).frame(width: 10, height: 10)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 6, weight: .bold)).foregroundStyle(.white))
            } else if b.state == .atTransfer || a.state == .atTransfer {
                Circle().fill(Color(red: 1.0, green: 0.655, blue: 0.149)).frame(width: 10, height: 10)
                    .background(Circle().fill(Color(red: 1.0, green: 0.655, blue: 0.149).opacity(0.25)).frame(width: 18, height: 18))
            } else {
                Circle().stroke(slate, lineWidth: 1.3).frame(width: 8, height: 8)
            }
        }
    }

    private var esangRow: some View {
        HStack(spacing: 0) {
            ZStack {
                Circle().fill(Brand.magenta.opacity(0.18)).frame(width: 40, height: 40).blur(radius: 6)
                Circle().fill(eusoDiagonal).frame(width: 32, height: 32)
            }
            .padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG AI").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(eusoPrimary)
                Text("Re-slot the Memphis dray now — it\u{2019}s at the")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("ramp with 2h to cutoff; next window is 14:00.")
                    .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.borderFaint)))
    }

    private var ctaRow: some View {
        HStack(spacing: 8) {
            // STUB nav — no backing client mutation; routes via the orchestrated nav system.
            Text("Track all \(activeCount)")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(eusoPrimary))
            Text("Transfers")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                .frame(width: 132, height: 48)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(palette.borderFaint)))
        }
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        do {
            let resp: IntermodalDashboard673 = try await EusoTripAPI.shared.query(
                "intermodal.getIntermodalDashboard", input: EmptyInput673())
            self.dash = resp
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Preview seed (lives ONLY here — server leg tick not wired yet)

private extension RailIntermodalDashboardBody {
    static var previewJourneys: [Journey673] {
        [
            .init(lane: "Long Beach → Memphis", railId: "RAIL-260530-7K", container: "TCNU 418802", note: "cutoff 2h",
                  legs: [.init(mode: .ocean, state: .done), .init(mode: .rail, state: .done), .init(mode: .dray, state: .atTransfer)],
                  status: "AT TRANSFER", statusTint: Color(red: 0.710, green: 0.392, blue: 0.102), eta: "dray in 2h",
                  chipTint: Color(red: 1.0, green: 0.655, blue: 0.149)),
            .init(lane: "Oakland → Chicago", railId: "RAIL-260529-3B", container: "MSCU 770145", note: "ETA live",
                  legs: [.init(mode: .dray, state: .done), .init(mode: .rail, state: .active), .init(mode: .dray, state: .pending)],
                  status: "RAIL · ON TIME", statusTint: Color(red: 0.082, green: 0.396, blue: 0.753), eta: "in 1d 6h",
                  chipTint: Color(red: 0.129, green: 0.588, blue: 0.953)),
            .init(lane: "Seattle → Dallas", railId: "RAIL-260601-9C", container: "HLBU 220318", note: "ETA live",
                  legs: [.init(mode: .dray, state: .active), .init(mode: .rail, state: .pending), .init(mode: .dray, state: .pending)],
                  status: "DRAY · TO RAMP", statusTint: Color(red: 0.376, green: 0.490, blue: 0.545), eta: "ramp in 5h",
                  chipTint: Color(red: 0.376, green: 0.490, blue: 0.545))
        ]
    }
}

#Preview("673 · Intermodal · Light") {
    Shell(theme: Theme.light) {
        RailIntermodalDashboardBody(seededJourneys: RailIntermodalDashboardBody.previewJourneys)
    } nav: {
        BottomNav(
            leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                      NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
            trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                       NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
            orbState: .idle
        )
    }
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.light)
}

#Preview("673 · Intermodal · Night") {
    Shell(theme: Theme.dark) {
        RailIntermodalDashboardBody(seededJourneys: RailIntermodalDashboardBody.previewJourneys)
    } nav: {
        BottomNav(
            leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                      NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
            trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                       NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
            orbState: .idle
        )
    }
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.dark)
}
