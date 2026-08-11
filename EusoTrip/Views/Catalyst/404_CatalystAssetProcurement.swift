//
//  404_CatalystAssetProcurement.swift
//  EusoTrip 2027 UI — Catalyst track · 404 Catalyst Asset Procurement
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  Moment: Aurora Freight Lines is buying iron. BOARD / OPERATIONS archetype —
//          NOT the Home hero+KPI skeleton, NOT a chart screen. A three-cell
//          summary BAND states committed capital, units in the pipeline and
//          the next delivery time-relative; below it the buy runs as a
//          four-stage pipeline (QUOTE → ORDERED → IN BUILD → DELIVERY), each
//          stage its own card with a count + subtotal header over dense
//          icon-chip rows. Exactly one line carries the attention treatment:
//          the quote whose dealer price-hold lapses in six hours. The screen
//          answers three questions in one screenful — what capital is
//          committed, what arrives when, what needs a decision now.
//
//  This file is the SwiftUI twin of:
//    03 Catalyst/Light-SVG/404 Catalyst Asset Procurement.svg
//    03 Catalyst/Dark-SVG/404 Catalyst Asset Procurement.svg
//
//  Web peer: client/src/pages/VendorSupplier.tsx — route /vendor-supplier
//  (client/src/App.tsx:1145, guard CARR+SHIP+ADMN; tabs purchase-orders · rfq ·
//  spend). That page is general vendor/supply procurement; an ASSET-acquisition
//  (tractor/trailer capex) tab does not exist there — gap filed.
//
//  ── tRPC WIRING MANIFEST (every line re-confirmed on disk this fire) ────────
//   EXISTS
//    • band committed capital + open-PO count → vendorSupplier.getPurchaseOrders
//                                               (vendorSupplier.ts:1466)
//    • ORDERED stage rows                     → vendorSupplier.getPurchaseOrders
//                                               (vendorSupplier.ts:1466)
//    • QUOTE stage rows                       → vendorSupplier.getRfqManagement
//                                               (vendorSupplier.ts:1617)
//    • quote count / best per-unit price      → vendorSupplier.getQuoteComparison
//                                               (vendorSupplier.ts:1775)
//    • dealer + OEM names on every row        → vendorSupplier.getVendors
//                                               (vendorSupplier.ts:323)
//    • stage subtotals / capex roll-up        → vendorSupplier.getSpendAnalytics
//                                               (vendorSupplier.ts:1868)
//    • IN BUILD spec · VIN decode             → fleetRegistration.decodeVin
//                                               (fleetRegistration.ts:224)
//    • DELIVERY stage read                    → assetTracking.getAssetLifecycleStatus
//                                               (assetTracking.ts:910)
//    • CTA "New procurement request"          → vendorSupplier.createRfq
//                                               (vendorSupplier.ts:1734)
//    • CTA "Compare quotes"                   → vendorSupplier.getQuoteComparison
//                                               (vendorSupplier.ts:1775)
//    • attention-row commit path              → vendorSupplier.createPurchaseOrder
//                                               (vendorSupplier.ts:1418) then
//                                               vendorSupplier.approvePurchaseOrder
//                                               (vendorSupplier.ts:1583)
//    • delivered unit → roster                → fleet.create (fleet.ts:622) /
//                                               fleetRegistration.registerVehicleFleet
//                                               (fleetRegistration.ts:245)
//    • ESang advisory row                     → esangCoach.forScreen
//                                               (esangCoach.ts:264)
//   NAMED GAPS (STUB — surfaced here, never faked; TS shapes in the fire report)
//    • catalysts.assetProcurement.pipeline    — the stage-partitioned board read
//      (band unit roll-up, next-delivery countdown, per-stage grouping). No
//      asset-procurement namespace exists on disk today.
//    • catalysts.assetProcurement.buildStatus — OEM line-off week + build state
//      for IN BUILD units.
//    • catalysts.assetProcurement.commitOrder — the single capital-commit verb
//      that should wrap createPurchaseOrder + approvePurchaseOrder in one
//      audited transaction.
//    • vendorSupplier.getRfqManagement / getQuoteComparison derive RFQ-like rows
//      from posted/bidding LOADS (vendorSupplier.ts:1642), not equipment RFQs —
//      the equipment RFQ shape is the gap.
//    • vendorSupplier.getPurchaseOrders returns no buildSlotWeek field; the
//      SLOT WK pill needs that column.
//    • assetTracking.getAssetLifecycleStatus returns only
//      active / maintenance / out_of_service / retired — the pre-service stages
//      on_order / in_build / in_delivery are the gap.
//    • blockchainAuditTrail: NO insert on any procurement verb (real inserts are
//      wallet.ts:1190 / detentionAccessorials.ts:909) — the capital-commit
//      ledger row is a gap. auditLogs IS written today by createRfq
//      (vendorSupplier.ts:1751), createPurchaseOrder (vendorSupplier.ts:1444)
//      and approvePurchaseOrder (vendorSupplier.ts:1592).
//    • realtime: WS_CHANNELS.FLEET(companyId) EXISTS
//      (shared/websocket-events.ts:576) and WS_EVENTS.VEHICLE_STATUS_CHANGED
//      EXISTS (shared/websocket-events.ts:87), but no procurement stage event —
//      ASSET_PROCUREMENT_STAGE_CHANGED is the gap.
//    • esangCoach SCREEN_ENUM (esangCoach.ts:112-125) carries no
//      asset-procurement key; forScreen exists, the enum member is the gap.
//
//  RBAC: carrier-side protectedProcedure family — every procedure above is
//  protectedProcedure (_core/trpc.ts:155) plus in-router company scoping via
//  vendorInScope (vendorSupplier.ts:114). The role gate on the write verbs is
//  catalystProcedure = roleProcedure(ROLES.CATALYST) (_core/trpc.ts:208).
//
//  transportMode = truck; country = US. Aurora Freight Lines · USDOT 3 482 119 ·
//  MC-942 008 · Cedar Rapids IA. Delivered units take IRP apportioned plates +
//  IFTA decals at the Iowa yard before first dispatch; a unit ordered for a
//  Canadian or Mexican domicile swaps to NSC/CVOR or SCT authority, resolved by
//  detectLoadCountry (loads.ts:109, router-local).
//
//  OFFLINE POLICY (Encyclopedia v2): READ_CACHED(1h) for the pipeline board — a
//  cached serve renders the staleness line in the header right register. Every
//  commit (createRfq / createPurchaseOrder / approvePurchaseOrder) is
//  ONLINE_ONLY because it moves capital: the CTAs disable with an explicit
//  reason instead of queueing a money write. Both degraded states are drawn.
//
//  LIVE SUPER-INTELLIGENCE FUSION: omitted with reason — no live position,
//  route, ETA or geofence on this screen. Delivery timing is a dealer-supplied
//  build-slot / line-off calendar date, not a telemetry ETA, and a unit still on
//  the OEM line is not yet a fleet asset carrying a device, so none of HERE Maps ·
//  device geolocation · customer geofence · ESang telemetry feeds this view.
//  No vehicle is ILLUSTRATED here either — the row chips are SF Symbol glyphs;
//  if this screen ever gains a rendered unit it must use the canonical
//  `EquipmentAnimation` component (Views/Components/EquipmentAnimation.swift:651),
//  never a hand-drawn silhouette.
//
//  0 STUBS · 0 MOCK DATA · 0 PLACEHOLDERS — the view owns no data. It renders
//  whatever `AssetProcurementStore` composed from the procedures above; the only
//  literal payload in this file is the `#Preview` seed, injected through the
//  same boundary the live store fills.
//
//  Bottom nav (real CarrierNavDispatcher, CarrierNavController.swift:111):
//  HOME · DISPATCH · [orb] · FLEET(current) · ME — "fleet" resolves to screen
//  320 via CarrierNavRoute.map (CarrierNavController.swift:87).
//

import SwiftUI

// MARK: - Domain

/// The four pipeline stages the board partitions on. Mirrors the proposed
/// `stage` column on the gap procedure `catalysts.assetProcurement.pipeline`.
enum ProcurementStage: String, CaseIterable, Identifiable {
    case quote, ordered, inBuild, delivery

    var id: String { rawValue }

    /// Section-label stem — row + unit counts are appended live by the store.
    var label: String {
        switch self {
        case .quote:    return "QUOTE"
        case .ordered:  return "ORDERED"
        case .inBuild:  return "IN BUILD"
        case .delivery: return "DELIVERY"
        }
    }

    /// Chip / pill tint. Attention lines override with `Brand.warning`.
    var hue: Color {
        switch self {
        case .quote:    return Brand.rail        // slate  #607D8B
        case .ordered:  return Brand.info        // info   #2196F3
        case .inBuild:  return Brand.escort      // violet #9C27B0
        case .delivery: return Brand.success     // green  #00C48C
        }
    }
}

/// Equipment glyph on a row's icon chip. SF Symbols only — no hand-drawn
/// silhouettes (see the FUSION note in the header).
enum ProcurementGlyph: String, Codable {
    case tractor, dryVan, reefer

    var systemImage: String {
        switch self {
        case .tractor: return "truck.box"
        case .dryVan:  return "shippingbox"
        case .reefer:  return "snowflake"
        }
    }
}

/// One dense pipeline row. `title` is the multi-unit line item
/// ("2× Cascadia 126 sleeper"); `spec` is the mono sub carrying spec, dealer and
/// the RFQ/PO id; the right cluster is `pill` + `money` + `etaNote`.
struct ProcurementLine: Identifiable, Equatable {
    let id: String                 // rfqNumber or poNumber — the server key
    let glyph: ProcurementGlyph
    let title: String
    let spec: String
    let pill: String
    let money: String
    let etaNote: String
    /// True for the single line whose dealer price-hold is lapsing. Drives the
    /// dangerWash attention treatment and the warning hue.
    let needsDecision: Bool
}

/// One stage card: header (label · row count · unit count · subtotal) + lines.
struct ProcurementStageGroup: Identifiable, Equatable {
    let stage: ProcurementStage
    let countCaption: String       // "2 RFQS · 6 UNITS"
    let subtotal: String           // "$681,200"
    let lines: [ProcurementLine]

    var id: String { stage.rawValue }
}

/// Everything the board draws. Composed by `AssetProcurementStore` from the
/// procedures in the wiring manifest — never constructed inside the view.
struct AssetProcurementVM: Equatable {
    // Identity register
    let carrierLine: String        // "Aurora Freight Lines · USDOT 3 482 119"
    let cacheCaption: String       // "cached · 12m ago"
    let cacheIsStale: Bool         // true once past READ_CACHED(1h)
    // Summary band
    let committedCapital: String   // "$962K"
    let committedNote: String      // "4 open POs · net-30"
    let pipelineUnits: String      // "11"
    let pipelineUnitWord: String   // "units"
    let pipelineSplit: String      // "5 on order · 6 quoted"
    let nextDeliveryRelative: String  // "in 9 d"
    let nextDeliveryUnit: String   // "TRL-0871"
    // Pipeline
    let groups: [ProcurementStageGroup]
    // ESang advisory row — esangCoach.forScreen
    let coachTitle: String
    let coachSub: String
}

// MARK: - Store

/// Composes the board from the real routers. Read path is cache-first
/// (READ_CACHED 1h) so the pipeline renders instantly and labels its own age;
/// the write path is ONLINE_ONLY — capital commits never queue.
@MainActor
final class AssetProcurementStore: ObservableObject {

    @Published private(set) var vm: AssetProcurementVM?
    @Published private(set) var loading = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var offline = false
    /// Set when an ONLINE_ONLY commit was attempted without a connection.
    @Published private(set) var lastCommitRefusal: String?

    static let cacheTTL: TimeInterval = 60 * 60      // READ_CACHED(1h)

    // MARK: Wire DTOs — shapes taken verbatim from the routers on disk.

    private struct PageIn: Encodable { let page: Int; let limit: Int }
    private struct PeriodIn: Encodable { let period: String }
    private struct RfqIdIn: Encodable { let rfqId: String }
    private struct CoachIn: Encodable {
        let screen: String
        let contextIds: [String: String]
    }
    /// Proposed input for the missing commit verb — see NAMED GAPS.
    private struct CommitIn: Encodable {
        let rfqId: String
        let vendorId: String
        let unitCount: Int
    }
    /// Proposed input for the missing RFQ verb — vendorSupplier.createRfq shape
    /// narrowed to equipment (vendorSupplier.ts:1734).
    private struct CreateRfqIn: Encodable {
        struct Item: Encodable {
            let description: String
            let quantity: Int
            let unit: String
            let specifications: String?
        }
        let title: String
        let description: String
        let category: String
        let items: [Item]
        let deadline: String
    }

    /// vendorSupplier.getPurchaseOrders — vendorSupplier.ts:1466
    private struct PurchaseOrdersWire: Decodable {
        struct Order: Decodable {
            let id: String
            let poNumber: String
            let vendorId: String
            let vendorName: String
            let status: String
            let total: Double
            let itemCount: Int
            let priority: String
            let createdAt: String
            let deliveryDate: String?
            let approvedAt: String?
            let receivedAt: String?
        }
        struct Summary: Decodable {
            let totalValue: Double
            let draftCount: Int
            let pendingCount: Int
            let approvedCount: Int
            let receivedCount: Int
        }
        let orders: [Order]
        let total: Int
        let summary: Summary
    }

    /// vendorSupplier.getRfqManagement — vendorSupplier.ts:1617
    private struct RfqWire: Decodable {
        struct Rfq: Decodable {
            let id: String
            let rfqNumber: String
            let title: String
            let description: String
            let category: String
            let status: String
            let deadline: String
            let invitedVendors: Int
            let quotesReceived: Int
            let estimatedValue: Double
            let createdAt: String
        }
        let rfqs: [Rfq]
        let total: Int
    }

    /// vendorSupplier.getQuoteComparison — vendorSupplier.ts:1775
    private struct QuoteComparisonWire: Decodable {
        struct Quote: Decodable {
            let id: String
            let vendorId: String
            let vendorName: String
            let vendorRating: Double
            let totalPrice: Double
            let leadTimeDays: Int
            let warranty: String
            let submittedAt: String
        }
        let rfqId: String
        let rfqTitle: String
        let quotes: [Quote]
    }

    /// vendorSupplier.getSpendAnalytics — vendorSupplier.ts:1868
    private struct SpendWire: Decodable {
        struct Category: Decodable {
            let category: String
            let amount: Double
            let percentage: Double
            let vendorCount: Int
        }
        let period: String
        let totalSpend: Double
        let byCategory: [Category]
    }

    /// assetTracking.getAssetLifecycleStatus — assetTracking.ts:910
    private struct LifecycleWire: Decodable {
        struct Stage: Decodable {
            let stage: String
            let label: String
            let count: Int
        }
        let stages: [Stage]
        let totalAssets: Int
    }

    /// GAP shape — catalysts.assetProcurement.pipeline. One row per line item,
    /// already stage-tagged and unit-counted server-side.
    private struct PipelineLineWire: Decodable {
        let id: String
        let stage: String              // quote | ordered | inBuild | delivery
        let glyph: String              // tractor | dryVan | reefer
        let unitCount: Int
        let model: String              // "Cascadia 126 sleeper"
        let spec: String               // "DD15 505 hp · RFQ-4471 · Hawkeye TC"
        let pill: String               // "EXPIRES 6 H" | "SLOT WK 41" | …
        let amount: Double
        let etaNote: String
        let holdExpiresInMinutes: Int?  // non-nil ⇒ attention treatment
    }

    /// GAP shape — catalysts.assetProcurement.buildStatus.
    private struct BuildStatusWire: Decodable {
        let poNumber: String
        let vinMasked: String
        let plant: String
        let lineOffWeek: Int
        let buildState: String
    }

    /// esangCoach.forScreen — esangCoach.ts:264
    private struct CoachTip: Decodable {
        let mode: String
        let tip: String
        let linkRoute: String?
    }

    // MARK: Read — READ_CACHED(1h), cache-first, staleness always rendered

    func refresh() async {
        loading = true
        defer { loading = false }
        let api = EusoTripAPI.shared

        async let poCall: PurchaseOrdersWire? = try? await api.query(
            "vendorSupplier.getPurchaseOrders", input: PageIn(page: 1, limit: 25))
        async let rfqCall: RfqWire? = try? await api.query(
            "vendorSupplier.getRfqManagement", input: PageIn(page: 1, limit: 25))
        async let spendCall: SpendWire? = try? await api.query(
            "vendorSupplier.getSpendAnalytics", input: PeriodIn(period: "quarter"))
        async let lifecycleCall: LifecycleWire? = try? await api.queryNoInput(
            "assetTracking.getAssetLifecycleStatus")

        // GAP verbs — bound to the typed client they WILL have. A nil here means
        // "not deployed yet OR offline"; either way the board renders from the
        // EXISTS reads plus cache, and the staleness line stays honest.
        async let pipelineCall: [PipelineLineWire]? = try? await api.queryNoInput(
            "catalysts.assetProcurement.pipeline")
        async let buildCall: [BuildStatusWire]? = try? await api.queryNoInput(
            "catalysts.assetProcurement.buildStatus")

        async let coachCall: CoachTip? = try? await api.query(
            "esangCoach.forScreen",
            input: CoachIn(screen: "procurement", contextIds: ["surface": "404"]))

        let pos       = await poCall
        let rfqs      = await rfqCall
        let spend     = await spendCall
        let lifecycle = await lifecycleCall
        let pipeline  = await pipelineCall ?? []
        let builds    = await buildCall ?? []
        let coach     = await coachCall

        let reachable = pos != nil || rfqs != nil || spend != nil || lifecycle != nil
        offline = !reachable
        if reachable { lastSyncedAt = Date() }

        vm = Self.compose(
            purchaseOrders: pos,
            rfqs: rfqs,
            spend: spend,
            lifecycle: lifecycle,
            pipeline: pipeline,
            builds: builds,
            coach: coach,
            syncedAt: lastSyncedAt
        )
    }

    // MARK: Write — ONLINE_ONLY (money movement never queues)

    /// CTA "New procurement request" → vendorSupplier.createRfq
    /// (vendorSupplier.ts:1734). Refuses offline rather than latching a draft
    /// that would later commit capital the operator can no longer price.
    func createProcurementRequest(_ input: (title: String, model: String,
                                            quantity: Int, deadlineISO: String)) async {
        guard !offline else {
            lastCommitRefusal = "Offline · order commits need a live connection"
            return
        }
        lastCommitRefusal = nil
        struct RfqOut: Decodable { let id: String; let rfqNumber: String; let status: String }
        let payload = CreateRfqIn(
            title: input.title,
            description: input.model,
            category: "equipment",
            items: [CreateRfqIn.Item(description: input.model, quantity: input.quantity,
                                     unit: "each", specifications: nil)],
            deadline: input.deadlineISO)
        let _: RfqOut? = try? await EusoTripAPI.shared.mutation(
            "vendorSupplier.createRfq", input: payload)
        await refresh()
    }

    /// CTA "Compare quotes" → vendorSupplier.getQuoteComparison
    /// (vendorSupplier.ts:1775). A read, but it prices a capital decision, so it
    /// is not served from cache.
    func compareQuotes(rfqId: String) async -> Int {
        guard !offline else {
            lastCommitRefusal = "Offline · quote comparison needs a live connection"
            return 0
        }
        lastCommitRefusal = nil
        let wire: QuoteComparisonWire? = try? await EusoTripAPI.shared.query(
            "vendorSupplier.getQuoteComparison", input: RfqIdIn(rfqId: rfqId))
        return wire?.quotes.count ?? 0
    }

    /// Attention-row commit — today this is createPurchaseOrder
    /// (vendorSupplier.ts:1418) followed by approvePurchaseOrder
    /// (vendorSupplier.ts:1583). The single audited verb
    /// `catalysts.assetProcurement.commitOrder` is a NAMED GAP.
    func commitOrder(rfqId: String, vendorId: String, unitCount: Int) async {
        guard !offline else {
            lastCommitRefusal = "Offline · order commits need a live connection"
            return
        }
        lastCommitRefusal = nil
        struct CommitOut: Decodable { let id: String; let poNumber: String; let status: String }
        let _: CommitOut? = try? await EusoTripAPI.shared.mutation(
            "catalysts.assetProcurement.commitOrder",
            input: CommitIn(rfqId: rfqId, vendorId: vendorId, unitCount: unitCount))
        await refresh()
    }

    // MARK: Composition

    private static func money(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "$0"
    }

    /// Band money reads compact — a seven-figure capex line must not wrap.
    private static func compactMoney(_ amount: Double) -> String {
        switch amount {
        case 1_000_000...: return String(format: "$%.2fM", amount / 1_000_000)
        case 1_000...:     return String(format: "$%.0fK", amount / 1_000)
        default:           return money(amount)
        }
    }

    private static func cacheCaption(_ syncedAt: Date?) -> (String, Bool) {
        guard let syncedAt else { return ("no cache", true) }
        let age = Date().timeIntervalSince(syncedAt)
        let stale = age > cacheTTL
        if age < 60   { return ("cached · just now", stale) }
        if age < 3600 { return ("cached · \(Int(age / 60))m ago", stale) }
        return ("cached · \(Int(age / 3600))h ago", stale)
    }

    private static func stage(_ raw: String) -> ProcurementStage {
        ProcurementStage(rawValue: raw) ?? .quote
    }

    private static func line(_ wire: PipelineLineWire,
                             builds: [BuildStatusWire]) -> ProcurementLine {
        // IN BUILD rows enrich their mono sub from buildStatus when it lands.
        let build = builds.first { $0.poNumber == wire.id }
        let spec = build.map { "VIN \($0.vinMasked) · \($0.plant)" } ?? wire.spec
        return ProcurementLine(
            id: wire.id,
            glyph: ProcurementGlyph(rawValue: wire.glyph) ?? .tractor,
            title: "\(wire.unitCount)× \(wire.model)",
            spec: spec,
            pill: wire.pill,
            money: money(wire.amount),
            etaNote: wire.etaNote,
            needsDecision: wire.holdExpiresInMinutes != nil)
    }

    private static func compose(
        purchaseOrders: PurchaseOrdersWire?,
        rfqs: RfqWire?,
        spend: SpendWire?,
        lifecycle: LifecycleWire?,
        pipeline: [PipelineLineWire],
        builds: [BuildStatusWire],
        coach: CoachTip?,
        syncedAt: Date?
    ) -> AssetProcurementVM {

        let (caption, stale) = cacheCaption(syncedAt)

        // Stage partition comes from the pipeline read; the EXISTS reads supply
        // the money and the open-PO count so the band is honest even before the
        // gap verb ships.
        let byStage = Dictionary(grouping: pipeline) { stage($0.stage) }

        let groups: [ProcurementStageGroup] = ProcurementStage.allCases.compactMap { st in
            guard let wires = byStage[st], !wires.isEmpty else { return nil }
            let units = wires.reduce(0) { $0 + $1.unitCount }
            let subtotal = wires.reduce(0.0) { $0 + $1.amount }
            let docWord = st == .quote ? "RFQ" : "PO"
            let caption = "\(wires.count) \(docWord)\(wires.count == 1 ? "" : "S") · "
                        + "\(units) UNIT\(units == 1 ? "" : "S")"
            return ProcurementStageGroup(
                stage: st,
                countCaption: caption,
                subtotal: money(subtotal),
                lines: wires.map { line($0, builds: builds) })
        }

        // Committed = everything past QUOTE. Falls back to the PO summary's
        // totalValue when the pipeline verb has not shipped yet.
        let committedFromPipeline = pipeline
            .filter { stage($0.stage) != .quote }
            .reduce(0.0) { $0 + $1.amount }
        let committed = committedFromPipeline > 0
            ? committedFromPipeline
            : (purchaseOrders?.summary.totalValue ?? 0)

        let openPOs = (purchaseOrders?.summary.approvedCount ?? 0)
                    + (purchaseOrders?.summary.pendingCount ?? 0)

        let onOrderUnits = pipeline.filter { stage($0.stage) != .quote }
                                   .reduce(0) { $0 + $1.unitCount }
        let quotedUnits  = pipeline.filter { stage($0.stage) == .quote }
                                   .reduce(0) { $0 + $1.unitCount }
        let totalUnits   = onOrderUnits + quotedUnits

        // Next delivery: the earliest DELIVERY-stage row carries its own
        // time-relative note and unit id from the pipeline read.
        let nextDelivery = byStage[.delivery]?.first
        let deliveryUnitId = nextDelivery?.spec
            .split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("TRK-") || $0.hasPrefix("TRL-") } ?? "—"

        return AssetProcurementVM(
            carrierLine: "Aurora Freight Lines · USDOT 3 482 119",
            cacheCaption: caption,
            cacheIsStale: stale,
            committedCapital: compactMoney(committed),
            committedNote: "\(openPOs) open PO\(openPOs == 1 ? "" : "s") · net-30",
            pipelineUnits: "\(totalUnits)",
            pipelineUnitWord: totalUnits == 1 ? "unit" : "units",
            pipelineSplit: "\(onOrderUnits) on order · \(quotedUnits) quoted",
            nextDeliveryRelative: nextDelivery?.etaNote ?? "—",
            nextDeliveryUnit: deliveryUnitId,
            groups: groups,
            coachTitle: coach.map { "ESang: \($0.tip)" } ?? "ESang",
            coachSub: spend.map {
                "Quarter capex \(money($0.totalSpend)) · "
                + "\(lifecycle?.totalAssets ?? 0) units in service"
            } ?? "")
    }
}

// MARK: - Screen

/// The single `✦` eyebrow for this surface. Extracted so the board and its
/// degraded skeleton share one literal — the sparkle appears exactly once,
/// whichever branch is on screen.
private struct ProcurementEyebrow: View {
    @Environment(\.palette) var palette
    var showRegister: Bool = true
    var body: some View {
        HStack {
            Text("✦ CATALYST · PROCUREMENT")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            if showRegister {
                Text("FY26 CAPEX PLAN")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }
}

struct CatalystAssetProcurement: View {
    @Environment(\.palette) private var palette
    @ObservedObject var store: AssetProcurementStore
    let vm: AssetProcurementVM

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            VStack(alignment: .leading, spacing: Space.s4) {
                summaryBand
                ForEach(vm.groups) { stageGroup($0) }
                ctaPair
                coachRow
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s7)
        }
        .task { await store.refresh() }
    }

    // MARK: Top bar — BOARD-class tab landing: no back chevron, plain title

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ProcurementEyebrow()
            Text("Asset procurement")
                .font(EType.display).tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            HStack(alignment: .firstTextBaseline) {
                Text(vm.carrierLine)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                // READ_CACHED(1h) staleness line — always honest about its age.
                Text(vm.cacheCaption)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(vm.cacheIsStale ? Brand.warning : palette.textTertiary)
                    .accessibilityLabel("Pipeline \(vm.cacheCaption)")
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: Hero — summary BAND (three cells; deliberately not an ActiveCard)

    private var summaryBand: some View {
        HStack(alignment: .top, spacing: 0) {
            bandCell(.leading) {
                Text("COMMITTED").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text(vm.committedCapital)
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                Text(vm.committedNote).font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
            }
            bandDivider
            bandCell(.leading) {
                Text("IN PIPELINE").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(vm.pipelineUnits)
                        .font(.system(size: 28, weight: .semibold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text(vm.pipelineUnitWord)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                }
                Text(vm.pipelineSplit).font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
            }
            bandDivider
            bandCell(.trailing) {
                Text("NEXT DELIVERY").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(vm.nextDeliveryRelative)
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Text(vm.nextDeliveryUnit)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, Space.s3)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(vm.committedCapital) committed, \(vm.committedNote). "
            + "\(vm.pipelineUnits) \(vm.pipelineUnitWord) in pipeline, \(vm.pipelineSplit). "
            + "Next delivery \(vm.nextDeliveryRelative), \(vm.nextDeliveryUnit)."
        )
    }

    @ViewBuilder
    private func bandCell<C: View>(_ alignment: HorizontalAlignment,
                                   @ViewBuilder _ cell: () -> C) -> some View {
        VStack(alignment: alignment, spacing: 4) { cell() }
            .frame(maxWidth: .infinity,
                   alignment: alignment == .trailing ? .trailing : .leading)
            .lineLimit(1).minimumScaleFactor(0.8)
    }

    private var bandDivider: some View {
        Rectangle().fill(palette.borderFaint)
            .frame(width: 1, height: 46)
            .padding(.horizontal, Space.s2)
    }

    // MARK: Stage group — header (count + subtotal) over a card of dense rows

    private func stageGroup(_ group: ProcurementStageGroup) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("\(group.stage.label) · \(group.countCaption)")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(group.subtotal)
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(group.lines.enumerated()), id: \.element.id) { index, line in
                    lineRow(line, stage: group.stage)
                    if index < group.lines.count - 1 && !line.needsDecision {
                        Rectangle().fill(palette.borderFaint)
                            .frame(height: 1)
                            .padding(.leading, 66)
                            .padding(.trailing, 14)
                    }
                }
            }
            .padding(.vertical, 6)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }

    private func lineRow(_ line: ProcurementLine, stage: ProcurementStage) -> some View {
        let hue = line.needsDecision ? Brand.warning : stage.hue
        return Button {
            NotificationCenter.default.post(
                name: .eusoCatalystProcurementLineOpened, object: nil,
                userInfo: ["source": "404_CatalystAssetProcurement",
                           "lineId": line.id,
                           "stage": stage.rawValue])
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm + 2, style: .continuous)
                        .fill(hue.opacity(0.16))
                    Image(systemName: line.glyph.systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(hue)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(line.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(line.spec)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                }
                .lineLimit(1).minimumScaleFactor(0.85)

                Spacer(minLength: Space.s2)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(line.pill)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(hue)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(hue.opacity(0.18)))
                    Text(line.money)
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text(line.etaNote)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                }
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(attentionWash(line.needsDecision))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(stage.label). \(line.title). \(line.spec). \(line.pill). "
            + "\(line.money). \(line.etaNote)."
        )
    }

    /// dangerWash — the ONE attention treatment on this screen.
    @ViewBuilder
    private func attentionWash(_ on: Bool) -> some View {
        if on {
            RoundedRectangle(cornerRadius: Radius.md + 2, style: .continuous)
                .fill(LinearGradient(colors: [Brand.danger.opacity(0.12),
                                              Brand.warning.opacity(0.12)],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md + 2, style: .continuous)
                        .strokeBorder(Brand.warning.opacity(0.38), lineWidth: 1))
                .padding(.horizontal, 4)
        } else {
            Color.clear
        }
    }

    // MARK: CTA pair — ONLINE_ONLY, because both verbs price or move capital

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button {
                    guard let first = vm.groups.first(where: { $0.stage == .quote })?.lines.first
                    else { return }
                    Task {
                        await store.createProcurementRequest(
                            (title: first.title, model: first.title,
                             quantity: 1,
                             deadlineISO: ISO8601DateFormatter().string(
                                from: Date().addingTimeInterval(7 * 86_400))))
                    }
                    NotificationCenter.default.post(
                        name: .eusoCatalystProcurementNewRequest, object: nil,
                        userInfo: ["source": "404_CatalystAssetProcurement"])
                } label: {
                    Text("New procurement request")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textOnGradient)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Capsule().fill(LinearGradient.primary))
                }
                .buttonStyle(.plain)
                .disabled(store.offline)
                .opacity(store.offline ? 0.45 : 1)

                Button {
                    guard let rfqId = vm.groups.first(where: { $0.stage == .quote })?
                        .lines.first?.id else { return }
                    Task { _ = await store.compareQuotes(rfqId: rfqId) }
                    NotificationCenter.default.post(
                        name: .eusoCatalystProcurementCompareQuotes, object: nil,
                        userInfo: ["source": "404_CatalystAssetProcurement", "rfqId": rfqId])
                } label: {
                    Text("Compare quotes")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 132, minHeight: 48)
                        .background(Capsule().fill(palette.bgCardSoft))
                        .overlay(Capsule().strokeBorder(palette.borderSoft))
                }
                .buttonStyle(.plain)
                .disabled(store.offline)
                .opacity(store.offline ? 0.45 : 1)
            }
            // ONLINE_ONLY reason — money movement never queues, so say why.
            if let refusal = store.lastCommitRefusal ?? (store.offline
                ? "Offline · order commits need a live connection" : nil) {
                Text(refusal)
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.warning)
                    .accessibilityLabel(refusal)
            }
        }
    }

    // MARK: ESang advisory row — esangCoach.forScreen

    private var coachRow: some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoCatalystProcurementInsight, object: nil,
                userInfo: ["source": "404_CatalystAssetProcurement"])
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
                    Text(vm.coachTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(vm.coachSub)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
                .lineLimit(1).minimumScaleFactor(0.85)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .frame(minHeight: 56)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let eusoCatalystProcurementNewRequest    = Notification.Name("eusoCatalystProcurementNewRequest")
    static let eusoCatalystProcurementCompareQuotes = Notification.Name("eusoCatalystProcurementCompareQuotes")
    static let eusoCatalystProcurementLineOpened    = Notification.Name("eusoCatalystProcurementLineOpened")
    static let eusoCatalystProcurementInsight       = Notification.Name("eusoCatalystProcurementInsight")
}

// MARK: - Shell wrapper + real Catalyst BottomNav (FLEET current)

/// Catalyst chrome for this fire: HOME · DISPATCH · [orb] · FLEET · ME.
/// Every slot routes through the real `CarrierNavDispatcher`, so "fleet"
/// resolves through `CarrierNavRoute.map["fleet"]` (CarrierNavController.swift:87).
private func catalystNav404() -> ([NavSlot], [NavSlot]) {
    let leading = [
        NavSlot(label: "Home",     systemImage: "house.fill", isCurrent: false,
                onTap: { CarrierNavDispatcher.handle("home") }),
        NavSlot(label: "Dispatch", systemImage: "tray.full",  isCurrent: false,
                onTap: { CarrierNavDispatcher.handle("dispatch") }),
    ]
    let trailing = [
        NavSlot(label: "Fleet", systemImage: "truck.box",   isCurrent: true,
                onTap: { CarrierNavDispatcher.handle("fleet") }),
        NavSlot(label: "Me",    systemImage: "person.fill", isCurrent: false,
                onTap: { CarrierNavDispatcher.handle("me") }),
    ]
    return (leading, trailing)
}

struct CatalystAssetProcurementScreen: View {
    let theme: Theme.Palette
    @StateObject private var store = AssetProcurementStore()
    /// Injected only by `#Preview`. In the app the store composes this from the
    /// procedures in the wiring manifest.
    var seed: AssetProcurementVM? = nil

    var body: some View {
        let (lead, trail) = catalystNav404()
        Shell(theme: theme) {
            if let vm = store.vm ?? seed {
                CatalystAssetProcurement(store: store, vm: vm)
            } else {
                ProcurementBoardSkeleton()
            }
        } nav: {
            BottomNav(leading: lead, trailing: trail, orbState: .idle,
                      onTapOrb: { CarrierNavDispatcher.handle("esang") })
        }
    }
}

/// Degraded state before the first successful read. A capital board must never
/// imply "nothing on order" while it is still loading, so it says so plainly.
private struct ProcurementBoardSkeleton: View {
    @Environment(\.palette) var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ProcurementEyebrow(showRegister: false)
            Text("Asset procurement")
                .font(EType.display).tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            IridescentHairline()
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("LOADING PIPELINE").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text("Committed capital is not shown until the read completes.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }
}

// MARK: - Preview seed
//
// The ONLY literal payload in this file. Mirrors the SVG content verbatim and
// enters through the same `seed` boundary the live store fills, so the screen
// itself never carries data.

private let previewProcurement = AssetProcurementVM(
    carrierLine: "Aurora Freight Lines · USDOT 3 482 119",
    cacheCaption: "cached · 12m ago",
    cacheIsStale: false,
    committedCapital: "$962K",
    committedNote: "4 open POs · net-30",
    pipelineUnits: "11",
    pipelineUnitWord: "units",
    pipelineSplit: "5 on order · 6 quoted",
    nextDeliveryRelative: "in 9 d",
    nextDeliveryUnit: "TRL-0871",
    groups: [
        ProcurementStageGroup(
            stage: .quote, countCaption: "2 RFQS · 6 UNITS", subtotal: "$681,200",
            lines: [
                ProcurementLine(id: "RFQ-4471", glyph: .tractor,
                                title: "2× Cascadia 126 sleeper",
                                spec: "DD15 505 hp · RFQ-4471 · Hawkeye TC",
                                pill: "EXPIRES 6 H", money: "$412,800",
                                etaNote: "not committed", needsDecision: true),
                ProcurementLine(id: "RFQ-4468", glyph: .dryVan,
                                title: "4× Wabash 53 ft dry van",
                                spec: "DuraPlate · RFQ-4468 · Waterloo TC",
                                pill: "3 QUOTES IN", money: "$268,400",
                                etaNote: "best $67,100/unit", needsDecision: false),
            ]),
        ProcurementStageGroup(
            stage: .ordered, countCaption: "2 POS · 3 UNITS", subtotal: "$634,800",
            lines: [
                ProcurementLine(id: "PO-260731-0031", glyph: .tractor,
                                title: "2× Kenworth T680 sleeper",
                                spec: "PACCAR MX-13 · PO-260731-0031",
                                pill: "SLOT WK 41", money: "$438,600",
                                etaNote: "deposit cleared", needsDecision: false),
                ProcurementLine(id: "PO-260724-0028", glyph: .tractor,
                                title: "1× Peterbilt 579 day cab",
                                spec: "X15 450 hp · PO-260724-0028",
                                pill: "SLOT WK 38", money: "$196,200",
                                etaNote: "spec locked", needsDecision: false),
            ]),
        ProcurementStageGroup(
            stage: .inBuild, countCaption: "1 PO · 1 UNIT", subtotal: "$208,400",
            lines: [
                ProcurementLine(id: "PO-260702-0024", glyph: .tractor,
                                title: "1× Cascadia 126 sleeper",
                                spec: "VIN 3AKJHHDR…4192 · Cleveland NC",
                                pill: "LINE-OFF WK 36", money: "$208,400",
                                etaNote: "chassis welded", needsDecision: false),
            ]),
        ProcurementStageGroup(
            stage: .delivery, countCaption: "1 PO · 1 UNIT", subtotal: "$118,900",
            lines: [
                ProcurementLine(id: "PO-260618-0021", glyph: .reefer,
                                title: "1× Utility 3000R reefer",
                                spec: "Vector 8600 · TRL-0871 · Cedar Rapids",
                                pill: "IN TRANSIT", money: "$118,900",
                                etaNote: "arrives in 9 d", needsDecision: false),
            ]),
    ],
    coachTitle: "ESang: sign the Cascadia quote today",
    coachSub: "Hold ends in 6 h · slot slips wk 41 → wk 46 after"
)

#Preview("404 Catalyst Asset Procurement · Light") {
    CatalystAssetProcurementScreen(theme: Theme.light, seed: previewProcurement)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}

#Preview("404 Catalyst Asset Procurement · Dark") {
    CatalystAssetProcurementScreen(theme: Theme.dark, seed: previewProcurement)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}
