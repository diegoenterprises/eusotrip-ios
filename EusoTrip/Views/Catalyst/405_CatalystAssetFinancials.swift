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
//  Canonical contract audit (backend origin/main): company identity and vehicle
//  roster are read directly; fuel, maintenance, and insurance contribute only
//  values their ledgers actually measure. The backend has no asset financing,
//  acquisition-value, depreciation, per-asset revenue, or installment contract,
//  so those slots remain explicitly untracked and no payment/export action is
//  presented as an asset-financial write.
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
    let companyLine: String
    // hero
    let costPerMile: String          // "$1.87"
    let monthlyFleetCost: String     // "$63,240"
    let planDelta: String            // "−$1,480 vs plan"
    let planDeltaFavourable: Bool
    let spread: String               // "+$0.54/mi spread"
    let spreadFavourable: Bool?
    let costOfRevenue: Double        // 0.776 — cost fill against the revenue track
    let heroCaption: String          // "$1.87 of $2.41 revenue per loaded mi"
    let staleness: String            // latest refresh and partial-source status
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

    // source coverage
    let coverageTitle: String
    let coverageSub: String

    static let unavailable = AssetFinancialsVM_405(
        companyLine: "Company identity unavailable",
        costPerMile: "—", monthlyFleetCost: "—", planDelta: "", planDeltaFavourable: true,
        spread: "", spreadFavourable: nil, costOfRevenue: 0,
        heroCaption: "No cost history yet for this fleet", staleness: "", isCached: false,
        loadedMiles: "—", segments: [], ledgerCount: "0 units", rows: [],
        fleetEquity: "—", owed: "—", nextPayment: "—", hasFinancing: false,
        coverageTitle: "Measured cost coverage",
        coverageSub: "No cost ledgers returned data"
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
    CarrierNavRoute.leading(current: .drivers)
}

/// FLEET is the current tab — this screen lives under it.
private func catalystNavTrailing_405() -> [NavSlot] {
    CarrierNavRoute.trailing(current: .drivers)
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
                sourceCoverageRow
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
            .padding(.bottom, Space.s7)
        }
        .task {
            if let preloaded { vm = preloaded } else { await reload() }
        }
        .eusoRefreshable { await reload() }
    }

    // MARK: eyebrow · title · subline  (SVG y72 / y116 / y140)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EusoTripEyebrow(verbatim: "CATALYST · ASSET FINANCIALS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("\(vm.ledgerCountTotal) UNITS · COSTS")
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
                        Text("RECORDED OPERATING COST / MILE · LATEST")
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
                                .foregroundStyle(palette.textSecondary)
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
                        .foregroundStyle(vm.spreadFavourable.map {
                            $0 ? Brand.success : Brand.danger
                        } ?? palette.textSecondary)
                        .fixedSize()
                }
                .padding(.top, Space.s3)

                HStack(alignment: .firstTextBaseline) {
                    Text(vm.heroCaption)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: Space.s2)
                    // Age/coverage of the latest in-memory refresh.
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
                Text("MAINTENANCE BY ASSET · LATEST")
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
                Text("ACQUISITION VALUE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text(vm.fleetEquity)
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: Space.s3)
            Rectangle().fill(palette.borderSoft).frame(width: 1, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("FINANCING BALANCE")
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
            Button { Task { await reload() } } label: {
                Text("Refresh costs")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(loading)
            .accessibilityLabel("Refresh recorded fleet costs")

            Button { openPayments() } label: {
                Text("Open wallet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(reach.isOnline ? palette.textPrimary : palette.textTertiary)
                    .frame(width: 132).frame(minHeight: 48)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }
            .buttonStyle(.plain)
            // ONLINE_ONLY(money movement) — an installment write never queues.
            .disabled(!reach.isOnline)
            .accessibilityLabel(reach.isOnline ? "Open wallet"
                                               : "Wallet needs a connection")
        }
    }

    // MARK: Measured source coverage

    private var sourceCoverageRow: some View {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear],
                                                 center: .init(x: 0.35, y: 0.30),
                                                 startRadius: 0, endRadius: 16))
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.coverageTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Text(vm.coverageSub)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: Space.s2)
            }
            .padding(Space.s3)
            .frame(height: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
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
    private struct VehicleInput_405: Encodable { let limit = 200 }
    private struct MaintCostInput_405: Encodable { let periodMonths = 1; let groupBy = "vehicle" }
    private struct FuelInput_405: Encodable { let period = "month" }

    // ---- wire shapes (mirror the server projections exactly) ----

    private struct CompanyWire_405: Decodable {
        let name: String
        let dotNumber: String?
    }

    private struct VehicleWire_405: Decodable {
        let id: String
        let make: String
        let model: String
        let year: Int
        let licensePlate: String
        let vehicleType: String?
        let status: String?
        let isActive: Bool?
    }

    private struct MaintenanceCostWire_405: Decodable {
        struct Month: Decodable { let month: String; let total: Double }
        struct Vehicle: Decodable {
            let vehicleUnit: String
            let vehicleId: Int?
            let amount: Double
        }
        let totalCost: Double
        let avgMonthlyCost: Double
        let monthlyTrend: [Month]
        let byVehicle: [Vehicle]
    }

    private struct InsuranceSummaryWire_405: Decodable {
        let totalPolicies: Int
        let annualPremium: Double
    }

    private struct FuelDashboardWire_405: Decodable {
        struct Month: Decodable { let month: String; let amount: Double }
        let totalSpend: Double
        let totalMiles: Double
        let transactionCount: Int
        let monthlySpend: [Month]
    }

    private struct AccountingSummaryWire_405: Decodable {
        let currency: String
    }

    private func reload() async {
        loading = true
        loadError = nil
        actionNote = nil
        defer { loading = false }
        let api = EusoTripAPI.shared
        var company: CompanyWire_405?
        var vehicles: [VehicleWire_405] = []
        var maintenance: MaintenanceCostWire_405?
        var insurance: InsuranceSummaryWire_405?
        var fuel: FuelDashboardWire_405?
        var accounting: AccountingSummaryWire_405?
        var failures: [String] = []

        do { company = try await api.queryNoInput("companies.getMyCompany") }
        catch { failures.append("Company identity: \(error.eusoUserCopy)") }
        do {
            vehicles = try await api.query("catalysts.getVehicles", input: VehicleInput_405())
        } catch { failures.append("Fleet roster: \(error.eusoUserCopy)") }
        do {
            maintenance = try await api.query(
                "fleetMaintenance.getMaintenanceCostAnalysis", input: MaintCostInput_405())
        } catch { failures.append("Maintenance costs: \(error.eusoUserCopy)") }
        do {
            fuel = try await api.query("fuelManagement.getFuelDashboard", input: FuelInput_405())
        } catch { failures.append("Fuel costs: \(error.eusoUserCopy)") }
        do { insurance = try await api.queryNoInput("insurance.getSummary") }
        catch { failures.append("Insurance costs: \(error.eusoUserCopy)") }
        do { accounting = try await api.queryNoInput("accounting.getSummary") }
        catch { failures.append("Currency context: \(error.eusoUserCopy)") }

        vm = Self.compose(company: company, vehicles: vehicles, maintenance: maintenance,
                          insurance: insurance, fuel: fuel,
                          currencyCode: accounting?.currency ?? "USD",
                          sourceFailureCount: failures.count)
        loadError = failures.isEmpty ? nil : failures.joined(separator: " ")
    }

    private func openPayments() {
        guard reach.isOnline else {
            actionNote = "Wallet needs a live connection."
            return
        }
        Task { @MainActor in CarrierNavDispatcher.handle("Wallet") }
    }

    // ────────────────────────────────────────────────────────────────────────
    // MARK: - VM construction (pure; no data invented)
    // ────────────────────────────────────────────────────────────────────────

    private static func compose(company: CompanyWire_405?,
                                vehicles: [VehicleWire_405],
                                maintenance: MaintenanceCostWire_405?,
                                insurance: InsuranceSummaryWire_405?,
                                fuel: FuelDashboardWire_405?,
                                currencyCode: String,
                                sourceFailureCount: Int) -> AssetFinancialsVM_405 {

        let maintenanceMonthly = maintenance?.avgMonthlyCost ?? 0
        let insuranceMonthly = (insurance?.annualPremium ?? 0) / 12
        let fuelMonthly = fuel?.totalSpend ?? 0
        let measuredMiles = fuel?.totalMiles ?? 0

        let raw: [(kind: AssetCostSegment_405.Kind, monthly: Double, detail: String)] = [
            (kind: .fuel, monthly: fuelMonthly,
             detail: "\(fuel?.transactionCount ?? 0) transactions"),
            (kind: .maintenance, monthly: maintenanceMonthly, detail: "maintenance ledger"),
            (kind: .insurance, monthly: insuranceMonthly, detail: "annual premium / 12"),
        ].filter { $0.monthly > 0 }

        let monthlyTotal = raw.reduce(0) { $0 + $1.monthly }
        let segments: [AssetCostSegment_405] = monthlyTotal <= 0 ? [] : raw.map { entry in
            AssetCostSegment_405(
                kind: entry.kind, title: entry.kind.display,
                sub: "\(money0(entry.monthly, currencyCode)) /mo · \(entry.detail)",
                share: entry.monthly / monthlyTotal,
                perMile: measuredMiles > 0
                    ? money2(entry.monthly / measuredMiles, currencyCode) : "—")
        }

        let vehiclesById = Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, $0) })
        let rows: [AssetLedgerRow_405] = (maintenance?.byVehicle ?? [])
            .filter { $0.amount > 0 }
            .prefix(50)
            .map { item in
            let id = item.vehicleId.map(String.init) ?? item.vehicleUnit
            let vehicle = vehiclesById[id]
            let unit = vehicle?.licensePlate.isEmpty == false
                ? vehicle!.licensePlate : item.vehicleUnit
            var specParts: [String] = []
            if let make = vehicle?.make, !make.isEmpty { specParts.append(make) }
            if let model = vehicle?.model, !model.isEmpty { specParts.append(model) }
            if let year = vehicle?.year, year > 0 { specParts.append(String(year)) }
            let spec = specParts.joined(separator: " ")
            let status = vehicle?.status?.replacingOccurrences(of: "_", with: " ") ?? "status unavailable"
            return AssetLedgerRow_405(
                id: id,
                code: unitCode(unit),
                classPrefix: unitPrefix(unit),
                title: spec.isEmpty ? unit : "\(unit) · \(spec)",
                metrics: "\(status) · recorded maintenance",
                margin: "recorded",
                verdict: .unknown,
                monthlyCost: money0(item.amount, currencyCode))
        }

        var companyParts: [String] = []
        if let name = company?.name, !name.isEmpty { companyParts.append(name) }
        if let dot = company?.dotNumber, !dot.isEmpty { companyParts.append("USDOT \(dot)") }
        let companyLine = (companyParts + ["\(vehicles.count) units"]).joined(separator: " · ")
        let measuredCPM = measuredMiles > 0 ? monthlyTotal / measuredMiles : 0
        let coverage = [
            (fuel?.transactionCount ?? 0) > 0 ? "fuel" : nil,
            ((maintenance?.monthlyTrend.isEmpty == false)
                || (maintenance?.byVehicle.isEmpty == false)) ? "maintenance" : nil,
            (insurance?.totalPolicies ?? 0) > 0 ? "insurance" : nil,
        ].compactMap { $0 }
        let hasMeasuredSources = !coverage.isEmpty

        return AssetFinancialsVM_405(
            companyLine: companyLine,
            costPerMile: measuredMiles > 0 ? money2(measuredCPM, currencyCode) : "—",
            monthlyFleetCost: hasMeasuredSources ? money0(monthlyTotal, currencyCode) : "—",
            planDelta: "\(coverage.count) measured cost sources",
            planDeltaFavourable: true,
            spread: "Revenue not measured",
            spreadFavourable: nil,
            costOfRevenue: 0,
            heroCaption: !hasMeasuredSources ? "No measured cost records were returned"
                : measuredMiles > 0
                ? "\(money0(monthlyTotal, currencyCode)) across \(int0(measuredMiles)) recorded load miles"
                : "\(money0(monthlyTotal, currencyCode)) recorded; mileage unavailable",
            staleness: sourceFailureCount == 0 ? "updated · just now" : "updated · partial sources",
            isCached: false,
            loadedMiles: measuredMiles > 0 ? "\(int0(measuredMiles)) loaded mi" : "mileage unavailable",
            segments: segments,
            ledgerCount: "\(rows.count) of \(vehicles.count) units",
            rows: rows,
            fleetEquity: "Not tracked",
            owed: "Not tracked",
            nextPayment: "Not tracked",
            hasFinancing: false,
            coverageTitle: "Measured cost coverage",
            coverageSub: coverage.isEmpty
                ? "No cost ledgers returned records"
                : coverage.joined(separator: ", ").capitalized)
    }

    // ---- formatting ----

    private static func money0(_ v: Double, _ code: String = "USD") -> String {
        currency(v, fraction: 0, code: code)
    }
    private static func money2(_ v: Double, _ code: String = "USD") -> String {
        currency(v, fraction: 2, code: code)
    }
    private static func currency(_ v: Double, fraction: Int, code: String = "USD") -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
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
    /// The unit counter and subline both read the same live roster.
    var ledgerCountTotal: String {
        ledgerCount.split(separator: " ").dropFirst(2).first.map(String.init) ?? "0"
    }
    var subline: String {
        companyLine
    }
}

// MARK: - Previews (fixture mirrors the SVG verbatim; production loads live)

private let previewAssetFinancials_405 = AssetFinancialsVM_405(
    companyLine: "Aurora Freight Lines · 8 units · USDOT 3 482 119",
    costPerMile: "$1.87",
    monthlyFleetCost: "$63,240",
    planDelta: "−$1,480 vs plan",
    planDeltaFavourable: true,
    spread: "+$0.54/mi spread",
    spreadFavourable: true,
    costOfRevenue: 0.776,
    heroCaption: "$1.87 of $2.41 revenue per loaded mi",
    staleness: "updated · 12m ago",
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
    coverageTitle: "Measured cost coverage",
    coverageSub: "Fuel, maintenance and insurance records"
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
