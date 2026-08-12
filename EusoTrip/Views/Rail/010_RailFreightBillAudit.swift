//
//  010_RailFreightBillAudit.swift
//  EusoTrip — Rail · Shipper · Freight Bill Audit (brick 010).
//
//  PURPOSE. The three-way match on a rail freight bill: what the railroad
//  billed, what the contract says it should have been, and every line where
//  those two disagree — with the recovery filed from the same screen.
//
//  Verbatim port of 05 Rail/Light-SVG/010 Rail Freight Bill Audit.svg (Light +
//  Dark). Register mirrored block-for-block: eyebrow + audit-verdict register →
//  back-chevron breadcrumb + money-style billed title + invoice subline →
//  iridescent hairline → hero invoice card (billed vs tariff-expected, variance,
//  charge decomposition, exception badge, verdict rail) → EXCEPTIONS ledger
//  (severity dot, type tag, server message, tabular delta per line) → recoverable
//  strip → ESANG readout row → currency/tax-regime band → CTA pair → shipper
//  BottomNav with WALLET current.
//
//  ARCHETYPE = MONEY. A variance hero over a line-item exception ledger with a
//  recovery CTA — not a hero-card → 3-KPI → list stamp. The right rail of the
//  ledger is money, every figure is tabular, and the one big number on the page
//  is a variance, not a vanity metric.
//
//  WHERE THE LINE ITEMS COME FROM (the honest answer, worked first-hand).
//  `auditInvoice` does not fetch an invoice — it TAKES one. There is no rail
//  invoice storage anywhere in the schema, no EDI 210 ingest, and no document
//  parser that emits rail charge lines (`aiRateConReader` reads truck rate
//  confirmations and emits a load, not freight-bill lines). So the invoice side
//  of the match is CAPTURED here, line by line, off the paper/PDF bill — and the
//  capture affordance says so in plain words. The EXPECTED side is NOT captured:
//  the contracted linehaul and accrued demurrage come off `getRailSettlement`,
//  and the governing tariff rate + fuel-surcharge percent come off
//  `railTariff.lookup` (real `rail_tariffs` columns). Nothing on this screen is
//  pre-populated with a plausible-looking invoice.
//
//  WIRING MANIFEST (every line re-confirmed first-hand in the real files this fire):
//    EXISTS · railFreightAudit.ts:27  (MUTATION, .mutation at :44)
//               railFreightAudit.auditInvoice
//               in  { invoiceNumber, shipmentId?, lineItems:[{lineId, chargeType:
//                     "linehaul"|"fuel_surcharge"|"demurrage"|"switching"|
//                     "accessorial"|"detention"|"tax", description?, amount,
//                     carId?, unitCount?}], tariffContext?{expectedLinehaul?,
//                     expectedFsc?, expectedDemurrage?, fscPercent?} }
//               out { invoiceNumber, shipmentId, invoiceTotal, expectedTotal,
//                     varianceTotal, breakdown{linehaul,fuel,demurrage,other},
//                     exceptions[], auditStatus:"passed"|"flagged"|"failed" }
//               → the hero card, the exception ledger, the verdict register.
//               IT IS A `.mutation` EVEN THOUGH IT IS READ-ONLY PURE COMPUTE:
//               it touches no DB, writes no audit row and emits nothing. Sent via
//               mutation() = POST. The server has NO method override, so shipping
//               this as query() is a permanently dead CTA (fault class S4).
//               ACCEPTED-AND-IGNORED: the procedure never reads `description`,
//               `carId` or `unitCount`. This screen therefore does not ask for
//               them — collecting a field that cannot affect the result, or reach
//               the dispute, would be theatre.
//               NO CURRENCY: the engine has no currency field at all. It compares
//               the numbers you type against the numbers your contract holds. The
//               code shown beside the figures is the settlement's, not the audit's.
//    EXISTS · railFreightAudit.ts:103 (query)   railFreightAudit.recentAudits
//               in {limit?:1..100 default 20}
//               out { audits: [], total: 0, note: "Audit history requires invoice
//                     storage (not yet schema-backed)." } — HARDCODED honest-empty.
//               → rendered as the server's own `note`, VERBATIM. No history list
//                 is drawn, because there is no history to draw.
//    EXISTS · railFreightAudit.ts:122 (MUTATION) railFreightAudit.fileRecovery
//               in {invoiceId: string 1..120, findingIds: string[] max 100 = []}
//               out {disputeId:"DSP-<n>"|null, status:"open", findingCount}
//               → the primary CTA. Writes a `disputes` row (reason 'rate',
//                 counterpartyUserId 0 = unassigned) + a `dispute_events` 'created'
//                 row, so the recovery lands in the shared dispute queues.
//               WRITES NO `blockchainAuditTrail` ROW. BROADCASTS NO `WS_EVENTS.*`
//               — the router imports neither (grep count 0 in the file). Both are
//               said out loud on screen in the confirm gate, not just here.
//    EXISTS · railShipments.ts:412   (query)   railShipments.getRailShipmentDetail
//               in {id} → shipment spread + originYard/destinationYard + events +
//               waybills + demurrage. → route breadcrumb, reporting marks, real
//               shipment number, and the yard `country` enum the regime band reads.
//    EXISTS · railShipments.ts:1465  (query)   railShipments.getRailSettlement
//               in {shipmentId} → {shipmentId, shipmentNumber, status, linehaul,
//               demurrage, total, currency}. linehaul = rail_shipments.rate;
//               demurrage = SUM(rail_demurrage.totalCharge). → the shipment's own
//               contracted expectation. Returns null for a non-owner.
//    EXISTS · railTariff.ts:26       (query)   railTariff.lookup
//               (mounted routers.ts:3362) in {invoiceId: string 1..120}
//               out {baseRate, fscBasis:"<n>% of linehaul", rateType:"per_car"|
//                    "per_ton", resolvedShipment} — table-backed on rail_tariffs
//               (schema.ts:11350: ratePerCar / ratePerTon / fuelSurcharge /
//               carType / effective window), tenant-gated, honest nulls.
//               → the GOVERNING TARIFF: the fuel-surcharge percent the audit
//                 engine needs, and a per-car fallback for the linehaul
//                 expectation when rail_shipments.rate is empty.
//               NAMING DRIFT (worth fixing server-side): the parameter is called
//               `invoiceId` but it is matched against rail_shipments.shipmentNumber
//               and then .waybillNumber (railTariff.ts:50-51). It is a SHIPMENT
//               reference, not a freight-bill number — this screen therefore
//               passes the resolved shipment number, never the invoice number,
//               which would silently miss and return all-nulls.
//
//    STUB · named-gap · draftDisputeFromAudit — ABSENT. The SVG's <desc> names it
//               (and offers railDemurrageAuto.createDispute as an alternative).
//               THE DESC IS WRONG: `draftDisputeFromAudit` exists nowhere in the
//               web repo, and createDispute takes a `demurrageId` — a freight-bill
//               overcharge has none. `fileRecovery` is the real equivalent and is
//               what this screen calls. Record corrected.
//    STUB · named-gap · WS_EVENTS.AUDIT_DISPUTE_FILED — DOES NOT EXIST (zero hits
//               in the whole web repo). No broadcast is claimed anywhere on screen.
//    STUB · named-gap · NO indexed fuel-surcharge FEED. rail_tariffs.fuelSurcharge
//               is a static contract percent, not a period index — nothing in
//               server/ publishes a rail FSC index (every other fuelSurcharge
//               source is the truck lane's per-mile DOE formula, quotes.ts:412 /
//               rates.ts:571). So the expected FSC AMOUNT is derived here as
//               tariff-percent x contracted linehaul, the derivation is printed
//               on the card, and both figures stay editable for the period the
//               bill actually covers.
//    STUB · named-gap · NO tax-regime procedure. `cross_border_mx_taxes` is an MCP
//               tool (services/mcpServer.ts:2681), not tRPC; IVA 16% lives as a TS
//               constant at services/mxCrossBorderEnforcement.ts:213 with no client
//               exposure. The regime band is therefore static regulatory content
//               and is labelled as reference, not as a live rate.
//    DRIFT · getRailSettlement hardcodes currency "USD" at railShipments.ts:1487
//               regardless of the yard's real country. The band marks the true
//               country from the yard enum and the header strip states the
//               mismatch instead of pretending the code was derived.
//
//  RBAC. `railFreightAudit.*` is protectedProcedure — any authenticated user, no
//  role or mode gate, no tenant gate (auditInvoice is pure compute; fileRecovery
//  files the dispute under ctx.user.id). The two shipment reads are railProcedure
//  (requireUser + requireRailMode, _core/trpc.ts:267) plus the row-level
//  ownsRailShipmentRow tenant gate (railShipments.ts:137) — a non-owner gets null,
//  never another tenant's contract rate.
//
//  transportMode = rail. COUNTRY IS CONTENT, NOT A FILE FORK: one screen reads the
//  yard's real `country` enum (US | CA | MX) and swings the currency and tax band
//  with it — US · USD · no federal VAT · STB / FRA · CA · CAD · GST/HST ·
//  Transport Canada · MX · MXN · IVA 16% · ARTF / SICT. When no shipment is
//  linked, no regime is marked live rather than defaulting to US.
//
//  RBAC note: railTariff.lookup is railProcedure too, and carries its own
//  shipperId/companyId ownership check (railTariff.ts:58-61) — a non-owner gets
//  all-nulls rather than another tenant's contracted tariff.
//
//  OFFLINE POLICY (Encyclopedia v2): READ_CACHED(15m) for the contracted tariff
//  expectation and the audit-history note — the last good serve stays on screen
//  and always stamps its own age on a monospaced line that flips to Brand.warning
//  past the TTL, instead of blanking to zeros. Running the audit is ONLINE_ONLY
//  because the reconciliation engine lives on the server and nothing is computed
//  on-device. Filing a recovery is ONLINE_ONLY because it opens a dispute over
//  money — the CTA disables with an explicit on-screen reason instead of queueing.
//  Nothing here can queue in any case: only six paths are offline-eligible
//  (Services/EusoTripAPI.swift:1684) and no rail path is among them.
//
//  PRODUCTIVITY. It turns a rail freight bill into a line-by-line variance against
//  the shipper's own contract and files the overcharge as a real dispute in one
//  tap, so money left on an invoice gets recovered instead of quietly paid.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Charge types (verbatim zod enum · railFreightAudit.ts:32)

private enum ChargeType010: String, CaseIterable, Identifiable {
    case linehaul
    case fuelSurcharge = "fuel_surcharge"
    case demurrage
    case switching
    case accessorial
    case detention
    case tax

    var id: String { rawValue }

    var label: String {
        switch self {
        case .linehaul:      return "Linehaul"
        case .fuelSurcharge: return "Fuel surcharge"
        case .demurrage:     return "Demurrage"
        case .switching:     return "Switching"
        case .accessorial:   return "Accessorial"
        case .detention:     return "Detention"
        case .tax:           return "Tax"
        }
    }

    var tint: Color {
        switch self {
        case .linehaul:      return Brand.blue
        case .fuelSurcharge: return Brand.warning
        case .demurrage:     return Brand.danger
        case .switching:     return Brand.info
        case .accessorial:   return Brand.magenta
        case .detention:     return Brand.hazmat
        case .tax:           return Brand.rail
        }
    }
}

// MARK: - Captured invoice line (live user input — the only source that exists)

private struct DraftLine010: Identifiable {
    let id = UUID()
    var lineRef: String = ""
    var chargeType: ChargeType010 = .linehaul
    var amountText: String = ""

    /// Tolerant money parse — the shipper types what the bill prints.
    var amount: Double? {
        let cleaned = amountText
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let v = Double(cleaned), v.isFinite else { return nil }
        return v
    }
    var refTrimmed: String { lineRef.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isComplete: Bool { !refTrimmed.isEmpty && amount != nil }
}

// MARK: - Encodable inputs (hand-rolled so absent optionals are OMITTED, not null)
//
// Swift's synthesized encoder emits `null` for a nil optional and zod's
// `.optional()` rejects null. Every optional below goes through encodeIfPresent.

private struct AuditLineIn010: Encodable {
    let lineId: String
    let chargeType: String
    let amount: Double
}

private struct TariffContextIn010: Encodable {
    let expectedLinehaul: Double?
    let expectedFsc: Double?
    let expectedDemurrage: Double?
    let fscPercent: Double?

    var isEmpty: Bool {
        expectedLinehaul == nil && expectedFsc == nil
            && expectedDemurrage == nil && fscPercent == nil
    }

    private enum CodingKeys: String, CodingKey {
        case expectedLinehaul, expectedFsc, expectedDemurrage, fscPercent
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(expectedLinehaul, forKey: .expectedLinehaul)
        try c.encodeIfPresent(expectedFsc, forKey: .expectedFsc)
        try c.encodeIfPresent(expectedDemurrage, forKey: .expectedDemurrage)
        try c.encodeIfPresent(fscPercent, forKey: .fscPercent)
    }
}

private struct AuditInvoiceIn010: Encodable {
    let invoiceNumber: String
    let shipmentId: Int?
    let lineItems: [AuditLineIn010]
    let tariffContext: TariffContextIn010?

    private enum CodingKeys: String, CodingKey {
        case invoiceNumber, shipmentId, lineItems, tariffContext
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(invoiceNumber, forKey: .invoiceNumber)
        try c.encodeIfPresent(shipmentId, forKey: .shipmentId)
        try c.encode(lineItems, forKey: .lineItems)
        try c.encodeIfPresent(tariffContext, forKey: .tariffContext)
    }
}

private struct FileRecoveryIn010: Encodable {
    let invoiceId: String
    let findingIds: [String]
}

private struct RecentAuditsIn010: Encodable {
    let limit: Int
}

/// Round to whole cents. Money arithmetic on this screen is never allowed to
/// leak binary-float dust into a figure the shipper may dispute.
private func cents010(_ v: Double) -> Double {
    (v * 100).rounded() / 100
}

/// "12.5" / "12" — a percent printed without a trailing ".0".
private func trimNumber010(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
}

/// `railTariff.lookup` input. The key is named `invoiceId` server-side but is
/// matched against rail_shipments.shipmentNumber / .waybillNumber — the value
/// passed here is always the resolved SHIPMENT reference.
private struct TariffLookupIn010: Encodable {
    let invoiceId: String
}

private struct ShipmentDetailIn010: Encodable {
    let id: Int
}

private struct ShipmentIdIn010: Encodable {
    let shipmentId: Int
}

// MARK: - Decoded server shapes

/// `auditInvoice.breakdown` — four pure sums over the lines the client sent.
private struct AuditBreakdown010: Decodable {
    let linehaul: Double?
    let fuel: Double?
    let demurrage: Double?
    let other: Double?
}

/// One `AuditException` (railFreightAudit.ts:16). The server assigns NO id, so
/// the ledger keys on the array offset rather than inventing one.
private struct AuditException010: Decodable {
    let type: String?           // duplicate | overcharge | undercharge | missing_charge | stale_rate
    let severity: String?       // critical | warning | info
    let invoiceLineId: String?
    let expected: Double?
    let actual: Double?
    let variance: Double?
    let message: String?
}

private struct AuditResult010: Decodable {
    let invoiceNumber: String?
    let shipmentId: Int?
    let invoiceTotal: Double?
    let expectedTotal: Double?
    let varianceTotal: Double?
    let breakdown: AuditBreakdown010?
    let exceptions: [AuditException010]?
    let auditStatus: String?    // passed | flagged | failed
}

/// `recentAudits` — `audits` is hardcoded `[]` today. Every field is optional so
/// the decoder survives both today's empty serve and whatever shape invoice
/// storage lands with, without ever pretending a row exists.
private struct AuditHistoryRow010: Decodable {
    let id: Int?
    let invoiceNumber: String?
    let varianceTotal: Double?
    let auditStatus: String?
    let auditedAt: String?
}

private struct RecentAudits010: Decodable {
    let audits: [AuditHistoryRow010]?
    let total: Int?
    let note: String?
}

private struct FileRecoveryOut010: Decodable {
    let disputeId: String?
    let status: String?
    let findingCount: Int?
}

/// `getRailSettlement` — the shipment's own contracted linehaul + accrued
/// demurrage. Paired with `railTariff.lookup` for the governing tariff rate.
private struct RailSettlement010: Decodable {
    let shipmentId: Int?
    let shipmentNumber: String?
    let status: String?
    let linehaul: Double?
    let demurrage: Double?
    let total: Double?
    let currency: String?
}

/// `railTariff.lookup` — the governing rail_tariffs row for this shipment's
/// carrier + car type, inside its effective window. Every field can be null.
private struct RailTariff010: Decodable {
    let baseRate: Double?          // ratePerCar, else ratePerTon
    let fscBasis: String?          // "<n>% of linehaul" | null
    let rateType: String?          // "per_car" | "per_ton" | null
    let resolvedShipment: String?  // the shipmentNumber the ref matched
}

private struct RailYardNode010: Decodable {
    let name: String?
    let city: String?
    let state: String?
    let country: String?        // "US" | "CA" | "MX"
}

private struct RailShipmentHead010: Decodable {
    let id: Int?
    let shipmentNumber: String?
    let status: String?
    let numberOfCars: Int?
    let originRailroad: String?
    let destinationRailroad: String?
    let routeDescription: String?
    let originYard: RailYardNode010?
    let destinationYard: RailYardNode010?
}

// MARK: - Currency / tax regime band (static regulatory reference · see header)

private struct RegimeFacet010: Identifiable {
    let id: String              // "US" | "CA" | "MX"
    let currency: String
    let taxLine: String
    let regulator: String
}

private let regimeFacets010: [RegimeFacet010] = [
    RegimeFacet010(id: "US", currency: "USD", taxLine: "no fed VAT", regulator: "STB · FRA"),
    RegimeFacet010(id: "CA", currency: "CAD", taxLine: "GST/HST",    regulator: "Transport Canada"),
    RegimeFacet010(id: "MX", currency: "MXN", taxLine: "IVA 16%",    regulator: "ARTF · SICT")
]

// MARK: - Screen root

struct RailFreightBillAudit_010: View {
    let theme: Theme.Palette
    /// Optional shipment to pull the contracted tariff expectation from. 0 = the
    /// screen asks for one; `auditInvoice.shipmentId` is optional server-side, so
    /// an unlinked audit is a legitimate (if expectation-less) run.
    let shipmentId: Int

    init(theme: Theme.Palette = Theme.dark, shipmentId: Int = 0) {
        self.theme = theme
        self.shipmentId = shipmentId
    }

    var body: some View {
        Shell(theme: theme) {
            RailFreightBillAuditBody010(shipmentId: shipmentId)
        } nav: {
            // Shipper band, identical slot set to 002 Rail Shipment Detail and
            // 004 Rail Demurrage Detail — this must read as the same Shipper app,
            // never as a separate "Rail Shipper" product. WALLET is current
            // because a freight-bill audit is a financial surface (the SVG marks
            // it current for the same reason).
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house.fill",       isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: true),
                           NavSlot(label: "Me",     systemImage: "person.fill",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailFreightBillAuditBody010: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    let shipmentId: Int

    // Captured invoice (live user input — the only source of the billed side)
    @State private var invoiceNumberText: String = ""
    @State private var shipmentIdText: String = ""
    @State private var lines: [DraftLine010] = [DraftLine010()]
    @State private var expectedFscText: String = ""
    @State private var fscPercentText: String = ""
    @State private var showCapture: Bool = true

    // Server state
    @State private var head: RailShipmentHead010? = nil
    @State private var settlement: RailSettlement010? = nil
    @State private var tariff: RailTariff010? = nil
    @State private var history: RecentAudits010? = nil
    @State private var result: AuditResult010? = nil

    // Lifecycle
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Per-section degraded flags. A `try?`-swallowed read used to be
    /// indistinguishable from a genuinely empty one; these carry the difference
    /// to the surface so a dead tariff or a dead history says so out loud.
    @State private var tariffDegraded = false
    @State private var historyDegraded = false
    /// READ_CACHED(15m) — the last good serve stays and stamps its own age.
    @State private var lastSyncedAt: Date? = nil

    // Audit run (ONLINE_ONLY — the engine is server-side)
    @State private var auditing = false
    @State private var auditError: String? = nil

    // Recovery (ONLINE_ONLY — it opens a dispute over money)
    @State private var selectedFindings: Set<Int> = []
    @State private var showRecoveryGate = false
    @State private var filing = false
    @State private var recoveryError: String? = nil
    @State private var showHistorySheet = false
    @State private var toast: String? = nil

    private static let cacheTTL: TimeInterval = 15 * 60

    // MARK: Derived — identity

    private var invoiceNumberTrimmed: String {
        invoiceNumberText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var linkedShipmentId: Int? {
        let raw = shipmentIdText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = Int(raw), v > 0 else { return nil }
        return v
    }

    /// "US" | "CA" | "MX" from the real yard enum. Never defaulted.
    private var countryCode: String? {
        nonEmpty(head?.destinationYard?.country) ?? nonEmpty(head?.originYard?.country)
    }

    /// What the settlement endpoint actually returned. It hardcodes "USD"
    /// (railShipments.ts:1487) — displayed as-is, with the mismatch stated.
    private var currencyCode: String {
        nonEmpty(settlement?.currency) ?? "USD"
    }

    private var currencyIsAsserted: Bool {
        guard let c = countryCode, settlement != nil else { return false }
        switch c.uppercased() {
        case "CA": return currencyCode.uppercased() != "CAD"
        case "MX": return currencyCode.uppercased() != "MXN"
        default:   return false
        }
    }

    /// Origin + interchange reporting marks straight off the real columns.
    /// Never typed here; absent columns collapse the label instead of guessing.
    private var carrierMarks: String? {
        let origin = nonEmpty(head?.originRailroad)
        let interchange = nonEmpty(head?.destinationRailroad)
        switch (origin, interchange) {
        case let (o?, i?) where o != i: return "\(o) - \(i)"
        case let (o?, _):               return o
        case let (_, i?):               return i
        default:                        return nil
        }
    }

    private var routeTitle: String {
        let o = nonEmpty(head?.originYard?.city) ?? nonEmpty(head?.originYard?.name)
        let d = nonEmpty(head?.destinationYard?.city) ?? nonEmpty(head?.destinationYard?.name)
        if let o, let d { return "\(o) -> \(d)" }
        if let r = nonEmpty(head?.routeDescription) { return r }
        if let n = nonEmpty(head?.shipmentNumber) { return n }
        return "Freight bills"
    }

    private var sublineText: String {
        var parts: [String] = []
        if let marks = carrierMarks { parts.append(marks) }
        if !invoiceNumberTrimmed.isEmpty { parts.append(invoiceNumberTrimmed) }
        if let n = nonEmpty(head?.shipmentNumber) ?? nonEmpty(settlement?.shipmentNumber) { parts.append(n) }
        if parts.isEmpty {
            return "Capture the bill below - no rail invoice storage exists to load one from."
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Derived — verdict

    private var auditStatus: String? { nonEmpty(result?.auditStatus)?.lowercased() }

    private var verdictLabel: String {
        switch auditStatus {
        case "failed":  return "AUDIT FAILED"
        case "flagged": return "AUDIT FLAGGED"
        case "passed":  return "AUDIT PASSED"
        default:        return "NOT RUN"
        }
    }

    private var verdictColor: Color {
        switch auditStatus {
        case "failed":  return Brand.danger
        case "flagged": return Brand.warning
        case "passed":  return Brand.success
        default:        return palette.textTertiary
        }
    }

    private var exceptions: [AuditException010] { result?.exceptions ?? [] }
    private var criticalCount: Int {
        exceptions.filter { ($0.severity ?? "").lowercased() == "critical" }.count
    }

    /// The reference string that is actually filed for a finding. The server
    /// assigns no id, so we send its own `invoiceLineId` where it gave one and
    /// otherwise its own `type` plus the finding's position in the returned
    /// array. Nothing is invented and the row shows exactly what will be filed.
    private func findingRef(_ index: Int) -> String {
        guard index < exceptions.count else { return "finding#\(index + 1)" }
        let e = exceptions[index]
        if let ref = nonEmpty(e.invoiceLineId) { return ref }
        return "\(nonEmpty(e.type) ?? "finding")#\(index + 1)"
    }

    private var selectedFindingRefs: [String] {
        selectedFindings.sorted().map { findingRef($0) }
    }

    /// Arithmetic sum of the POSITIVE variances the server returned on the
    /// findings the user selected. A derivation over decoded fields — not a
    /// settled recovery figure, and labelled as such on screen.
    private var selectedOverchargeSum: Double {
        selectedFindings.sorted().reduce(into: 0.0) { acc, i in
            guard i < exceptions.count, let v = exceptions[i].variance, v > 0 else { return }
            acc += v
        }
    }

    // MARK: Derived — tariff expectation

    /// The contract's fuel-surcharge percent, off the governing rail_tariffs row.
    /// `fscBasis` is formatted "<n>% of linehaul" (railTariff.ts:90) — the leading
    /// number is taken rather than re-deriving anything.
    private var serverFscPercent: Double? {
        guard let raw = nonEmpty(tariff?.fscBasis) else { return nil }
        let numeric = raw.prefix { $0.isNumber || $0 == "." }
        guard let v = Double(numeric), v.isFinite, v > 0 else { return nil }
        return v
    }

    /// A typed value always wins; otherwise the contract's own percent is sent.
    private var fscPercent: Double? { parseMoney(fscPercentText) ?? serverFscPercent }

    /// The expected fuel-surcharge AMOUNT. No rail FSC index feed exists, so this
    /// is the contract arithmetic — tariff percent applied to the contracted
    /// linehaul — over two real columns. The formula is printed on the card and
    /// the field stays editable for the period the bill actually covers.
    private var derivedExpectedFsc: Double? {
        guard let pct = fscPercent, pct > 0, let lh = contractLinehaul, lh > 0 else { return nil }
        return cents010(lh * pct / 100)
    }
    private var expectedFsc: Double? { parseMoney(expectedFscText) ?? derivedExpectedFsc }

    /// The contracted linehaul. First choice is the shipment's own rate through
    /// getRailSettlement. When that column is empty, the governing tariff's
    /// per-car rate times the shipment's real car count is the honest second
    /// read — both are real columns, and the card says which one is in play.
    private var contractLinehaul: Double? {
        if let v = settlement?.linehaul, v > 0 { return v }
        if (tariff?.rateType ?? "") == "per_car",
           let rate = tariff?.baseRate, rate > 0,
           let cars = head?.numberOfCars, cars > 0 {
            return cents010(rate * Double(cars))
        }
        return nil
    }

    private var contractLinehaulIsDerived: Bool {
        !((settlement?.linehaul ?? 0) > 0) && contractLinehaul != nil
    }

    private var contractDemurrage: Double? {
        guard let v = settlement?.demurrage, v > 0 else { return nil }
        return v
    }

    private var tariffContextIn: TariffContextIn010 {
        TariffContextIn010(
            expectedLinehaul: contractLinehaul,
            expectedFsc: expectedFsc,
            expectedDemurrage: contractDemurrage,
            fscPercent: fscPercent
        )
    }

    // MARK: Derived — gates

    private var completeLines: [DraftLine010] { lines.filter { $0.isComplete } }

    private var captureBlockReason: String? {
        if invoiceNumberTrimmed.isEmpty { return "Enter the invoice number printed on the bill." }
        if completeLines.isEmpty { return "Add at least one charge line with a line reference and an amount." }
        if completeLines.count < lines.count {
            return "One or more lines are missing a line reference or a readable amount."
        }
        return nil
    }

    private var canRunAudit: Bool {
        captureBlockReason == nil && reach.isOnline && !auditing
    }

    private var runBlockReason: String? {
        if !reach.isOnline {
            return "Offline - the reconciliation engine runs live and nothing is computed on this device."
        }
        return captureBlockReason
    }

    private var canFileRecovery: Bool {
        result != nil && !selectedFindings.isEmpty && !invoiceNumberTrimmed.isEmpty
            && reach.isOnline && !filing
    }

    private var recoveryBlockReason: String? {
        if result == nil { return "Run the audit first - a recovery is filed against its findings." }
        if !reach.isOnline {
            return "Offline - filing a recovery opens a dispute over money and never queues. Reconnect to file it live."
        }
        if selectedFindings.isEmpty { return "Select at least one finding to file." }
        if invoiceNumberTrimmed.isEmpty { return "The invoice number is required to file." }
        return nil
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                breadcrumbRow
                moneyTitle
                subline
                IridescentHairline()
                    .padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    // Cold entry on a four-call fan-out used to show a bare
                    // capture form with no sign the screen was still reading.
                    if loading && head == nil && settlement == nil && history == nil && result == nil {
                        LifecycleCard {
                            Text("Loading the bill context…")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }

                    if let err = loadError { staleNote(err, danger: true) }
                    if let stamp = cacheAgeLine { staleNote(stamp, danger: false) }
                    if tariffDegraded {
                        staleNote("The governing tariff did not answer, so the expected linehaul and demurrage are absent from this run — findings below are computed without them.", danger: true)
                    }
                    if historyDegraded {
                        staleNote("Recent audits did not answer. The strip below is empty because the read failed, not because there is no history.", danger: true)
                    }

                    if result != nil {
                        heroInvoiceCard
                        exceptionsSection
                        flaggedVarianceStrip
                        readoutRow
                    }

                    captureSection
                    historyStrip
                    regimeBand
                    ctaPair
                }
                .padding(.top, Space.s5)

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task {
            // Seed the field from the injected id, then pass the id EXPLICITLY —
            // never read the @State back in the same pass and hope it settled.
            if shipmentIdText.isEmpty, shipmentId > 0 { shipmentIdText = String(shipmentId) }
            await load(forcedShipmentId: shipmentId > 0 ? shipmentId : nil)
        }
        .refreshable { await load() }
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $showRecoveryGate) { recoveryGateSheet }
        .sheet(isPresented: $showHistorySheet) { historySheet }
    }

    // MARK: - Top bar (eyebrow + verdict register)

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · RAIL · FREIGHT AUDIT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text(verdictLabel)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(verdictColor)
        }
    }

    private var breadcrumbRow: some View {
        HStack(spacing: Space.s2) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Text(routeTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.top, Space.s4)
    }

    private var moneyTitle: some View {
        Text(headlineText)
            .font(.system(size: 32, weight: .bold)).kerning(-0.6)
            .monospacedDigit()
            .foregroundStyle(LinearGradient.diagonal)
            .lineLimit(1).minimumScaleFactor(0.55)
            .padding(.top, Space.s3)
    }

    private var headlineText: String {
        if let t = result?.invoiceTotal { return "\(money(t)) billed" }
        return "Audit a freight bill"
    }

    private var subline: some View {
        Text(sublineText)
            .font(.system(size: 12))
            .foregroundStyle(palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: - Hero invoice card (billed vs tariff-expected)

    private var heroInvoiceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(heroEyebrow)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: Space.s2)
                Text(exceptionBadgeText)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(verdictColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(verdictColor.opacity(0.16)))
            }

            HStack(alignment: .firstTextBaseline) {
                Text(money(result?.invoiceTotal))
                    .font(.system(size: 30, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: Space.s3)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(expectedLine)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("Variance \(signedMoney(result?.varianceTotal))")
                        .font(.system(size: 13, weight: .bold)).monospacedDigit()
                        .foregroundStyle(varianceColor)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .padding(.top, Space.s4)

            Text(breakdownLine)
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s3)

            if (result?.expectedTotal ?? 0) <= 0 {
                Text("No tariff expectation was sent, so the variance is the full billed total. Link a shipment or enter an expected fuel surcharge to make the comparison real.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s2)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(alignment: .leading) { Rectangle().fill(verdictColor).frame(width: 3) }
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var heroEyebrow: String {
        let inv = nonEmpty(result?.invoiceNumber) ?? invoiceNumberTrimmed
        if let marks = carrierMarks, !inv.isEmpty { return "INVOICE TOTAL · \(marks.uppercased()) \(inv)" }
        if !inv.isEmpty { return "INVOICE TOTAL · \(inv)" }
        return "INVOICE TOTAL"
    }

    private var exceptionBadgeText: String {
        let n = exceptions.count
        if n == 0 { return "NO EXCEPTIONS" }
        if criticalCount > 0 { return "\(n) EXCEPTION\(n == 1 ? "" : "S") · \(criticalCount) CRIT" }
        return "\(n) EXCEPTION\(n == 1 ? "" : "S")"
    }

    private var expectedLine: String {
        guard let e = result?.expectedTotal, e > 0 else { return "No tariff expectation sent" }
        return "Tariff expected \(money(e))"
    }

    private var varianceColor: Color {
        guard let v = result?.varianceTotal else { return palette.textSecondary }
        if v > 0 { return Brand.danger }
        if v < 0 { return Brand.success }
        return palette.textSecondary
    }

    /// Server-computed decomposition — four real fields, never re-derived here.
    private var breakdownLine: String {
        guard let b = result?.breakdown else { return "Charge decomposition unavailable" }
        var parts: [String] = []
        if let v = b.linehaul,  v != 0 { parts.append("Linehaul \(money(v))") }
        if let v = b.fuel,      v != 0 { parts.append("FSC \(money(v))") }
        if let v = b.demurrage, v != 0 { parts.append("Demurrage \(money(v))") }
        if let v = b.other,     v != 0 { parts.append("Other \(money(v))") }
        return parts.isEmpty ? "No charges decoded on this invoice" : parts.joined(separator: " · ")
    }

    // MARK: - Exceptions ledger

    private var exceptionsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(exceptionsHeader)
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                if !exceptions.isEmpty {
                    Button(action: toggleSelectAll) {
                        Text(selectedFindings.count == exceptions.count ? "CLEAR ALL" : "SELECT ALL")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if exceptions.isEmpty {
                LifecycleCard {
                    Text("The audit returned no exceptions. Every line you captured reconciled against the expectation that was sent.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(exceptions.enumerated()), id: \.offset) { idx, e in
                        exceptionRow(idx, e)
                        if idx < exceptions.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.leading, Space.s4)
                        }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private var exceptionsHeader: String {
        let n = exceptions.count
        if n == 0 { return "EXCEPTIONS · NONE" }
        return "EXCEPTIONS · \(n) FLAGGED · \(criticalCount) CRITICAL"
    }

    private func exceptionRow(_ index: Int, _ e: AuditException010) -> some View {
        let sev = (e.severity ?? "info").lowercased()
        let dot: Color = {
            switch sev {
            case "critical": return Brand.danger
            case "warning":  return Brand.warning
            default:         return palette.textTertiary
            }
        }()
        let isSelected = selectedFindings.contains(index)
        let tag = "\((nonEmpty(e.type) ?? "finding").replacingOccurrences(of: "_", with: " ").uppercased()) · \(sev.uppercased())"

        return Button {
            if isSelected { selectedFindings.remove(index) } else { selectedFindings.insert(index) }
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? dot : palette.textTertiary)
                    .padding(.top, 2)
                Circle().fill(dot).frame(width: 10, height: 10).padding(.top, 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tag)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(dot)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    // The server's own message, verbatim — never re-worded.
                    Text(nonEmpty(e.message) ?? "Exception reported without a message")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(exceptionDetail(index, e))
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s2)
                Text(exceptionAmount(e))
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(exceptionAmountColor(e, dot: dot))
                    .padding(.top, 2)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Expected/actual off the server plus the exact reference this finding will
    /// be filed under. No invented copy.
    private func exceptionDetail(_ index: Int, _ e: AuditException010) -> String {
        var parts: [String] = []
        if let ex = e.expected, let ac = e.actual {
            parts.append("\(money(ex)) -> \(money(ac))")
        }
        parts.append("files as \(findingRef(index))")
        return parts.joined(separator: " · ")
    }

    private func exceptionAmount(_ e: AuditException010) -> String {
        if let v = e.variance { return signedMoney(v) }
        if let a = e.actual { return money(a) }
        return (e.severity ?? "review").lowercased() == "info" ? "review" : "flagged"
    }

    private func exceptionAmountColor(_ e: AuditException010, dot: Color) -> Color {
        guard let v = e.variance else { return palette.textSecondary }
        if v > 0 { return dot }
        if v < 0 { return Brand.success }
        return palette.textPrimary
    }

    private func toggleSelectAll() {
        if selectedFindings.count == exceptions.count { selectedFindings.removeAll() }
        else { selectedFindings = Set(0..<exceptions.count) }
    }

    // MARK: - Selected-variance strip

    private var flaggedVarianceStrip: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SELECTED OVERCHARGE VARIANCE")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Text(selectedStripSub)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            Text(money(selectedOverchargeSum))
                .font(.system(size: 20, weight: .bold)).monospacedDigit()
                .foregroundStyle(selectedOverchargeSum > 0 ? Brand.success : palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.success.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.success.opacity(0.28)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var selectedStripSub: String {
        let n = selectedFindings.count
        return "Arithmetic sum of the positive variances the audit returned on the \(n) finding\(n == 1 ? "" : "s") you selected. Not a settled recovery figure - no recoverable total is computed anywhere."
    }

    // MARK: - ESANG readout row (server verdict + the server's own top message)

    private var readoutRow: some View {
        HStack(spacing: Space.s3) {
            Circle()
                .fill(LinearGradient.diagonal)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(readoutHeadline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(readoutSub)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var readoutHeadline: String {
        let n = exceptions.count
        switch auditStatus {
        case "failed":
            return "ESANG: audit failed on \(criticalCount) critical finding\(criticalCount == 1 ? "" : "s")"
        case "flagged":
            return "ESANG: audit flagged \(n) finding\(n == 1 ? "" : "s")"
        case "passed":
            return "ESANG: audit passed - no exception raised"
        default:
            return "ESANG: audit readout"
        }
    }

    private var readoutSub: String {
        if let top = exceptions.first(where: { ($0.severity ?? "").lowercased() == "critical" })
            ?? exceptions.first, let msg = nonEmpty(top.message) {
            return msg
        }
        return "Every figure above comes from the audit engine itself: it files no audit entry and announces nothing."
    }

    // MARK: - Capture deck (the invoice side — user input, the only source)

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { showCapture.toggle() }
            } label: {
                HStack {
                    Text(result == nil ? "CAPTURE THE BILL" : "CAPTURED BILL · \(completeLines.count) LINE\(completeLines.count == 1 ? "" : "S")")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Image(systemName: showCapture ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showCapture {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("Rail invoices are not filed anywhere in EusoTrip yet, so the billed side of this match is typed off the paper bill in front of you. The contracted side below is read from your own shipment.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    captureField(label: "INVOICE NUMBER",
                                 placeholder: "As printed on the freight bill",
                                 text: $invoiceNumberText,
                                 numeric: false)

                    captureField(label: "SHIPMENT ID (OPTIONAL)",
                                 placeholder: "Links your contracted tariff expectation",
                                 text: $shipmentIdText,
                                 numeric: true,
                                 onSubmit: { Task { await load() } })

                    tariffExpectationCard
                    lineEditor

                    if let reason = runBlockReason {
                        blockedNote(reason)
                    }

                    CTAButton(
                        title: auditing ? "Running audit…" : "Run audit",
                        action: { Task { await runAudit() } },
                        leadingIcon: "doc.text.magnifyingglass",
                        isLoading: auditing
                    )
                    .opacity(canRunAudit ? 1 : 0.45)
                    .disabled(!canRunAudit)

                    if let err = auditError {
                        Text(err)
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func captureField(label: String,
                              placeholder: String,
                              text: Binding<String>,
                              numeric: Bool,
                              onSubmit: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            TextField(placeholder, text: text)
                .keyboardType(numeric ? .numbersAndPunctuation : .default)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.characters)
                .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .submitLabel(.done)
                .onSubmit { onSubmit?() }
                .padding(Space.s3)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: Tariff expectation (contract side — server truth + declared gaps)

    private var tariffExpectationCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("TARIFF EXPECTATION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            expectationRow(
                title: "Contracted linehaul",
                value: contractLinehaul.map { money($0) } ?? (linkedShipmentId == nil ? "link a shipment" : "no contracted rate"),
                source: contractLinehaulIsDerived
                    ? "Tariff lookup · rate per car x \(head?.numberOfCars ?? 0) cars"
                    : "Settlement of record · contracted rate",
                live: contractLinehaul != nil
            )
            expectationRow(
                title: "Accrued demurrage",
                value: contractDemurrage.map { money($0) } ?? (linkedShipmentId == nil ? "link a shipment" : "none accrued"),
                source: "Settlement of record · accrued demurrage total",
                live: contractDemurrage != nil
            )
            expectationRow(
                title: "Governing tariff rate",
                value: tariffRateValue,
                source: "Tariff lookup · rate per car / rate per ton",
                live: tariff?.baseRate != nil
            )
            expectationRow(
                title: "Tariff fuel surcharge",
                value: nonEmpty(tariff?.fscBasis) ?? (tariff == nil ? "not looked up" : "not on this tariff"),
                source: "Tariff lookup · fuel surcharge",
                live: serverFscPercent != nil
            )

            Text(fscExplainer)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.s2) {
                smallField(label: "EXPECTED FSC",
                           placeholder: derivedExpectedFsc.map { money($0) } ?? "amount",
                           text: $expectedFscText)
                smallField(label: "TARIFF FSC %",
                           placeholder: serverFscPercent.map { trimNumber010($0) } ?? "percent",
                           text: $fscPercentText)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var tariffRateValue: String {
        guard let r = tariff?.baseRate else {
            return linkedShipmentId == nil ? "link a shipment" : "no governing tariff"
        }
        let unit = (tariff?.rateType ?? "").replacingOccurrences(of: "_", with: " ")
        return unit.isEmpty ? money(r) : "\(money(r)) \(unit)"
    }

    /// Says exactly where the expected fuel-surcharge figure comes from — the
    /// contract percent, the arithmetic, or nothing at all.
    private var fscExplainer: String {
        if let pct = fscPercent, let lh = contractLinehaul, let fsc = derivedExpectedFsc {
            let src = parseMoney(fscPercentText) != nil ? "your entry" : "the contract"
            return "Expected FSC = \(trimNumber010(pct))% (\(src)) x \(money(lh)) contracted linehaul = \(money(fsc)). No rail FSC index feed exists, so this is contract arithmetic - override either figure for the period the bill covers."
        }
        if serverFscPercent == nil {
            return "The governing tariff carries no fuel-surcharge percent. Enter your own so the engine can check the fuel line; leave both blank and the fuel check is simply not run."
        }
        return "A contracted linehaul is needed before the expected fuel surcharge can be computed from the tariff percent. Enter the amount directly if you have it."
    }

    private func expectationRow(title: String, value: String, source: String, live: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(source)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: Space.s2)
            Text(value)
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(live ? palette.textPrimary : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func smallField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .padding(Space.s2)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Line editor (billed side)

    private var lineEditor: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("BILLED CHARGE LINES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(completeLines.count) of \(lines.count) ready")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }

            Text("The duplicate check keys on the line reference - type it exactly as the bill prints it, or a line billed twice will not be caught.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach($lines) { line in
                lineRow(line)
            }

            Button {
                lines.append(DraftLine010())
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 12, weight: .heavy))
                    Text("Add charge line").font(.system(size: 12, weight: .heavy))
                }
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(palette.bgCardSoft))
                .overlay(Capsule().strokeBorder(palette.borderFaint))
            }
            .buttonStyle(.plain)
        }
    }

    private func lineRow(_ line: Binding<DraftLine010>) -> some View {
        // Read the row's value ONCE while the body is being built. The delete
        // button closes over the captured id rather than re-reading
        // `line.wrappedValue` after the array has already been mutated — that
        // re-read is the classic out-of-range crash on a bound ForEach.
        let row = line.wrappedValue
        let rowId = row.id
        let selectedType = row.chargeType
        let rowIsComplete = row.isComplete

        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                TextField("Line ref", text: line.lineRef)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.characters)
                    .font(.system(size: 13, weight: .bold)).monospaced()
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 92)
                TextField("Amount", text: line.amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                if lines.count > 1 {
                    Button {
                        lines.removeAll { $0.id == rowId }
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Brand.danger)
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ChargeType010.allCases) { ct in
                        let on = selectedType == ct
                        Button {
                            line.chargeType.wrappedValue = ct
                        } label: {
                            Text(ct.label)
                                .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                                .foregroundStyle(on ? ct.tint : palette.textSecondary)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(on ? ct.tint.opacity(0.18) : palette.tintNeutral))
                                .overlay(Capsule().strokeBorder(on ? ct.tint.opacity(0.5) : Color.clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(rowIsComplete ? palette.borderFaint : Brand.warning.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Audit history (the note on record, verbatim)

    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("AUDIT HISTORY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("Recent audits · total \(history?.total ?? 0)")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            LifecycleCard {
                if let rows = history?.audits, !rows.isEmpty {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(nonEmpty(r.invoiceNumber) ?? "Invoice")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(signedMoney(r.varianceTotal))
                                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                } else {
                    // The server's own `note`, rendered verbatim. No history list
                    // is drawn because the server holds none to draw.
                    Text(nonEmpty(history?.note) ?? (loading ? "Loading audit history…" : "Audit history is unavailable."))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Currency / tax regime band (country is content)

    private var regimeBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("CURRENCY · TAX REGIME")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                Text(regimeProvenance)
                    .font(EType.mono(.micro))
                    .foregroundStyle(currencyIsAsserted ? Brand.warning : palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            HStack(spacing: Space.s2) {
                ForEach(regimeFacets010) { f in
                    regimePill(f, active: countryCode?.uppercased() == f.id)
                }
            }
            Text(regimeFootnote)
                .font(EType.caption)
                .foregroundStyle(currencyIsAsserted ? Brand.warning : palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func regimePill(_ f: RegimeFacet010, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(f.id) · \(f.currency)")
                .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? palette.textOnGradient : palette.textPrimary)
            Text(f.taxLine)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(active ? palette.textOnGradient.opacity(0.9) : palette.textTertiary)
            Text(f.regulator)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(active ? palette.textOnGradient.opacity(0.85) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(
            Group {
                if active { LinearGradient.primary } else { palette.bgCard }
            }
        )
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(active ? Color.clear : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var regimeProvenance: String {
        guard let c = countryCode else { return "no yard country" }
        return "yard country \(c.uppercased())"
    }

    private var regimeFootnote: String {
        if currencyIsAsserted {
            return "Settlement reports \(currencyCode) on every shipment even though this one's yard is in \(countryCode?.uppercased() ?? "-"). The figures above carry the code that actually came back, never one derived here. The audit engine itself carries no currency at all."
        }
        if countryCode == nil {
            return "Link a shipment to resolve the regime from its real yard country. Tax lines are regulatory reference - no rate is published for them."
        }
        return "Regime resolved from the shipment's real yard country. Tax lines are regulatory reference - no rate is published for them, and the audit engine carries no currency of its own."
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let reason = recoveryBlockReason { blockedNote(reason) }
            HStack(spacing: Space.s2) {
                CTAButton(
                    title: filing ? "Filing…" : "File recovery",
                    action: { showRecoveryGate = true },
                    leadingIcon: "flag.fill",
                    isLoading: filing
                )
                .opacity(canFileRecovery ? 1 : 0.45)
                .disabled(!canFileRecovery)

                Button {
                    showHistorySheet = true
                } label: {
                    Text("Recent audits")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.72)
                        .frame(width: 148, height: 52)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Confirm gate (money · ONLINE_ONLY)

    private var recoveryGateSheet: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("FILE RECOVERY · OPENS A DISPUTE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Brand.danger)
                Text("File \(selectedFindings.count) finding\(selectedFindings.count == 1 ? "" : "s") on \(invoiceNumberTrimmed)")
                    .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("This writes a real dispute row (reason 'rate') plus its opening thread event, and it shows up in the shared dispute queues immediately. The railroad counterparty is left unassigned because no platform account is resolvable from a bare invoice reference. No amount is claimed on the dispute - the findings carry line references, not a settled sum.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("No immutable audit-trail row is written and no socket event is broadcast: railFreightAudit imports neither. Nothing on this screen claims otherwise.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("FILED REFERENCES")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(selectedFindingRefs.isEmpty ? "(all flagged lines)" : selectedFindingRefs.joined(separator: ", "))
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let err = recoveryError {
                    Text(err)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CTAButton(
                    title: filing ? "Filing…" : (reach.isOnline ? "File the recovery" : "Offline - can't file"),
                    action: { Task { await fileRecovery() } },
                    isLoading: filing
                )
                .opacity(canFileRecovery ? 1 : 0.5)
                .disabled(!canFileRecovery)

                Spacer(minLength: 0)
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.large])
    }

    // MARK: - Recent-audits sheet

    private var historySheet: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("RECENT AUDITS · FREIGHT BILL AUDIT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text("Audit history")
                    .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                    .foregroundStyle(palette.textPrimary)

                HStack {
                    Text("total")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(history?.total ?? 0)")
                        .font(.system(size: 15, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(Space.s3)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTE ON RECORD · VERBATIM")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(nonEmpty(history?.note) ?? "No note was recorded.")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                Text("Audit history is not kept yet. Every audit you run here is calculated and then discarded — nothing is filed, so there is no history to show. Showing an invented list would be a lie about your own records.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    // MARK: - Degraded-state drawing (honesty law)

    private var cacheAgeLine: String? {
        guard let synced = lastSyncedAt else { return nil }
        let age = Date().timeIntervalSince(synced)
        guard age > Self.cacheTTL else { return nil }
        return "Contract figures are \(Int(age / 60))m old - pull down to re-read them."
    }

    private func staleNote(_ text: String, danger: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: danger ? "wifi.exclamationmark" : "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(danger ? Brand.danger : Brand.warning)
            Text(text)
                .font(EType.mono(.micro))
                .foregroundStyle(danger ? Brand.danger : Brand.warning)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func blockedNote(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: reach.isOnline ? "exclamationmark.circle" : "wifi.slash")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Brand.warning)
            Text(reason)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var toastView: some View {
        Group {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Brand.success))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func showToast(_ msg: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = msg }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
    }

    // MARK: - Formatting

    private func money(_ v: Double?) -> String {
        guard let v else { return "-" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        // Whole figures read clean; cents are never silently rounded away on a
        // money surface. Both bounds are set — a currency formatter defaults its
        // MINIMUM to 2, which would fight a 0 maximum.
        let digits = (v == v.rounded()) ? 0 : 2
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? "\(currencyCode) \(v)"
    }

    private func signedMoney(_ v: Double?) -> String {
        guard let v else { return "-" }
        if v > 0 { return "+\(money(v))" }
        if v < 0 { return "-\(money(abs(v)))" }
        return money(0)
    }

    private func parseMoney(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let v = Double(cleaned), v.isFinite else { return nil }
        return v
    }

    private func nonEmpty(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    // MARK: - Load (parallel fan-out · READ_CACHED 15m)
    //
    // The history note is always read. The two contract reads only fire when a
    // shipment is linked. Each section degrades alone AND SAYS SO:
    //   · head + settlement — `loadError` fires only when BOTH come back nil,
    //     because either one alone still carries the expectation the audit needs.
    //   · tariff  — sets `tariffDegraded`, surfaced above the capture form.
    //   · history — sets `historyDegraded`, likewise.
    // Nothing here is swallowed silently; a failed read is always visibly
    // distinct from a genuinely empty one.

    private func load(forcedShipmentId: Int? = nil) async {
        loading = true
        loadError = nil
        tariffDegraded = false
        historyDegraded = false

        async let historyTask: RecentAudits010? = EusoTripAPI.shared.query(
            "railFreightAudit.recentAudits", input: RecentAuditsIn010(limit: 20))

        var reached = false

        if let sid = forcedShipmentId ?? linkedShipmentId {
            async let headTask: RailShipmentHead010? = EusoTripAPI.shared.query(
                "railShipments.getRailShipmentDetail", input: ShipmentDetailIn010(id: sid))
            async let settleTask: RailSettlement010? = EusoTripAPI.shared.query(
                "railShipments.getRailSettlement", input: ShipmentIdIn010(shipmentId: sid))

            let h = (try? await headTask) ?? nil
            let s = (try? await settleTask) ?? nil
            if h != nil { head = h; reached = true }
            if s != nil { settlement = s; reached = true }
            if h == nil && s == nil {
                loadError = "Shipment \(sid) returned nothing - it may not exist, or it is not on your account. The audit can still run without a tariff expectation."
            }

            // Wave 2 — the governing tariff. It can only be asked for once the
            // shipment REFERENCE is known: railTariff.lookup's `invoiceId` param
            // is matched against rail_shipments.shipmentNumber then
            // .waybillNumber (railTariff.ts:50-51), so a freight-bill number
            // would silently return all-nulls. Degrades alone — but the failure
            // is flagged, not swallowed: without the tariff the audit runs with
            // no expected linehaul or demurrage, and the user is told that.
            if let ref = nonEmpty(h?.shipmentNumber) ?? nonEmpty(s?.shipmentNumber) {
                // do/catch, not `try?` — a THROW and a legitimately null tariff
                // are different facts and only the throw may claim "did not
                // answer". Collapsing them would trade one false statement for
                // another.
                do {
                    let t: RailTariff010? = try await EusoTripAPI.shared.query(
                        "railTariff.lookup", input: TariffLookupIn010(invoiceId: ref))
                    tariff = t
                    reached = true
                } catch {
                    tariffDegraded = true
                }
            } else {
                tariff = nil
            }
        } else {
            head = nil
            settlement = nil
            tariff = nil
        }

        // Same rule for the history strip: only a throw sets the degraded flag.
        do {
            let hist = try await historyTask
            if hist != nil { history = hist }
            reached = true
        } catch {
            historyDegraded = true
        }

        if reached { lastSyncedAt = Date() }
        loading = false
    }

    // MARK: - Run the audit (MUTATION · railFreightAudit.ts:44)

    private func runAudit() async {
        guard canRunAudit else { return }
        auditing = true
        auditError = nil

        let ctx = tariffContextIn
        let input = AuditInvoiceIn010(
            invoiceNumber: invoiceNumberTrimmed,
            shipmentId: linkedShipmentId,
            lineItems: completeLines.compactMap { l in
                guard let amt = l.amount else { return nil }
                return AuditLineIn010(lineId: l.refTrimmed,
                                      chargeType: l.chargeType.rawValue,
                                      amount: amt)
            },
            tariffContext: ctx.isEmpty ? nil : ctx
        )

        do {
            // `.mutation` server-side even though it is read-only pure compute.
            // query() would issue a GET and the server has no method override —
            // that mistake is the S4 dead-CTA class this lane exists to kill.
            let out: AuditResult010 = try await EusoTripAPI.shared.mutation(
                "railFreightAudit.auditInvoice", input: input)
            result = out
            selectedFindings = Set(0..<(out.exceptions?.count ?? 0))
            withAnimation(.easeOut(duration: 0.18)) { showCapture = false }
        } catch {
            auditError = auditErrorCopy(error, attempt: "run this audit")
        }
        auditing = false
    }

    /// Operator-language copy for a failed freight-bill audit request.
    ///
    /// A raw `NSError` string ("EusoTripAPIError error 5") tells a billing
    /// clerk nothing they can act on, so every failure class is mapped to a
    /// sentence that names what did not happen and what to do next. Refusal
    /// reasons that already carry human copy are surfaced verbatim.
    private func auditErrorCopy(_ error: Error, attempt: String) -> String {
        guard let api = error as? EusoTripAPIError else {
            if (error as NSError).domain == NSURLErrorDomain {
                return "No connection, so EusoTrip couldn't \(attempt). Check your signal, then try again."
            }
            return "Couldn't \(attempt). Try again in a moment."
        }
        switch api {
        case .unauthenticated:
            return "Your session expired before EusoTrip could \(attempt). Sign in again, then retry."
        case .forbidden(let reason):
            return reason
        case .trpcError(let reason):
            return reason
        case .httpStatus(let code, _):
            return "Freight-bill audit is unavailable right now (\(code)), so EusoTrip couldn't \(attempt). Try again in a moment."
        case .decodingFailed:
            return "The audit came back in a form this app version can't read. Update the app, then retry."
        case .empty:
            return "Nothing came back, so EusoTrip couldn't \(attempt). Try again in a moment."
        case .notConfigured, .badURL:
            return "Freight-bill audit isn't reachable from this build. Restart the app, then try again."
        case .queuedForOfflineReplay:
            return "You're offline — a recovery filing is never held for later. Nothing was filed."
        }
    }

    // MARK: - File the recovery (MUTATION · railFreightAudit.ts:127 · ONLINE_ONLY)

    private func fileRecovery() async {
        guard canFileRecovery else { return }
        filing = true
        recoveryError = nil

        let refs = selectedFindingRefs
        do {
            let out: FileRecoveryOut010 = try await EusoTripAPI.shared.mutation(
                "railFreightAudit.fileRecovery",
                input: FileRecoveryIn010(invoiceId: invoiceNumberTrimmed, findingIds: refs))
            showRecoveryGate = false
            let n = out.findingCount ?? refs.count
            if let d = nonEmpty(out.disputeId) {
                showToast("Recovery filed - dispute \(d) - \(n) finding\(n == 1 ? "" : "s")")
            } else {
                showToast("Recovery filed - no dispute number came back")
            }
            await load()
        } catch {
            recoveryError = auditErrorCopy(error, attempt: "file this recovery")
        }
        filing = false
    }
}

// MARK: - Previews

#Preview("010 · Rail Freight Bill Audit · Night") {
    RailFreightBillAudit_010(theme: Theme.dark, shipmentId: 0)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("010 · Rail Freight Bill Audit · Light") {
    RailFreightBillAudit_010(theme: Theme.light, shipmentId: 0)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
