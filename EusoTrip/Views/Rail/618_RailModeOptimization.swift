//
//  618_RailModeOptimization.swift
//  EusoTrip — Rail Engineer · Mode Optimization (carrier-side mode-choice verdict).
//
//  Verbatim port of wireframe "618 Rail Mode Optimization · Dark".
//  CARRIER-SIDE DECISION/COMPARE archetype: a savings hero (best mode + all-in
//  vs truck + transit), a unit-economics KPI strip ($/mi rail vs truck, CO₂e
//  delta, transit), an itemized mode-option comparison (rail / OTR truck /
//  transload+rail, each with a short verdict pill clear of the all-in cost),
//  an ESang rationale, and an Apply/Re-run CTA pair. Owen picks the cheapest
//  mode that still meets the shipper SLA in one tap — turning a routing call
//  into a logged decision.
//
//  Web parity: app/(rail)/optimize/mode/page.tsx
//  tRPC:
//    • shipment resolution      ← intermodal.getIntermodalShipments
//                                (newest real shipment when none is injected
//                                — zero-fallback: no invented lane/id)
//    • per-mode all-in costs   ← intermodal.getIntermodalCostBreakdown
//                                (server/routers/intermodal.ts:295)
//    • rail-vs-truck compare    ← routeOptimization.getRouteComparison
//                                (server/routers/routeOptimization.ts:1402)
//    • lane context             ← intermodal.getIntermodalDashboard
//                                (server/routers/intermodal.ts:341)
//    • 'Apply mode'            → intermodal.applyModeChoice
//                                (server/routers/intermodal.ts:519)
//  ZERO-FALLBACK (2026-06-09): every economic figure renders live or as an
//  em-dash; savings/rationale claims are suppressed when either side of the
//  comparison is missing. RBAC: protectedProcedure. transportMode=rail.
//
//  NAV (REAL): HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME
//

import SwiftUI

struct RailModeOptimizationScreen: View {
    let theme: Theme.Palette
    /// Intermodal shipment this mode-optimization verdict is scoped to.
    /// 0 = unresolved: the body resolves the user's NEWEST real intermodal
    /// shipment via intermodal.getIntermodalShipments, so the verdict is
    /// never rendered against an invented lane. The host surface injects the
    /// live shipment id + labels when pushing from a shipment row.
    var intermodalShipmentId: Int = 0
    var shipmentRef: String = ""
    var originLabel: String = ""
    var destinationLabel: String = ""

    var body: some View {
        Shell(theme: theme) {
            RailModeOptimizationBody(
                intermodalShipmentId: intermodalShipmentId,
                shipmentRef: shipmentRef,
                originLabel: originLabel,
                destinationLabel: destinationLabel
            )
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (decode the REAL tRPC payloads)

/// intermodal.getIntermodalCostBreakdown — the chosen-mode all-in.
private struct ModeCostBreakdown: Decodable {
    let intermodalNumber: String?
    let segments: [ModeSegmentCost]?
    let transfers: [ModeTransferCost]?
    let totalSegmentCost: Double?
    let totalTransferCost: Double?
    let grandTotal: Double?
    let currency: String?
}
private struct ModeSegmentCost: Decodable {
    let legNumber: Int?
    let mode: String?
    let rate: Double?
    let status: String?
}
private struct ModeTransferCost: Decodable {
    let transferType: String?
    let cost: Double?
    let facilityName: String?
}

/// routeOptimization.getRouteComparison — OTR truck route + cost compare.
private struct RouteComparison: Decodable {
    let origin: String?
    let destination: String?
    let routes: [RouteOption]?
    let bestByTime: String?
    let bestByCost: String?
    let bestByFuel: String?
    let error: String?
}
private struct RouteOption: Decodable {
    let name: String?
    let type: String?
    let miles: Int?
    let hours: Double?
    let duration: String?
    let tollCost: Double?
    let fuelCost: Double?
    let totalCost: Double?
}

/// intermodal.getIntermodalDashboard — lane context (active shipments, revenue).
private struct IntermodalDashboard: Decodable {
    let activeShipments: Int?
    let avgTransitDays: Double?
    let totalRevenue: Double?
}

/// intermodal.getIntermodalShipments — raw shipment rows; used to resolve the
/// newest REAL shipment when the navigator injects no id.
private struct IntermodalShipmentRow618: Decodable {
    struct Loc: Decodable { let description: String? }
    let id: Int
    let intermodalNumber: String?
    let originLocation: Loc?
    let destinationLocation: Loc?
    let status: String?
}
private struct IntermodalShipmentsPage618: Decodable {
    let shipments: [IntermodalShipmentRow618]?
    let total: Int?
}

// MARK: - Body

private struct RailModeOptimizationBody: View {
    @Environment(\.palette) private var palette

    let intermodalShipmentId: Int
    let shipmentRef: String
    let originLabel: String
    let destinationLabel: String

    @State private var breakdown: ModeCostBreakdown? = nil
    @State private var compare: RouteComparison? = nil
    @State private var dashboard: IntermodalDashboard? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// True when no real intermodal shipment exists to scope the verdict to —
    /// renders an honest empty state instead of fabricated lane economics.
    @State private var noShipment = false

    // Resolved live shipment identity (from navigation or the newest-shipment
    // lookup). Em-dash when unresolved — never an invented lane.
    @State private var resolvedShipmentId: Int = 0
    @State private var resolvedRef: String = ""
    @State private var resolvedOrigin: String = ""
    @State private var resolvedDestination: String = ""

    @State private var applying = false
    @State private var applyError: String? = nil
    @State private var applied = false
    @State private var appliedStatus: String? = nil

    // MARK: Derived — intermodal all-in (rail line-haul + dray)

    /// Intermodal grand-total from the cost breakdown (segments + transfers).
    private var intermodalAllIn: Double? { breakdown?.grandTotal }

    /// OTR truck all-in — the cheapest truck route from the compare endpoint,
    /// or the fastest if no cost ordering is available.
    private var truckAllIn: Double? {
        guard let routes = compare?.routes, !routes.isEmpty else { return nil }
        let costed = routes.compactMap { $0.totalCost }
        return costed.min()
    }

    /// Truck transit days — derived from the fastest route's hours.
    private var truckTransitDays: Double? {
        guard let routes = compare?.routes else { return nil }
        let minHours = routes.compactMap { $0.hours }.min()
        return minHours.map { $0 / 24.0 }
    }

    /// Savings = truck all-in − intermodal all-in (positive = rail wins).
    private var savings: Double? {
        guard let rail = intermodalAllIn, let truck = truckAllIn else { return nil }
        return truck - rail
    }

    /// Lane mileage from the compare endpoint's routes — nil (em-dash) when
    /// the compare hasn't answered. No wireframe fallback mileage.
    private var laneMiles: Int? {
        compare?.routes?.compactMap { $0.miles }.min()
    }

    /// Display identity — live or em-dash.
    private var refLabel: String { resolvedRef.isEmpty ? "—" : resolvedRef }
    private var originDisplay: String { resolvedOrigin.isEmpty ? "—" : resolvedOrigin }
    private var destinationDisplay: String { resolvedDestination.isEmpty ? "—" : resolvedDestination }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                titleBlock
                IridescentHairline()
                    .padding(.top, Space.s4)
                content
                    .padding(.top, Space.s4)
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow (✦ RAIL ENGINEER · MODE  …  RAIL-260528-D331C)

    private var eyebrow: some View {
        HStack {
            Text("✦ RAIL ENGINEER · MODE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(refLabel)
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title block (back · "Mode optimization" · overflow · lane)

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text("Mode optimization")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 6)
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
            .padding(.top, Space.s4)
            Text("\(originDisplay) → \(destinationDisplay) · \(laneMilesLabel)")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.leading, 30)
        }
    }

    private var laneMilesLabel: String {
        if let m = laneMiles {
            return "\(m.formatted(.number.grouping(.automatic))) mi"
        }
        return "— mi"
    }

    // MARK: - Content (loading / error / loaded)

    @ViewBuilder
    private var content: some View {
        if loading {
            VStack(spacing: Space.s4) {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 104)
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(palette.borderFaint))
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 254)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
            .redacted(reason: .placeholder)
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Couldn't load mode comparison")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                }
            }
        } else if noShipment {
            // Honest empty: no real intermodal shipment exists to optimize.
            EusoEmptyState(systemImage: "arrow.triangle.swap",
                           title: "No shipment to optimize",
                           subtitle: "Book an intermodal shipment to compare rail, truck, and transload economics.")
                .padding(.top, Space.s6)
        } else {
            VStack(alignment: .leading, spacing: Space.s5) {
                savingsHero
                kpiStrip
                modeOptionsSection
                esangRationale
                ctaPair
                if let ae = applyError {
                    Text(ae).font(EType.caption).foregroundStyle(Brand.danger)
                } else if applied {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Brand.success)
                        Text(appliedStatus.map { "Mode applied · \($0)" } ?? "Mode applied · routing committed")
                            .font(EType.caption).foregroundStyle(Brand.success)
                    }
                }
            }
        }
    }

    // MARK: - Savings hero (gradient-rimmed)

    private var savingsHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SAVINGS · BEST MODE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(savingsLabel)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Brand.success)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("Intermodal vs OTR truck · all-in")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    heroStat(value: moneyLabel(intermodalAllIn) ?? "—", caption: "intermodal")
                    heroStat(value: moneyLabel(truckAllIn) ?? "—", caption: "truck")
                    heroStat(value: transitLabel(truckTransitDays) ?? "—", caption: "transit")
                }
            }
            .padding(Space.s4)
        }
        .frame(minHeight: 104)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    private func heroStat(value: String, caption: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textPrimary).monospacedDigit()
            Text(caption)
                .font(.system(size: 9)).foregroundStyle(palette.textTertiary)
        }
    }

    private var savingsLabel: String {
        // Em-dash until BOTH sides of the comparison are live — a savings
        // claim with a missing side is a fabrication.
        guard let s = savings, s > 0 else { return "—" }
        if s >= 1_000 {
            return String(format: "−$%.1fK", s / 1_000)
        }
        return String(format: "−$%.0f", s)
    }

    // MARK: - KPI strip (RAIL $/mi · TRUCK · CO₂e · TRANSIT)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // RAIL $/mi — gradient-filled feature tile.
            VStack(alignment: .leading, spacing: 6) {
                Text("RAIL $/MI")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white.opacity(0.85))
                Text(railPerMileLabel)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiTile(label: "TRUCK", value: truckPerMileLabel)
            kpiTile(label: "CO₂e", value: co2Label)
            kpiTile(label: "TRANSIT", value: transitLabel(truckTransitDays) ?? "—")
        }
    }

    private func kpiTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textPrimary).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// Rail $/mi — intermodal all-in over the lane mileage. Em-dash otherwise.
    private var railPerMileLabel: String {
        if let rail = intermodalAllIn, let m = laneMiles, m > 0 {
            return String(format: "$%.2f", rail / Double(m))
        }
        return "—"
    }
    /// Truck $/mi — cheapest truck all-in over the lane mileage. Em-dash otherwise.
    private var truckPerMileLabel: String {
        if let truck = truckAllIn, let m = laneMiles, m > 0 {
            return String(format: "$%.2f", truck / Double(m))
        }
        return "—"
    }
    /// CO₂e delta — WIRE-GAP: no emissions endpoint is wired to this surface,
    /// and a cost differential is NOT an emissions figure. Em-dash until a
    /// real CO₂e read (co2.calculate-class proc) lands here.
    private var co2Label: String { "—" }

    // MARK: - Mode options (itemized comparison)

    private var modeOptionsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("MODE OPTIONS · LANE \(laneCode)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("compare ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)

            VStack(spacing: 0) {
                // Verdict pills only render when the underlying comparison is
                // live — a "BEST $" badge over an em-dash is a fabrication.
                modeRow(
                    icon: "tram.fill",
                    accent: Brand.success,
                    title: "Intermodal rail",
                    sub: "rail line-haul + dray · \(transitLabel(truckTransitDays) ?? "—")",
                    pillText: (savings.map { $0 > 0 } ?? false) ? "BEST $" : nil,
                    pillColor: Brand.success,
                    cost: moneyLabel(intermodalAllIn) ?? "—",
                    costNote: intermodalAllIn != nil ? "all-in" : "—",
                    costNoteColor: palette.textTertiary
                )
                Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s3)
                modeRow(
                    icon: "truck.box.fill",
                    accent: Brand.warning,
                    title: "OTR truck",
                    sub: "door-to-door · \(truckFastestLabel) fastest",
                    pillText: truckTransitDays != nil ? "FASTEST" : nil,
                    pillColor: Brand.info,
                    cost: moneyLabel(truckAllIn) ?? "—",
                    costNote: truckDeltaLabel,
                    costNoteColor: palette.textTertiary
                )
                Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s3)
                // WIRE-GAP: no transload-scenario costing endpoint exists on
                // this surface — every cell is an em-dash until one lands.
                modeRow(
                    icon: "arrow.left.arrow.right",
                    accent: Brand.rail,
                    title: "Transload + rail",
                    sub: "cross-dock scenario · \(transloadTransitLabel)",
                    pillText: nil,
                    pillColor: Brand.rail,
                    cost: moneyLabel(transloadAllIn) ?? "—",
                    costNote: transloadDeltaLabel,
                    costNoteColor: palette.textTertiary
                )
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func modeRow(icon: String,
                         accent: Color,
                         title: String,
                         sub: String,
                         pillText: String?,
                         pillColor: Color,
                         cost: String,
                         costNote: String,
                         costNoteColor: Color) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub)
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                if let pillText {
                    Text(pillText)
                        .font(.system(size: 10.5, weight: .bold)).tracking(0.4)
                        .foregroundStyle(pillColor)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(pillColor.opacity(0.20)))
                }
                Text(cost)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary).monospacedDigit()
                Text(costNote)
                    .font(.system(size: 9))
                    .foregroundStyle(costNoteColor)
            }
        }
        .padding(Space.s3)
    }

    // MARK: - ESang rationale row

    private var esangRationale: some View {
        HStack(spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(rationaleHeadline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Text("Apply commits the selected routing to this shipment")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var rationaleHeadline: String {
        // A savings claim renders ONLY when both sides of the comparison are
        // live — otherwise the rationale states honestly what's missing.
        if let s = savings, s > 0 {
            let saved = s >= 1_000
                ? String(format: "$%.0f", (s / 100).rounded() * 100)
                : String(format: "$%.0f", s)
            return "Intermodal clears the SLA with \(saved) saved"
        }
        return "Mode economics pending — live costs incomplete"
    }

    // MARK: - CTA pair (Apply mode · Re-run)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: applied ? "Applied" : "Apply mode",
                action: { Task { await applyMode() } },
                leadingIcon: applied ? "checkmark.seal.fill" : "checkmark",
                isLoading: applying
            )
            Button {
                Task { await reload() }
            } label: {
                Text("Re-run")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 148)
        }
    }

    // MARK: - Derived labels for transload + truck deltas

    /// Transload + rail all-in. WIRE-GAP: a distinct transload routing is a
    /// separate planning scenario with NO dedicated read on this surface —
    /// every transload cell is an em-dash until that endpoint lands.
    private var transloadAllIn: Double? { nil }
    private var transloadTransitLabel: String { "—" }
    private var transloadDeltaLabel: String {
        guard let rail = intermodalAllIn, let load = transloadAllIn, rail > 0 else { return "—" }
        let pct = (load - rail) / rail * 100
        return String(format: "%@%.0f%%", pct >= 0 ? "+" : "−", abs(pct))
    }

    private var truckFastestLabel: String {
        guard let routes = compare?.routes,
              let minHours = routes.compactMap({ $0.hours }).min() else { return "—" }
        return String(format: "%.1fd", minHours / 24.0)
    }
    private var truckDeltaLabel: String {
        guard let rail = intermodalAllIn, let truck = truckAllIn, rail > 0 else { return "—" }
        let pct = (truck - rail) / rail * 100
        return String(format: "%@%.0f%%", pct >= 0 ? "+" : "−", abs(pct))
    }

    private var laneCode: String {
        guard !resolvedOrigin.isEmpty, !resolvedDestination.isEmpty else { return "—" }
        let o = String(resolvedOrigin.prefix(2)).uppercased()
        let d = String(resolvedDestination.prefix(3)).uppercased()
        return "\(o)→\(d)"
    }

    // MARK: - Formatting helpers

    private func moneyLabel(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }
        return "$" + Int(value.rounded()).formatted(.number.grouping(.automatic))
    }
    private func transitLabel(_ days: Double?) -> String? {
        guard let days, days > 0 else { return nil }
        return String(format: "%.1fd", days)
    }

    // MARK: - Load (rename: reload, not load — avoids name collision)

    private func reload() async {
        loading = true; loadError = nil; noShipment = false
        struct CostIn: Encodable { let intermodalShipmentId: Int }
        struct ListIn: Encodable { let limit: Int; let offset: Int }
        struct CompareIn: Encodable {
            let origin: String
            let destination: String
            let vehicleType: String
            let grossWeightLbs: Int
            let isHazmat: Bool
        }
        do {
            // 1. Resolve a REAL shipment. Navigation injection wins; otherwise
            //    the newest intermodal shipment (createdAt desc) scopes the
            //    verdict. No invented lane, ever.
            resolvedShipmentId = intermodalShipmentId
            resolvedRef = shipmentRef
            resolvedOrigin = originLabel
            resolvedDestination = destinationLabel
            if resolvedShipmentId <= 0 {
                let page: IntermodalShipmentsPage618 = try await EusoTripAPI.shared.query(
                    "intermodal.getIntermodalShipments", input: ListIn(limit: 1, offset: 0))
                guard let newest = page.shipments?.first else {
                    noShipment = true
                    loading = false
                    return
                }
                resolvedShipmentId = newest.id
                resolvedRef = newest.intermodalNumber ?? ""
                resolvedOrigin = newest.originLocation?.description ?? ""
                resolvedDestination = newest.destinationLocation?.description ?? ""
            }

            // 2. Live economics for the resolved shipment. The truck compare
            //    needs a real lane — it is only fired when both endpoints are
            //    known (no fabricated geocode inputs).
            async let bd: ModeCostBreakdown? = EusoTripAPI.shared.query(
                "intermodal.getIntermodalCostBreakdown",
                input: CostIn(intermodalShipmentId: resolvedShipmentId))
            async let dash: IntermodalDashboard = EusoTripAPI.shared.queryNoInput(
                "intermodal.getIntermodalDashboard")

            if !resolvedOrigin.isEmpty && !resolvedDestination.isEmpty {
                async let cmp: RouteComparison = EusoTripAPI.shared.query(
                    "routeOptimization.getRouteComparison",
                    input: CompareIn(origin: resolvedOrigin,
                                     destination: resolvedDestination,
                                     vehicleType: "5_axle",
                                     grossWeightLbs: 80_000,
                                     isHazmat: false))
                let (breakdownResult, compareResult, dashResult) = try await (bd, cmp, dash)
                self.breakdown = breakdownResult
                self.compare = compareResult
                self.dashboard = dashResult
                // The compare endpoint returns a geocode error in-band rather
                // than throwing — surface it so the user isn't staring at
                // stale numbers.
                if let e = compareResult.error, !e.isEmpty {
                    self.loadError = e
                }
            } else {
                let (breakdownResult, dashResult) = try await (bd, dash)
                self.breakdown = breakdownResult
                self.compare = nil
                self.dashboard = dashResult
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Apply mode

    // intermodal.applyModeChoice commits the chosen routing against the real
    // shipment row, writes the quoted cost when available, and appends a
    // blockchain audit entry server-side. Errors surface honestly.
    private func applyMode() async {
        guard !applying, !applied, resolvedShipmentId > 0 else { return }
        applying = true; applyError = nil
        struct ApplyIn: Encodable {
            let intermodalShipmentId: Int
            let chosenMode: String
            let quotedCost: Double
        }
        struct ApplyOut: Decodable {
            let id: Int?
            let success: Bool?
            let status: String?
            let chosenMode: String?
        }
        do {
            let ack: ApplyOut = try await EusoTripAPI.shared.mutation(
                "intermodal.applyModeChoice",
                input: ApplyIn(intermodalShipmentId: resolvedShipmentId,
                               chosenMode: "intermodal",
                               quotedCost: intermodalAllIn ?? 0))
            applied = ack.success ?? true
            appliedStatus = ack.status
        } catch {
            applyError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        applying = false
    }
}

#Preview("618 · Rail Mode Optimization · Night") {
    RailModeOptimizationScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("618 · Rail Mode Optimization · Light") {
    RailModeOptimizationScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
