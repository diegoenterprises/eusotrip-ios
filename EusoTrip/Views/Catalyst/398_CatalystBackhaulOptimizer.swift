//
//  398_CatalystBackhaulOptimizer.swift
//  EusoTrip — Catalyst track · carrier back-office growth band.
//
//  Verbatim iOS port of 03 Catalyst/Code/398_CatalystBackhaulOptimizer.swift
//  into the iOS house chrome (Shell + BottomNav). NOT the stamped home/detail
//  skeleton and NOT a generic header + card-list: the body is a DEADHEAD-vs-
//  LOADED hero comparison bar plus ranked return-load match cards, each
//  carrying its reposition (deadhead) miles, gross RPM, net-after-deadhead,
//  pickup window and a match score. Turns a free 612-mi empty run home out of
//  Dallas into a paid reposition in one tap.
//
//  CANONICAL PERSONA §12 — Michael Eusorone (Eusotrans LLC owner-op) ·
//  USDOT 3 194 882 · Belle Plaine IA. Web peer: /catalyst/backhaul.
//
//  tRPC wiring manifest (line-confirmed on disk this fire):
//    • ranked matches              → capacityPlanning.getBackhaulOptimizer  (capacityPlanning.ts:690)
//    • power-only / drop-trailer    → capacityPlanning.getPowerOnlyMatching  (capacityPlanning.ts:755)
//    • candidate loads near dropoff → loadBoard.search                       (loadBoard.ts)
//    • deadhead mileage             → routeOptimization.*                    (routeOptimization.ts)
//    • "Tender" CTA                 → loadBidding.createQuote                (loadBidding.ts)
//      (on win writes the loads row + blockchainAudit row, broadcasts
//       WS_EVENTS.LOAD_TENDERED on WS_CHANNELS.catalyst(carrierId))
//  RBAC: isolatedProcedure carrier-scope (capacityPlanning.ts:10).
//
//  LIVE WIRING (zero-fallback purge · 2026-06-09 · audit B13): reload()
//  calls the REAL `capacityPlanning.getBackhaulOptimizer` (thin in-file
//  decode mirroring the server projection exactly: opportunities[] of
//  deliveryLoad/backhaulLoad/fromState/toState/estimatedSavings +
//  emptyMileReduction + potentialSavings). The server matches at STATE
//  level and carries no equipment/RPM/deadhead-mile fields — the board
//  therefore renders state-lane matches with estimated savings, a neutral
//  equipment glyph, and an honest EusoEmptyState when no match exists.
//  The old city-pair/net-RPM seed board was fabricated and is GONE.
//
//  MAP-COORD INVESTIGATION (2026-06-05): the backhaul/deadhead lanes are
//  CITY-NAME-ONLY — no endpoint lat/lng is reachable for a HereLiveMapView
//  route overlay, so this screen is an HONEST-SKIP for the map embed:
//    • The lane model (`BackhaulMatch_398.lane`) is a display string
//      ("Dallas TX → Kansas City MO"); it carries no coordinate field.
//    • The sole backing proc `capacityPlanning.getBackhaulOptimizer`
//      (capacityPlanning.ts:690) extracts ONLY `$.state`/`$.city` from the
//      loads JSON and matches by STATE-NAME equality
//      (`del.deliveryState === pend.pickupState`); its `opportunities[]`
//      shape returns `fromState`/`toState`/`loadNumber`/`estimatedSavings`
//      and emits NO lat/lng (the `$.lat`/`$.lng` keys present on the
//      `loads.pickupLocation`/`deliveryLocation` JSON are never selected).
//    • No `capacityPlanning` iOS client exists, and `loads.getById`
//      (LoadDetail) narrows pickup/delivery to {city,state} only — so there
//      is no in-file path to real endpoint coordinates for these lanes.
//  Drawing lanes would require (a) editing the proc to return per-load
//  pickup+delivery coords and rework state-match → geo-match, and (b) a new
//  capacityPlanning client service — both outside this file's edit scope.
//  No fabricated/hardcoded coordinates are introduced here.
//
//  Bottom nav (Catalyst variant): HOME · DISPATCH · [orb] · WALLET · ME
//  (DISPATCH current).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen (house wrapper)

struct CatalystBackhaulOptimizerScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            BackhaulBody_398()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_398(),
                trailing: catalystNavTrailing_398(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_398() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_398() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",     isCurrent: false)]
}

// MARK: - View model (built from the LIVE getBackhaulOptimizer envelope only)

private enum BackhaulEquipment_398 { case dryVan, reefer, flatbed, unknown }

private struct BackhaulMatch_398: Identifiable {
    let id: String
    let lane: String          // "TX → MO" (server matches at state level)
    let spec: String          // "return for LD-… · candidate LD-…"
    let equipment: BackhaulEquipment_398
    let savings: String       // "$1,228" — server estimatedSavings
    let backhaulLoadNumber: String
}

private struct BackhaulVM_398 {
    let emptyAt: String
    let deadheadLabel: String
    let deadheadValue: String
    let loadedLabel: String
    let loadedValue: String
    let payoff: String
    let withinRadius: String
    let matches: [BackhaulMatch_398]
    let footerLead: String
    let footerSub: String
    let searchNote: String

    /// Honest empty envelope — every figure em-dash until a real hydrate.
    static let empty = BackhaulVM_398(
        emptyAt: "BACKHAUL SCAN · STATE-LEVEL MATCHES",
        deadheadLabel: "Empty miles avoidable", deadheadValue: "—",
        loadedLabel: "Matched return candidates", loadedValue: "—",
        payoff: "—", withinRadius: "—",
        matches: [],
        footerLead: "Matches pair your recent deliveries with posted loads picking up in the same state",
        footerSub: "",
        searchNote: ""
    )
}

/// Mirrors `capacityPlanning.getBackhaulOptimizer` (capacityPlanning.ts:690).
private struct BackhaulWire_398: Decodable {
    struct Opportunity: Decodable {
        let deliveryLoad: String
        let backhaulLoad: String
        let fromState: String
        let toState: String
        let estimatedSavings: Double
    }
    let opportunities: [Opportunity]
    let emptyMileReduction: Double
    let potentialSavings: Double
}

// MARK: - Notifications (carry the tap intent into the host action layer)

extension Notification.Name {
    static let eusoCatalystBackhaulTender_398     = Notification.Name("eusoCatalystBackhaulTender")
    static let eusoCatalystBackhaulTenderBest_398 = Notification.Name("eusoCatalystBackhaulTenderBest")
    static let eusoCatalystBackhaulRadius_398     = Notification.Name("eusoCatalystBackhaulRadius")
}

// MARK: - Body

private struct BackhaulBody_398: View {
    @Environment(\.palette) private var palette

    @State private var vm: BackhaulVM_398 = .empty
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            iridescentHairline
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    }
                    heroCard
                    matchesSection
                    ctaRow
                    if !vm.searchNote.isEmpty {
                        Text(vm.searchNote)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s3)
                .padding(.bottom, Space.s7)
            }
        }
        .task { await loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await reload() }
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("CATALYST · BACKHAUL · EMPTY-MILE KILLER")
                        .font(EType.micro)
                        .tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer(minLength: 0)
                Text(loading ? "SCANNING…" : "LIVE SCAN")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 28)
                Text("Backhaul")
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                VStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(palette.textPrimary).frame(width: 4, height: 4)
                    }
                }
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, 56)
        .padding(.bottom, Space.s3)
    }

    private var iridescentHairline: some View {
        IridescentHairline()
    }

    // MARK: Hero — deadhead vs best backhaul comparison

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)
            VStack(alignment: .leading, spacing: 10) {
                Text(vm.emptyAt)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                compareRow(
                    label: vm.deadheadLabel, value: vm.deadheadValue,
                    barFrac: vm.matches.isEmpty ? 0 : 1.0, barColor: Brand.danger.opacity(0.6),
                    track: Brand.danger.opacity(0.18), valueColor: Brand.danger
                )
                compareRow(
                    label: vm.loadedLabel, value: vm.loadedValue,
                    barFrac: vm.matches.isEmpty ? 0 : 0.93, barColor: nil,
                    track: Brand.success.opacity(0.18), valueColor: Brand.success
                )
                HStack {
                    Text("Estimated savings if matched")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Text(vm.payoff)
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 128)
    }

    private func compareRow(label: String, value: String, barFrac: CGFloat,
                            barColor: Color?, track: Color, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(valueColor)
            }
            GeometryReader { geo in
                let w = geo.size.width * 0.66   // bar occupies the left ~2/3
                ZStack(alignment: .leading) {
                    Capsule().fill(track).frame(width: w, height: 8)
                    barFill(barColor: barColor).frame(width: w * barFrac, height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    @ViewBuilder
    private func barFill(barColor: Color?) -> some View {
        if let bc = barColor {
            Capsule().fill(bc)
        } else {
            Capsule().fill(LinearGradient.primary)
        }
    }

    // MARK: Ranked return matches

    private var matchesSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("RETURN LOADS · RANKED BY NET RPM")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(vm.withinRadius)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                if vm.matches.isEmpty {
                    EusoEmptyState(
                        systemImage: "arrow.triangle.2.circlepath",
                        title: loading ? "Scanning for return loads…" : "No backhaul matches right now",
                        subtitle: loading ? "" : "Posted loads picking up where your fleet is delivering appear here ranked by estimated savings."
                    )
                    .padding(.vertical, Space.s3)
                } else {
                    if let best = vm.matches.first { featuredMatch(best) }
                    ForEach(Array(vm.matches.dropFirst().enumerated()), id: \.element.id) { idx, m in
                        compactMatch(m)
                        if idx < vm.matches.count - 2 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 48)
                        }
                    }
                }
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.footerLead)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    if !vm.footerSub.isEmpty {
                        Text(vm.footerSub)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func featuredMatch(_ m: BackhaulMatch_398) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.md - 1.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: Space.s3) {
                    equipmentChip(m.equipment)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.lane)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text(m.spec)
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(m.savings)
                            .font(.system(size: 20, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("est savings")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                HStack(spacing: 6) {
                    metricChip("STATE MATCH", tint: Brand.success.opacity(0.12), label: Brand.success)
                    metricChip(m.backhaulLoadNumber, tint: palette.bgCardSoft, label: palette.textPrimary)
                }
                HStack {
                    Button {
                        // Hands the REAL candidate load number to the host
                        // action layer (loadBidding.createQuote not yet bridged).
                        NotificationCenter.default.post(
                            name: .eusoCatalystBackhaulTender_398, object: nil,
                            userInfo: ["source": "398_CatalystBackhaulOptimizer",
                                       "loadNumber": m.backhaulLoadNumber]
                        )
                    } label: {
                        Text("TENDER NOW →")
                            .font(EType.micro).tracking(0.4).fontWeight(.heavy)
                            .foregroundStyle(LinearGradient.primary)
                            .padding(.horizontal, 14).padding(.vertical, 4)
                            .background(Capsule().strokeBorder(LinearGradient.primary, lineWidth: 1.1))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
            }
            .padding(Space.s3)
        }
        .padding(Space.s2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Best return, \(m.lane), estimated savings \(m.savings)")
    }

    private func metricChip(_ text: String, tint: Color?, label: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.3).monospacedDigit()
            .foregroundStyle(label)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(tint ?? Color.clear))
            .background(tint == nil ? AnyView(Capsule().fill(LinearGradient.primary)) : AnyView(EmptyView()))
    }

    private func compactMatch(_ m: BackhaulMatch_398) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            equipmentChip(m.equipment)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.lane)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(m.spec)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(m.savings)
                    .font(EType.bodyStrong).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("est savings")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
    }

    @ViewBuilder
    private func equipmentChip(_ eq: BackhaulEquipment_398) -> some View {
        let icon = equipmentIcon(eq)
        let tint = equipmentTint(eq)
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm).fill(tint.opacity(0.16))
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 36, height: 36)
    }

    private func equipmentIcon(_ eq: BackhaulEquipment_398) -> String {
        switch eq {
        case .dryVan:  return "box.truck"
        case .reefer:  return "thermometer.snowflake"
        case .flatbed: return "rectangle.compress.vertical"
        case .unknown: return "arrow.triangle.2.circlepath"   // equipment not in the live envelope — neutral glyph, never invented
        }
    }

    private func equipmentTint(_ eq: BackhaulEquipment_398) -> Color {
        switch eq {
        case .dryVan:  return Brand.rail            // SVG #607D8B slate
        case .reefer:  return Brand.info            // SVG #2196F3
        case .flatbed: return palette.textPrimary
        case .unknown: return Brand.blue
        }
    }

    // MARK: CTA pair

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                // WIRE: loadBidding.createQuote on the best return (loadBidding.ts)
                NotificationCenter.default.post(
                    name: .eusoCatalystBackhaulTenderBest_398, object: nil,
                    userInfo: ["source": "398_CatalystBackhaulOptimizer"]
                )
            } label: {
                Text("Tender best return")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tender the best return load")

            Button {
                NotificationCenter.default.post(
                    name: .eusoCatalystBackhaulRadius_398, object: nil,
                    userInfo: ["source": "398_CatalystBackhaulOptimizer"]
                )
            } label: {
                Text("Adjust radius")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Adjust search radius")
        }
    }

    // MARK: - Network (LIVE — capacityPlanning.getBackhaulOptimizer)

    private func loadAll() async {
        await reload()
    }

    private struct EmptyInput_398: Encodable {}

    private func reload() async {
        loading = true
        loadError = nil
        defer { loading = false }

        do {
            let wire: BackhaulWire_398 = try await EusoTripAPI.shared.query(
                "capacityPlanning.getBackhaulOptimizer", input: EmptyInput_398())

            let matches: [BackhaulMatch_398] = wire.opportunities.enumerated().map { idx, o in
                BackhaulMatch_398(
                    id: "\(o.deliveryLoad)-\(o.backhaulLoad)-\(idx)",
                    lane: "\(o.fromState) → \(o.toState)",
                    spec: "return for \(o.deliveryLoad) · candidate \(o.backhaulLoad)",
                    equipment: .unknown,
                    savings: money_398(o.estimatedSavings),
                    backhaulLoadNumber: o.backhaulLoad
                )
            }

            vm = BackhaulVM_398(
                emptyAt: "BACKHAUL SCAN · STATE-LEVEL MATCHES",
                deadheadLabel: "Empty miles avoidable",
                deadheadValue: wire.emptyMileReduction > 0
                    ? "\(Int(wire.emptyMileReduction)) mi est" : "—",
                loadedLabel: "Matched return candidates",
                loadedValue: matches.isEmpty ? "—" : "\(matches.count)",
                payoff: wire.potentialSavings > 0 ? "+\(money_398(wire.potentialSavings))" : "—",
                withinRadius: matches.isEmpty ? "—" : "\(matches.count) state match\(matches.count == 1 ? "" : "es")",
                matches: matches,
                footerLead: "Matches pair your recent deliveries with posted loads picking up in the same state",
                footerSub: matches.isEmpty ? "" : "Savings estimated at $1.80 per avoided empty mile",
                searchNote: matches.isEmpty ? "" : "State-level matching · 14-day delivery window · live load board"
            )
        } catch {
            vm = .empty
            loadError = "Couldn't reach the backhaul optimizer - retry."
        }
    }

    private func money_398(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}

// MARK: - Previews

#Preview("398 · Catalyst · Backhaul Optimizer · Night") {
    CatalystBackhaulOptimizerScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("398 · Catalyst · Backhaul Optimizer · Afternoon") {
    CatalystBackhaulOptimizerScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
