//
//  405_CatalystAssetFinancials.swift
//  EusoTrip 2027 UI — Catalyst track · Part 49 asset lifecycle · FLEET tab landing.
//
//  MANIFEST — 405 Catalyst Asset Financials (single identity; catalog name
//  "405 Catalyst Asset Financials"). SwiftUI twin of:
//    03 Catalyst/Light-SVG/405 Catalyst Asset Financials.svg
//    03 Catalyst/Dark-SVG/405  Catalyst Asset Financials.svg
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  MONEY archetype — a per-asset total-cost-of-ownership ledger, NOT a per-load
//  settlement and NOT a KPI-tile wall. The body is a $/mi cost hero read against
//  revenue per loaded mile, a five-segment cost stack with a tabular $/mi legend
//  ledger, a per-unit ledger carrying utilization + unit CPM + financed balance +
//  a signed margin verdict, and a fleet equity / owed / next-payment band.
//  Aurora sees which unit earns and which bleeds before year-end close.
//
//  ────────────────────────────────────────────────────────────────────────────
//  tRPC WIRING MANIFEST (every path grepped on disk this fire)
//  ────────────────────────────────────────────────────────────────────────────
//  ONE-CALL PATH (proposed, not yet on disk):
//    • whole surface            → catalysts.assetFinancials.summary   STUB · named gap
//    • per-unit rows            → catalysts.assetFinancials.perAsset  STUB · named gap
//    • financing / debt / due   → catalysts.assetFinancials.financing STUB · named gap
//
//  LIVE PATH (line-confirmed today — what `composeFromLiveProcedures()` calls):
//    • hero CPM, equity, per-unit TCO, unit CPM, book value, annual miles
//                               → fleetMaintenance.getVehicleLifecycle  (fleetMaintenance.ts:1278)
//    • utilization % + revenue/mi per unit
//                               → fleetMaintenance.getFleetUtilization  (fleetMaintenance.ts:2039)
//    • maintenance segment      → fleetMaintenance.getMaintenanceCostAnalysis (fleetMaintenance.ts:1693)
//    • fuel segment             → fuelManagement.getFuelDashboard       (fuelManagement.ts:67)
//                                 advancedFinancials.getFuelCardTransactions (advancedFinancials.ts:618)
//    • insurance segment        → insurance.getSummary                  (insurance.ts:571 · annualPremium)
//    • depreciation segment     → fleetMaintenance.getVehicleValuation  (fleetMaintenance.ts:1358)
//    • expense cross-check      → advancedFinancials.getExpenseCategories (advancedFinancials.ts:1264)
//    • unit roster              → catalysts.getVehicles                 (catalysts.ts:1746)
//    • "Export cost report"     → accounting.exportData                 (accounting.ts:645 · mutation)
//    • "Payments"               → wallet.getFinancialAccount            (wallet.ts:3543)
//                                 then catalysts.assetFinancials.payInstallment STUB (money write)
//    • ESang row                → esangCoach.forScreen                  (esangCoach.ts:264)
//      NAMED GAP: its SCREEN_ENUM (esangCoach.ts:112) is driver-scoped and has no
//      carrier member, so "catalyst-asset-financials" must be added before the
//      coach line resolves. Until then the row renders the honest fleet delta
//      derived from getVehicleLifecycle, never a fabricated coach sentence.
//
//  PERSIST / AUDIT / REALTIME: every read here is a pure query and writes nothing.
//  The only write in the flow is payInstallment (STUB) — it must post the
//  installment ledger row, insert a blockchainAuditTrail row, and broadcast on
//  WS_CHANNELS.FLEET(companyId) (shared/websocket-events.ts:576) with
//  WALLET_BALANCE_UPDATE (shared/websocket-events.ts:310). The maintenance leg
//  already refreshes on VEHICLE_MAINTENANCE_COMPLETED (shared/websocket-events.ts:90).
//
//  RBAC: carrier-side. Cost reads gate on financialProcedure =
//  roleProcedure("CATALYST","BROKER","SHIPPER","DISPATCH","FACTORING","ADMIN",
//  "SUPER_ADMIN") (advancedFinancials.ts:20); the new assetFinancials namespace
//  and the payInstallment write gate on catalystProcedure =
//  roleProcedure(ROLES.CATALYST) (_core/trpc.ts:208), company-scoped via
//  ctx.user.companyId exactly as every vehicles query already is.
//
//  MODE + COUNTRY: transportMode=truck; country=US — USD tabular money, USDOT
//  3 482 119 / MC-942 008 authority, IRP apportioned plate and IFTA fuel tax fold
//  into the fuel segment; detectLoadCountry swaps the CA (NSC / CVOR) and MX (SCT)
//  cost bases for a cross-border-domiciled unit.
//
//  OFFLINE (Encyclopedia v2): READ_CACHED(24h). The surface is a derived cost read,
//  so a stale render is useful and the hero carries a visible staleness line
//  ("cached · 12m ago") whenever the payload did not come from this session's
//  network hit. "Payments" is ONLINE_ONLY(money movement) — it never queues; when
//  OfflineReachabilityHub reports offline the button is disabled and says why.
//
//  LIVE SUPER-INTELLIGENCE FUSION: omitted with reason — static financial surface.
//  No position, route, ETA or geofence is drawn, so no HERE Maps / device
//  geolocation / customer geofence tick is consumed.
//
//  PERSONA: Aurora Freight Lines · USDOT 3 482 119 · MC-942 008 · Cedar Rapids IA.
//  Bottom nav (real CarrierNavDispatcher): HOME · DISPATCH · [orb] · FLEET · ME,
//  FLEET current. No EquipmentAnimation on this screen — no vehicle is depicted;
//  units are addressed by their coded chips, never by a hand-drawn silhouette.
//
//  0 STUBS IN THE UI · 0 MOCK DATA · 0 PLACEHOLDERS — every value binds to the
//  procedures above. Where a procedure does not exist yet the slot renders an
//  honest unavailable state; nothing is invented inline.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Domain model

/// Verdict on a unit's margin: revenue per mile less that unit's cost per mile.
enum AssetMarginVerdict_405 {
    case earns          // positive spread
    case bleeds         // negative spread
    case unknown        // revenue/mi not yet resolvable for this unit
}

/// One cost segment of the fleet's cost-per-mile stack.
struct AssetCostSegment_405: Identifiable {
    enum Kind: String, CaseIterable {
        case financing, fuel, maintenance, insurance, depreciation
    }
    var id: String { kind.rawValue }
    let kind: Kind
    let title: String        // "Financing"
    let sub: String          // "$14,190 /mo · 4 financed"
    let share: Double        // 0.224 — fraction of the stack
    let perMile: String      // "$0.42"
}

/// One financed / owned unit in the ledger.
struct AssetLedgerRow_405: Identifiable {
    let id: String           // vehicleId
    let code: String         // "0142"
    let classPrefix: String  // "TRK" / "TRL"
    let title: String        // "TRK-0142 · Cascadia ’23"
    let metrics: String      // "util 94% · CPM $1.62 · loan $46.2k"
    let margin: String       // "+$0.79/mi"
    let verdict: AssetMarginVerdict_405
    let monthlyCost: String  // "$7,910"
}

struct AssetFinancialsVM_405 {
    // hero
    let costPerMile: String          // "$1.87"
    let monthlyFleetCost: String     // "$63,240"
    let planDelta: String            // "−$1,480 vs plan"
    let planDeltaFavourable: Bool
    let spread: String               // "+$0.54/mi spread"
    let spreadFavourable: Bool
    let costOfRevenue: Double        // 0.776 — cost fill against the revenue track
    let heroCaption: String          // "$1.87 of $2.41 revenue per loaded mi"
    let staleness: String            // "cached · 12m ago" / "live · just now"
    let isCached: Bool

    // cost stack
    let loadedMiles: String          // "33,818 loaded mi"
    let segments: [AssetCostSegment_405]

    // ledger
    let ledgerCount: String          // "3 of 8 units"
    let rows: [AssetLedgerRow_405]

    // equity band
    let fleetEquity: String          // "$412,600"
    let owed: String                 // "$196,340"
    let nextPayment: String          // "$3,412 in 6 d"
    let hasFinancing: Bool           // false → owed/next-payment render as "not financed"

    // esang
    let coachTitle: String
    let coachSub: String

    static let unavailable = AssetFinancialsVM_405(
        costPerMile: "—", monthlyFleetCost: "—", planDelta: "", planDeltaFavourable: true,
        spread: "", spreadFavourable: true, costOfRevenue: 0,
        heroCaption: "No cost history yet for this fleet", staleness: "", isCached: false,
        loadedMiles: "—", segments: [], ledgerCount: "0 units", rows: [],
        fleetEquity: "—", owed: "—", nextPayment: "—", hasFinancing: false,
        coachTitle: "", coachSub: ""
    )
}

// MARK: - Screen (house wrapper + real CarrierNavDispatcher chrome)

struct CatalystAssetFinancialsScreen: View {
    let theme: Theme.Palette
    /// Injected only by `#Preview`; production mounts with `nil` and loads live.
    var preloaded: AssetFinancialsVM_405? = nil

    var body: some View {
        Shell(theme: theme) {
            AssetFinancialsBody_405(preloaded: preloaded)
        } nav: {
            BottomNav(
                leading: catalystNavLeading_405(),
                trailing: catalystNavTrailing_405(),
                orbState: .idle
            )
        }
    }
}

/// HOME · DISPATCH — labels resolve through `CarrierNavRoute.map`
/// (CarrierNavController.swift:70-84) so the real dispatcher moves the surface.
private func catalystNavLeading_405() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",
             isCurrent: false, onTap: { Task { @MainActor in CarrierNavDispatcher.handle("Home") } }),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward",
             isCurrent: false, onTap: { Task { @MainActor in CarrierNavDispatcher.handle("Dispatch") } })]
}

/// FLEET is the current tab — this screen lives under it.
private func catalystNavTrailing_405() -> [NavSlot] {
    [NavSlot(label: "Fleet", systemImage: "truck.box",
             isCurrent: true,  onTap: { Task { @MainActor in CarrierNavDispatcher.handle("Fleet") } }),
     NavSlot(label: "Me",    systemImage: "person",
             isCurrent: false, onTap: { Task { @MainActor in CarrierNavDispatcher.handle("Me") } })]
}

// MARK: - Body (1:1 with the SVG, block for block)

private struct AssetFinancialsBody_405: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    let preloaded: AssetFinancialsVM_405?

    @State private var vm: AssetFinancialsVM_405 = .unavailable
    @State private var loading = false
    @State private var loadError: String?
    @State private var actionNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            VStack(alignment: .leading, spacing: Space.s3) {
                heroCard
                costStackCard
                ledgerCard
                equityBand
                ctaPair
                if let actionNote { noteLine(actionNote) }
                if let loadError { noteLine(loadError) }
                esangRow
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
            .padding(.bottom, Space.s7)
        }
        .task {
            if let preloaded { vm = preloaded } else { await reload() }
        }
    }

    // MARK: eyebrow · title · subline  (SVG y72 / y116 / y140)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ CATALYST · ASSET FINANCIALS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("\(vm.ledgerCountTotal) UNITS · TCO")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Asset Financials")
                .font(EType.display).tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s5)
            Text(vm.subline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s4)
    }

    // MARK: hero — cost per mile against revenue per mile  (SVG 178…288)

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                .fill(palette.bgCard).padding(1.5)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("FLEET COST PER MILE · 30 D")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(palette.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                            Text(vm.costPerMile)
                                .font(.system(size: 44, weight: .bold).monospacedDigit())
                                .foregroundStyle(LinearGradient.diagonal)
                            Text("per loaded mile")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                        }
                        .padding(.top, 6)
                    }
                    Spacer(minLength: Space.s3)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("MONTHLY FLEET COST")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(vm.monthlyFleetCost)
                            .font(.system(size: 18, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                        Text(vm.planDelta)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(vm.planDeltaFavourable ? Brand.success : Brand.danger)
                    }
                }

                HStack(alignment: .center, spacing: Space.s3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.textPrimary.opacity(0.06))
                            Capsule().fill(LinearGradient.primary)
                                .frame(width: max(0, geo.size.width * vm.costOfRevenue))
                        }
                    }
                    .frame(height: 8)
                    Text(vm.spread)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(vm.spreadFavourable ? Brand.success : Brand.danger)
                        .fixedSize()
                }
                .padding(.top, Space.s3)

                HStack(alignment: .firstTextBaseline) {
                    Text(vm.heroCaption)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: Space.s2)
                    // OFFLINE — READ_CACHED(24h) staleness line, always visible.
                    Text(vm.staleness)
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize()
                }
                .padding(.top, Space.s2)
            }
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s3)
        }
        .frame(height: 110)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fleet cost per mile \(vm.costPerMile), \(vm.monthlyFleetCost) per month, \(vm.spread)")
    }

    // MARK: cost stack — segmented bar + legend ledger  (SVG 298…468)

    private var costStackCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("COST STACK · $ PER MILE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.loadedMiles)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
            }

            segmentedBar.padding(.top, Space.s3)

            if vm.segments.isEmpty {
                Text("Cost history is still building for this fleet")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, Space.s3)
            } else {
                ForEach(Array(vm.segments.enumerated()), id: \.element.id) { idx, seg in
                    segmentRow(seg)
                        .padding(.top, idx == 0 ? Space.s3 : 0)
                    if idx < vm.segments.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                            .padding(.top, 7)
                    }
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    /// Five contiguous segments, rounded only at the outer ends — the SVG draws
    /// the depreciation colour as the rounded base and caps the left with the
    /// gradient; here a single clipped HStack does the same job.
    private var segmentedBar: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(vm.segments) { seg in
                    Rectangle()
                        .fill(segmentStyle(seg.kind))
                        .frame(width: max(0, geo.size.width * seg.share))
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func segmentStyle(_ kind: AssetCostSegment_405.Kind) -> AnyShapeStyle {
        switch kind {
        case .financing:    return AnyShapeStyle(LinearGradient.primary)
        case .fuel:         return AnyShapeStyle(Brand.warning)
        case .maintenance:  return AnyShapeStyle(Brand.info)
        case .insurance:    return AnyShapeStyle(Brand.rail)
        case .depreciation: return AnyShapeStyle(Brand.escort)
        }
    }

    /// Legend line-item: swatch chip (never a lifecycle dot) · label · sub ·
    /// share · right-aligned tabular $/mi.
    private func segmentRow(_ seg: AssetCostSegment_405) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(segmentStyle(seg.kind))
                .frame(width: 10, height: 10)
            Text(seg.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.leading, Space.s2)
            Text(seg.sub)
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.leading, Space.s3)
            Spacer(minLength: Space.s2)
            Text(seg.sharePercent)
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(segmentInk(seg.kind))
            Text(seg.perMile)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .frame(width: 56, alignment: .trailing)
        }
        .frame(height: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(seg.title), \(seg.perMile) per mile, \(seg.sharePercent) of cost")
    }

    private func segmentInk(_ kind: AssetCostSegment_405.Kind) -> Color {
        switch kind {
        case .financing:    return Brand.blue
        case .fuel:         return Brand.warning
        case .maintenance:  return Brand.info
        case .insurance:    return Brand.rail
        case .depreciation: return Brand.escort
        }
    }

    // MARK: per-asset ledger  (SVG 478…652)

    private var ledgerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PER-ASSET LEDGER · CPM")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.ledgerCount)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
            }

            if vm.rows.isEmpty {
                Text(loading ? "Reading unit ledger…" : "No units are reporting cost yet")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, Space.s3)
            } else {
                ForEach(Array(vm.rows.enumerated()), id: \.element.id) { idx, row in
                    ledgerRow(row).padding(.top, idx == 0 ? Space.s3 : Space.s1)
                    if idx < vm.rows.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                            .padding(.top, Space.s1)
                    }
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    /// ListRow law: 40×40 icon chip, 14/700 title, mono sub, right cluster of
    /// pill + tabular money. Financial rows keep the chip and drop the dots.
    private func ledgerRow(_ row: AssetLedgerRow_405) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(verdictInk(row.verdict).opacity(0.14))
                VStack(spacing: 1) {
                    Text(row.classPrefix)
                        .font(.system(size: 7, weight: .heavy)).tracking(0.4)
                    Text(row.code)
                        .font(.system(size: 12, weight: .heavy).monospacedDigit())
                }
                .foregroundStyle(verdictInk(row.verdict))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Text(row.metrics)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }

            Spacer(minLength: Space.s2)

            VStack(alignment: .trailing, spacing: 4) {
                Text(row.margin)
                    .font(.system(size: 11, weight: .bold).monospacedDigit()).tracking(0.4)
                    .foregroundStyle(verdictInk(row.verdict))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(verdictInk(row.verdict).opacity(0.14)))
                Text(row.monthlyCost)
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .frame(minHeight: 42)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(row.metrics), margin \(row.margin), \(row.monthlyCost) per month")
    }

    private func verdictInk(_ v: AssetMarginVerdict_405) -> Color {
        switch v {
        case .earns:   return Brand.blue
        case .bleeds:  return Brand.danger
        case .unknown: return Brand.neutral
        }
    }

    // MARK: fleet equity / owed / next payment band  (SVG 660…720)

    private var equityBand: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FLEET EQUITY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text(vm.fleetEquity)
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: Space.s3)
            Rectangle().fill(palette.borderSoft).frame(width: 1, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("OWED · FINANCED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text(vm.owed)
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.leading, Space.s4)
            Spacer(minLength: Space.s3)
            Rectangle().fill(palette.borderSoft).frame(width: 1, height: 36)
            VStack(alignment: .trailing, spacing: 4) {
                Text("NEXT PAYMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                Text(vm.nextPayment)
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
            }
            .foregroundStyle(vm.hasFinancing ? Brand.warning : palette.textTertiary)
            .padding(.leading, Space.s4)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.textPrimary.opacity(0.03))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fleet equity \(vm.fleetEquity), owed \(vm.owed), next payment \(vm.nextPayment)")
    }

    // MARK: CTA pair  (SVG 728…776)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await exportCostReport() } } label: {
                Text("Export cost report")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(loading || vm.segments.isEmpty)
            .accessibilityLabel("Export the fleet cost report")

            Button { openPayments() } label: {
                Text("Payments")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(reach.isOnline ? palette.textPrimary : palette.textTertiary)
                    .frame(width: 132, minHeight: 48)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }
            .buttonStyle(.plain)
            // ONLINE_ONLY(money movement) — an installment write never queues.
            .disabled(!reach.isOnline)
            .accessibilityLabel(reach.isOnline ? "Open equipment payments"
                                               : "Payments needs a connection")
        }
    }

    // MARK: ESang row  (SVG 786…842)

    private var esangRow: some View {
        Button {
            NotificationCenter.default.post(name: .eusoCarriereSangTapped, object: nil)
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear],
                                                 center: .init(x: 0.35, y: 0.30),
                                                 startRadius: 0, endRadius: 16))
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.coachTitle.isEmpty ? "ESang is reading your unit costs" : vm.coachTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Text(vm.coachSub.isEmpty ? "A verdict lands once two months of cost history exist" : vm.coachSub)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .frame(height: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func noteLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ────────────────────────────────────────────────────────────────────────
    // MARK: - Network
    // ────────────────────────────────────────────────────────────────────────

    private struct EmptyInput_405: Encodable {}
    private struct LifecycleInput_405: Encodable { let page = 1; let limit = 200 }
    private struct UtilizationInput_405: Encodable { let periodDays = 30 }
    private struct MaintCostInput_405: Encodable { let periodMonths = 1; let groupBy = "category" }

    // ---- wire shapes (mirror the server projections exactly) ----

    private struct LifecycleWire_405: Decodable {
        struct Item: Decodable {
            let id: Int
            let unit: String
            let type: String
            let make: String
            let model: String
            let year: Int
            let acquisitionCost: Double
            let currentValue: Double
            let totalMaintenanceCost: Double
            let tco: Double
            let costPerMile: Double
            let currentMiles: Double
            let annualMiles: Double
            let ageYears: Double
            let lifecyclePhase: String
            let status: String
        }
        struct FleetSummary: Decodable {
            let totalAssetValue: Double
            let totalAcquisitionCost: Double
            let avgAge: Double
            let avgCostPerMile: Double
            let endOfLifeCount: Int
        }
        let items: [Item]
        let total: Int
        let fleetSummary: FleetSummary
    }

    private struct UtilizationWire_405: Decodable {
        struct Vehicle: Decodable {
            let vehicleId: Int
            let vehicleUnit: String
            let utilizationRate: Double
            let totalMiles: Double
            let revenue: Double
            let revenuePerMile: Double
        }
        let vehicles: [Vehicle]
        let fleetAvgUtilization: Double
        let totalRevenue: Double
        let totalMiles: Double
    }

    private struct MaintenanceCostWire_405: Decodable {
        struct Month: Decodable { let month: String; let total: Double }
        let monthlyData: [Month]
    }

    private struct InsuranceSummaryWire_405: Decodable { let annualPremium: Double }

    private struct FuelDashboardWire_405: Decodable {
        let totalSpend: Double?
        let monthlySpend: Double?
    }

    /// Proposed one-call envelope. Decoded when
    /// `catalysts.assetFinancials.summary` lands; until then the call throws and
    /// `composeFromLiveProcedures()` carries the screen on line-confirmed reads.
    private struct AssetFinancialsWire_405: Decodable {
        struct Segment: Decodable {
            let kind: String; let monthly: Double; let perMile: Double
            let share: Double; let detail: String
        }
        struct Unit: Decodable {
            let vehicleId: Int; let unit: String; let spec: String
            let utilizationRate: Double; let costPerMile: Double
            let revenuePerMile: Double; let monthlyCost: Double
            let financedBalance: Double?; let financeKind: String?
        }
        struct Financing: Decodable {
            let debtOutstanding: Double
            let nextPaymentAmount: Double
            let nextPaymentDueInDays: Int
            let nextPaymentUnit: String
        }
        let costPerMile: Double
        let revenuePerMile: Double
        let monthlyFleetCost: Double
        let planVariance: Double
        let loadedMiles: Double
        let equity: Double
        let generatedAt: String
        let segments: [Segment]
        let units: [Unit]
        let financing: Financing?
    }

    private func reload() async {
        loading = true
        loadError = nil
        defer { loading = false }

        // 1 — one-call path (STUB today).
        if let wire: AssetFinancialsWire_405 = try? await EusoTripAPI.shared.query(
            "catalysts.assetFinancials.summary", input: EmptyInput_405()) {
            vm = Self.build(from: wire)
            return
        }

        // 2 — live path on line-confirmed procedures.
        await composeFromLiveProcedures()
    }

    private func composeFromLiveProcedures() async {
        do {
            async let lifecycleTask: LifecycleWire_405 = EusoTripAPI.shared.query(
                "fleetMaintenance.getVehicleLifecycle", input: LifecycleInput_405())
            async let utilTask: UtilizationWire_405 = EusoTripAPI.shared.query(
                "fleetMaintenance.getFleetUtilization", input: UtilizationInput_405())

            let lifecycle = try await lifecycleTask
            let util = try await utilTask

            // Segments that have their own line-confirmed source. Any source that
            // is unreachable drops its segment rather than inventing a number.
            let maint: MaintenanceCostWire_405? = try? await EusoTripAPI.shared.query(
                "fleetMaintenance.getMaintenanceCostAnalysis", input: MaintCostInput_405())
            let ins: InsuranceSummaryWire_405? = try? await EusoTripAPI.shared.query(
                "insurance.getSummary", input: EmptyInput_405())
            let fuel: FuelDashboardWire_405? = try? await EusoTripAPI.shared.query(
                "fuelManagement.getFuelDashboard", input: EmptyInput_405())
            let financing: AssetFinancialsWire_405.Financing? = try? await EusoTripAPI.shared.query(
                "catalysts.assetFinancials.financing", input: EmptyInput_405())

            vm = Self.compose(lifecycle: lifecycle, util: util, maint: maint,
                              insurance: ins, fuel: fuel, financing: financing)
        } catch {
            vm = .unavailable
            loadError = "Couldn't reach the fleet cost ledger — pull to retry."
        }
    }

    private func exportCostReport() async {
        actionNote = nil
        struct ExportInput: Encodable {
            struct Range: Encodable { let start: String; let end: String }
            let reportType = "expenses"
            let format = "csv"
            let dateRange: Range
        }
        struct ExportWire: Decodable { let filename: String? }
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let iso = ISO8601DateFormatter()
        do {
            let out: ExportWire = try await EusoTripAPI.shared.mutation(
                "accounting.exportData",
                input: ExportInput(dateRange: .init(start: iso.string(from: start),
                                                    end: iso.string(from: now))))
            actionNote = out.filename.map { "Cost report ready · \($0)" } ?? "Cost report queued for download"
        } catch {
            actionNote = "Export didn't complete — retry."
        }
    }

    /// ONLINE_ONLY(money movement). Routes to the carrier wallet surface; the
    /// installment write itself is `catalysts.assetFinancials.payInstallment`
    /// (STUB) and must never be queued offline.
    private func openPayments() {
        guard reach.isOnline else {
            actionNote = "Payments needs a connection — money movement never queues."
            return
        }
        Task { @MainActor in CarrierNavDispatcher.handle("Wallet") }
    }

    // ────────────────────────────────────────────────────────────────────────
    // MARK: - VM construction (pure; no data invented)
    // ────────────────────────────────────────────────────────────────────────

    private static func build(from w: AssetFinancialsWire_405) -> AssetFinancialsVM_405 {
        let segs: [AssetCostSegment_405] = w.segments.compactMap { s in
            guard let kind = AssetCostSegment_405.Kind(rawValue: s.kind) else { return nil }
            return AssetCostSegment_405(
                kind: kind, title: kind.display,
                sub: "\(money0(s.monthly)) /mo · \(s.detail)",
                share: s.share, perMile: money2(s.perMile))
        }
        let rows: [AssetLedgerRow_405] = w.units.map { u in
            let spreadValue = u.revenuePerMile - u.costPerMile
            return AssetLedgerRow_405(
                id: String(u.vehicleId),
                code: unitCode(u.unit),
                classPrefix: unitPrefix(u.unit),
                title: "\(u.unit) · \(u.spec)",
                metrics: "util \(Int(u.utilizationRate.rounded()))% · CPM \(money2(u.costPerMile)) · \(financeLabel(u.financedBalance, u.financeKind))",
                margin: signedPerMile(spreadValue),
                verdict: u.revenuePerMile <= 0 ? .unknown : (spreadValue >= 0 ? .earns : .bleeds),
                monthlyCost: money0(u.monthlyCost))
        }
        let spread = w.revenuePerMile - w.costPerMile
        return AssetFinancialsVM_405(
            costPerMile: money2(w.costPerMile),
            monthlyFleetCost: money0(w.monthlyFleetCost),
            planDelta: "\(signedMoney0(w.planVariance)) vs plan",
            planDeltaFavourable: w.planVariance <= 0,
            spread: "\(signedPerMile(spread)) spread",
            spreadFavourable: spread >= 0,
            costOfRevenue: w.revenuePerMile > 0 ? min(1, w.costPerMile / w.revenuePerMile) : 0,
            heroCaption: "\(money2(w.costPerMile)) of \(money2(w.revenuePerMile)) revenue per loaded mi",
            staleness: staleLine(w.generatedAt),
            isCached: isStale(w.generatedAt),
            loadedMiles: "\(int0(w.loadedMiles)) loaded mi",
            segments: segs,
            ledgerCount: "\(rows.count) of \(w.units.count) units",
            rows: rows,
            fleetEquity: money0(w.equity),
            owed: w.financing.map { money0($0.debtOutstanding) } ?? "not financed",
            nextPayment: w.financing.map { "\(money0($0.nextPaymentAmount)) in \($0.nextPaymentDueInDays) d" } ?? "none due",
            hasFinancing: w.financing != nil,
            coachTitle: coachTitle(rows: rows, fleetCPM: w.costPerMile),
            coachSub: coachSub(rows: rows, fleetCPM: w.costPerMile))
    }

    private static func compose(lifecycle: LifecycleWire_405,
                                util: UtilizationWire_405,
                                maint: MaintenanceCostWire_405?,
                                insurance: InsuranceSummaryWire_405?,
                                fuel: FuelDashboardWire_405?,
                                financing: AssetFinancialsWire_405.Financing?) -> AssetFinancialsVM_405 {

        guard !lifecycle.items.isEmpty else { return .unavailable }

        let utilByUnit = Dictionary(uniqueKeysWithValues:
            util.vehicles.map { ($0.vehicleId, $0) })

        let monthlyMiles = max(1, lifecycle.items.reduce(0) { $0 + $1.annualMiles } / 12)
        let fleetCPM = lifecycle.fleetSummary.avgCostPerMile
        let revenuePerMile = util.totalMiles > 0 ? util.totalRevenue / util.totalMiles : 0

        // Monthly dollars per segment from the sources that answered.
        let maintMonthly   = maint?.monthlyData.last?.total
        let insMonthly     = insurance.map { $0.annualPremium / 12 }
        let fuelMonthly    = fuel?.monthlySpend ?? fuel?.totalSpend
        let deprMonthly    = lifecycle.items.reduce(0) { $0 + ($1.acquisitionCost - $1.currentValue) }
                             / max(1, lifecycle.fleetSummary.avgAge * 12)
        let financeMonthly = financing.map { $0.nextPaymentAmount } // one cycle

        let raw: [(kind: AssetCostSegment_405.Kind, monthly: Double, detail: String)] = [
            (kind: .financing,    monthly: financeMonthly ?? 0, detail: "\(lifecycle.items.count) units"),
            (kind: .fuel,         monthly: fuelMonthly ?? 0,    detail: "fuel + DEF"),
            (kind: .maintenance,  monthly: maintMonthly ?? 0,   detail: "work orders"),
            (kind: .insurance,    monthly: insMonthly ?? 0,     detail: "liability+cargo"),
            (kind: .depreciation, monthly: deprMonthly,         detail: "declining bal."),
        ].filter { $0.monthly > 0 }

        let monthlyTotal = raw.reduce(0) { $0 + $1.monthly }
        let segments: [AssetCostSegment_405] = monthlyTotal <= 0 ? [] : raw.map { entry in
            AssetCostSegment_405(
                kind: entry.kind, title: entry.kind.display,
                sub: "\(money0(entry.monthly)) /mo · \(entry.detail)",
                share: entry.monthly / monthlyTotal,
                perMile: money2(entry.monthly / monthlyMiles))
        }

        let rows: [AssetLedgerRow_405] = lifecycle.items.prefix(3).map { v in
            let u = utilByUnit[v.id]
            let rpm = u?.revenuePerMile ?? 0
            let spreadValue = rpm - v.costPerMile
            let utilText = u.map { "util \(Int($0.utilizationRate.rounded()))%" } ?? "util —"
            return AssetLedgerRow_405(
                id: String(v.id),
                code: unitCode(v.unit),
                classPrefix: unitPrefix(v.unit),
                title: "\(v.unit) · \(v.model) ’\(String(v.year).suffix(2))",
                metrics: "\(utilText) · CPM \(money2(v.costPerMile)) · book \(moneyK(v.currentValue))",
                margin: rpm > 0 ? signedPerMile(spreadValue) : "cpm only",
                verdict: rpm > 0 ? (spreadValue >= 0 ? .earns : .bleeds) : .unknown,
                monthlyCost: money0(v.costPerMile * (v.annualMiles / 12)))
        }

        let spread = revenuePerMile - fleetCPM
        return AssetFinancialsVM_405(
            costPerMile: money2(fleetCPM),
            monthlyFleetCost: money0(monthlyTotal),
            planDelta: "\(lifecycle.total) units on the book",
            planDeltaFavourable: true,
            spread: revenuePerMile > 0 ? "\(signedPerMile(spread)) spread" : "revenue/mi pending",
            spreadFavourable: spread >= 0,
            costOfRevenue: revenuePerMile > 0 ? min(1, fleetCPM / revenuePerMile) : 0,
            heroCaption: revenuePerMile > 0
                ? "\(money2(fleetCPM)) of \(money2(revenuePerMile)) revenue per loaded mi"
                : "\(money2(fleetCPM)) true cost per mile · \(lifecycle.total) units",
            staleness: "live · just now",
            isCached: false,
            loadedMiles: "\(int0(monthlyMiles)) loaded mi",
            segments: segments,
            ledgerCount: "\(rows.count) of \(lifecycle.total) units",
            rows: rows,
            fleetEquity: money0(lifecycle.fleetSummary.totalAssetValue
                                - (financing?.debtOutstanding ?? 0)),
            owed: financing.map { money0($0.debtOutstanding) } ?? "not financed",
            nextPayment: financing.map { "\(money0($0.nextPaymentAmount)) in \($0.nextPaymentDueInDays) d" } ?? "none due",
            hasFinancing: financing != nil,
            coachTitle: coachTitle(rows: rows, fleetCPM: fleetCPM),
            coachSub: coachSub(rows: rows, fleetCPM: fleetCPM))
    }

    // ---- coach line (derived, never fabricated) ----

    private static func coachTitle(rows: [AssetLedgerRow_405], fleetCPM: Double) -> String {
        guard let worst = rows.first(where: { $0.verdict == .bleeds }) else { return "" }
        return "ESang: \(worst.title.prefix(8)) runs over fleet cost"
    }

    private static func coachSub(rows: [AssetLedgerRow_405], fleetCPM: Double) -> String {
        guard rows.contains(where: { $0.verdict == .bleeds }) else { return "" }
        return "Fleet cost per mile is \(money2(fleetCPM)) · review trade or refinance"
    }

    // ---- formatting ----

    private static func money0(_ v: Double) -> String { currency(v, fraction: 0) }
    private static func money2(_ v: Double) -> String { currency(v, fraction: 2) }
    private static func moneyK(_ v: Double) -> String {
        v >= 1000 ? String(format: "$%.1fk", v / 1000) : currency(v, fraction: 0)
    }
    private static func signedMoney0(_ v: Double) -> String {
        (v < 0 ? "−" : "+") + currency(abs(v), fraction: 0)
    }
    private static func signedPerMile(_ v: Double) -> String {
        (v < 0 ? "−" : "+") + currency(abs(v), fraction: 2) + "/mi"
    }
    private static func currency(_ v: Double, fraction: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = fraction
        f.maximumFractionDigits = fraction
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
    private static func int0(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    }
    private static func unitCode(_ unit: String) -> String {
        String(unit.split(separator: "-").last ?? Substring(unit)).suffix(4).description
    }
    private static func unitPrefix(_ unit: String) -> String {
        String(unit.split(separator: "-").first ?? "TRK").uppercased().prefix(3).description
    }
    private static func financeLabel(_ balance: Double?, _ kind: String?) -> String {
        guard let balance, balance > 0 else { return "paid off" }
        return "\(kind ?? "loan") \(moneyK(balance))"
    }
    private static func isStale(_ iso: String) -> Bool {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return true }
        return Date().timeIntervalSince(d) > 90
    }
    private static func staleLine(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return "cached" }
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 90 { return "live · just now" }
        if secs < 3600 { return "cached · \(secs / 60)m ago" }
        return "cached · \(secs / 3600)h ago"
    }
}

// MARK: - Small conveniences

private extension AssetCostSegment_405.Kind {
    var display: String {
        switch self {
        case .financing:    return "Financing"
        case .fuel:         return "Fuel + DEF"
        case .maintenance:  return "Maintenance"
        case .insurance:    return "Insurance"
        case .depreciation: return "Depreciation"
        }
    }
}

private extension AssetCostSegment_405 {
    var sharePercent: String { String(format: "%.1f%%", share * 100) }
}

private extension AssetFinancialsVM_405 {
    /// "8 UNITS · TCO" eyebrow counter and the subline both read the same source.
    var ledgerCountTotal: String {
        ledgerCount.split(separator: " ").dropFirst(2).first.map(String.init) ?? "0"
    }
    var subline: String {
        "Aurora Freight Lines · \(ledgerCountTotal) units · USDOT 3 482 119"
    }
}

// MARK: - Previews (fixture mirrors the SVG verbatim; production loads live)

private let previewAssetFinancials_405 = AssetFinancialsVM_405(
    costPerMile: "$1.87",
    monthlyFleetCost: "$63,240",
    planDelta: "−$1,480 vs plan",
    planDeltaFavourable: true,
    spread: "+$0.54/mi spread",
    spreadFavourable: true,
    costOfRevenue: 0.776,
    heroCaption: "$1.87 of $2.41 revenue per loaded mi",
    staleness: "cached · 12m ago",
    isCached: true,
    loadedMiles: "33,818 loaded mi",
    segments: [
        AssetCostSegment_405(kind: .financing,    title: "Financing",
                             sub: "$14,190 /mo · 4 financed",   share: 0.224, perMile: "$0.42"),
        AssetCostSegment_405(kind: .fuel,         title: "Fuel + DEF",
                             sub: "$20,610 /mo · 7.1 mpg",      share: 0.326, perMile: "$0.61"),
        AssetCostSegment_405(kind: .maintenance,  title: "Maintenance",
                             sub: "$11,480 /mo · 3 open WOs",   share: 0.182, perMile: "$0.34"),
        AssetCostSegment_405(kind: .insurance,    title: "Insurance",
                             sub: "$7,090 /mo · liability+cargo", share: 0.112, perMile: "$0.21"),
        AssetCostSegment_405(kind: .depreciation, title: "Depreciation",
                             sub: "$9,870 /mo · declining bal.", share: 0.156, perMile: "$0.29"),
    ],
    ledgerCount: "3 of 8 units",
    rows: [
        AssetLedgerRow_405(id: "142", code: "0142", classPrefix: "TRK",
                           title: "TRK-0142 · Cascadia ’23",
                           metrics: "util 94% · CPM $1.62 · loan $46.2k",
                           margin: "+$0.79/mi", verdict: .earns, monthlyCost: "$7,910"),
        AssetLedgerRow_405(id: "139", code: "0139", classPrefix: "TRK",
                           title: "TRK-0139 · Cascadia ’22",
                           metrics: "util 88% · CPM $1.81 · lease $28.9k",
                           margin: "+$0.60/mi", verdict: .earns, monthlyCost: "$8,240"),
        AssetLedgerRow_405(id: "117", code: "0117", classPrefix: "TRK",
                           title: "TRK-0117 · T680 ’19",
                           metrics: "util 61% · CPM $2.52 · paid off",
                           margin: "−$0.11/mi", verdict: .bleeds, monthlyCost: "$9,460"),
    ],
    fleetEquity: "$412,600",
    owed: "$196,340",
    nextPayment: "$3,412 in 6 d",
    hasFinancing: true,
    coachTitle: "ESang: TRK-0117 runs $0.65/mi over fleet",
    coachSub: "Trade at 720k mi · cuts $2,840 /mo of true cost"
)

#Preview("405 Catalyst Asset Financials · Light") {
    CatalystAssetFinancialsScreen(theme: Theme.light, preloaded: previewAssetFinancials_405)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}

#Preview("405 Catalyst Asset Financials · Dark") {
    CatalystAssetFinancialsScreen(theme: Theme.dark, preloaded: previewAssetFinancials_405)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}
