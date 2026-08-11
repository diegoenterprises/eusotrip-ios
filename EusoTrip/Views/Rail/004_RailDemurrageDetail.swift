//
//  004_RailDemurrageDetail.swift
//  EusoTrip — Rail · Shipper · Demurrage Detail (brick 004).
//
//  PURPOSE. One rail shipment's free-time clock and the money it is about to
//  cost. The shipper sees how much free time is left on the placed car, what
//  the charge is right now, what it becomes if the car is still sitting
//  tomorrow, what a three-day hold totals, and can file a dispute against the
//  charge without leaving the screen.
//
//  Verbatim port of 05 Rail/Light-SVG/004 Rail Demurrage Detail.svg (Light + Dark).
//  Composition mirrored block-for-block: back-chevron + breadcrumb + money-style
//  title → hero free-time meter card (burndown bar + now-marker + hours figure)
//  → accrual-schedule ledger card (segmented ramp + four money lines) →
//  projected-total strip → ESang early-release advisory → dispute-window card →
//  tri-country free-time regime band → CTA pair → shipper BottomNav.
//
//  ARCHETYPE = MONEY. This is a burndown + line-item ledger + currency screen,
//  NOT a hero-card→3-KPI→list stamp. The hero is a clock burning down toward a
//  charge; underneath it is a ledger whose right rail is money; underneath that
//  is a TOTAL strip. Every figure carries a currency and a tabular numeral.
//
//  WIRING MANIFEST (re-confirmed first-hand in the real files this fire):
//    EXISTS · railShipments.ts:1452       (query)    railShipments.getRailDemurrage
//               in {shipmentId:number} · out raw rail_demurrage[] rows,
//               tenant-gated by ownsRailShipmentRow (non-owner → []).
//               → the charge the whole screen is about (placedAt / releasedAt /
//                 freeTimeHours / chargeableHours / ratePerHour / totalCharge /
//                 status / railcarId / yardId).
//    EXISTS · railShipments.ts:412        (query)    railShipments.getRailShipmentDetail
//               in {id:number} · out shipment spread + originYard/destinationYard
//               + events[] + waybills[] + demurrage[].
//               → route breadcrumb, car mark, commodity/UN, interchange mark,
//                 numberOfCars (the real railcarCount), yard names, country.
//    EXISTS · railDemurrageAuto.ts:150    (query)    railDemurrageAuto.calculateAccrual
//               in {placementTime, releaseTime?, country:"US"|"CA"|"MX",
//                   railcarCount, freeTimeHoursOverride?, ratePerHourOverride?}
//               out {dwellHours, freeTimeHours, chargeableHours, ratePerHour,
//                    railcarCount, totalCharge, status}.  Pure compute, no DB.
//               → EVERY dollar and every hour band on this screen. Called five
//                 times off ONE real placedAt: US / CA / MX (the regime band and
//                 the live figure) + a now+24h horizon + a placement+72h horizon.
//               → the free-time and rate constants live at railDemurrageAuto.ts:16-17
//                 (FREE_TIME_HOURS {US:48, CA:48, MX:24} · RATE_PER_HOUR
//                 {US:35, CA:35, MX:40}). This file hardcodes NEITHER — it reads
//                 them back off the procedure that owns them.
//    EXISTS · railShipments.ts:1816       (query)    railShipments.getLiveDemurrage
//               no input · out {railRef, headline, action, savings} | null.
//               → the ESang advisory line. NOT shipment-scoped (it returns the
//                 caller's single worst accruing charge), so it is only shown
//                 when railRef matches THIS shipment's number; otherwise the row
//                 falls back to a line derived from this shipment's own quote.
//    EXISTS · railDemurrageAuto.ts:264    (MUTATION) railDemurrageAuto.createDispute
//               in {confirm: literal(true), demurrageId, reason:
//                   "service_failure"|"weather"|"customer_error"|"data_error"|"other",
//                   notes?<=2000, requestedWaiverAmount?}
//               out {disputeId:"DSP-<n>", status:"submitted", reason,
//                    requestedWaiver, submittedBy}.
//               Flips the charge to 'disputed' and writes a blockchainAuditTrail
//               'rail.demurrage_disputed' entry at railDemurrageAuto.ts:305.
//               Goes through mutation() = POST. There is NO server method
//               override — sending this as a query() would be a dead CTA.
//               `confirm: true` is a zod LITERAL: omit it and the call 400s.
//
//    STUB · named-gap · railShipments.requestEarlyRelease — ABSENT. There is no
//               backing procedure anywhere in server/. The SVG's primary CTA is
//               therefore drawn in a truthful unavailable state (locked ribbon,
//               no tap target) with the reason spelled out on screen and the
//               live numbers behind it reachable through the house
//               RailSecondaryActionButton context sheet. Nothing is queued and
//               nothing is faked. Proposed contract is in the fire report.
//    STUB · named-gap · rail_demurrage has NO dispute-window column, so the SVG's
//               "30d left" pill cannot be honored. The pill instead carries the
//               real elapsed hold. The only real dispute gates the server
//               enforces are: ownership, status not in (paid, waived), and no
//               dispute already open — all three are drawn.
//    STUB · named-gap · rail_demurrage has NO tariff-tier table and NO currency
//               column. The SVG's "BNSF Tariff 6004-C · $250/$400/$650 per day"
//               ladder does not exist in the data model — the real engine is a
//               FLAT ratePerHour. The ledger keeps the SVG's four-step ramp
//               grammar but every step is a real calculateAccrual horizon, and
//               the tariff caption is replaced by the real rate + the country's
//               regulator. Currency is derived from the yard's real country enum.
//    NO SOCKET · WS_EVENTS.DEMURRAGE_TICK does not exist (grepped the whole web
//               repo: zero hits). The clock cannot be socket-driven. It runs on
//               THIS DEVICE off the real placedAt via TimelineView and says so in
//               plain words on the card; money never moves without a re-poll.
//
//  RBAC. Reads: railProcedure = requireUser + requireRailMode (_core/trpc.ts:267)
//  plus the row-level ownsRailShipmentRow tenant gate on getRailDemurrage /
//  getRailShipmentDetail — a non-owner gets [] / null, never another tenant's
//  money. calculateAccrual + createDispute are protectedProcedure; createDispute
//  additionally re-joins rail_shipments on companyId before it will touch the
//  charge (railDemurrageAuto.ts:274-280).
//
//  transportMode = rail. COUNTRY IS CONTENT, NOT A FILE FORK: one screen reads
//  the yard's real `country` enum (US | CA | MX) and swings free time, rate,
//  currency and regulator with it — US/CA 48h free at the US/CA rate in USD/CAD
//  under STB · FRA / Transport Canada, MX 24h free at the MX rate in MXN under
//  ARTF · SICT. Free time and rate are never typed here; they come back off
//  calculateAccrual, which owns the constants.
//
//  OFFLINE POLICY (Encyclopedia v2): READ_CACHED(5m) for the accrual board — a
//  demurrage clock moves by the hour, so the last good serve stays on screen and
//  always stamps its own age (amber past 5 minutes) instead of blanking; dispute
//  submission is ONLINE_ONLY (it moves money) — the CTA disables with an explicit
//  reason rather than queueing.
//
//  PRODUCTIVITY. It shows the rail shipper exactly how many hours of free time
//  are left on a placed car and what the next hour costs, so the car gets pulled
//  before the clock trips instead of after the invoice arrives.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Money parse boundary
//
// rail_demurrage.ratePerHour / totalCharge are MySQL `decimal` → the driver
// serializes them as JSON STRINGS ("35.00"). A future server change to emit
// numbers must not silently blank a money line, so both decode through this
// string-OR-number box (the same boundary 002 uses on rail_shipments.rate).

private struct FlexMoney004: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = Double(s) }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let i = try? c.decode(Int.self) { value = Double(i) }
        else { value = nil }
    }
}

// MARK: - Decoded server shapes

/// One `rail_demurrage` row exactly as `railShipments.getRailDemurrage` returns
/// it (`db.select().from(railDemurrage)` = every column, no join). Column set
/// verified against drizzle/schema.ts:11366.
private struct RailDemurrageRow004: Decodable, Identifiable {
    let id: Int
    let shipmentId: Int?
    let railcarId: Int?
    let yardId: Int?
    let placedAt: String?
    let releasedAt: String?
    let freeTimeHours: Int?
    let chargeableHours: Int?
    let ratePerHour: FlexMoney004?
    let totalCharge: FlexMoney004?
    let status: String?
    let createdAt: String?

    /// Still on the clock — no release scan has landed.
    var isOpen: Bool { (releasedAt ?? "").isEmpty }
    /// The server refuses a dispute on a paid or waived charge
    /// (railDemurrageAuto.ts:281). Mirrored here so the CTA never lies.
    var isTerminal: Bool {
        let s = (status ?? "").lowercased()
        return s == "paid" || s == "waived"
    }
    var isDisputed: Bool { (status ?? "").lowercased() == "disputed" }
}

/// `rail_yards` row nested by getRailShipmentDetail. `country` is the real
/// mysqlEnum ["US","CA","MX"] (drizzle/schema.ts:11148) — the single source of
/// the country swing on this screen.
private struct RailYardNode004: Decodable {
    let id: Int?
    let name: String?
    let city: String?
    let state: String?
    let country: String?
    let yardType: String?
}

/// `rail_waybills` row nested by getRailShipmentDetail — the car mark.
private struct RailWaybillNode004: Decodable, Identifiable {
    let id: Int
    let waybillNumber: String?
    let railcarNumber: String?
    let commodity: String?
}

/// The slice of `railShipments.getRailShipmentDetail` this screen reads. Every
/// field optional: the procedure returns null for a non-owner, and a partially
/// populated shipment must degrade to honest dashes, never to a fabricated lane.
private struct RailShipmentHead004: Decodable {
    let id: Int?
    let shipmentNumber: String?
    let carType: String?
    let numberOfCars: Int?
    let commodity: String?
    let unNumber: String?
    let hazmatClass: String?
    let status: String?
    let originRailroad: String?
    let destinationRailroad: String?
    let routeDescription: String?
    let transportMode: String?
    let originYard: RailYardNode004?
    let destinationYard: RailYardNode004?
    let waybills: [RailWaybillNode004]?
    let demurrage: [RailDemurrageRow004]?
}

/// `railDemurrageAuto.calculateAccrual` output, field-for-field
/// (railDemurrageAuto.ts:166-177). Pure numbers — no decimal-string boundary
/// needed here because this procedure never touches the DB.
private struct AccrualQuote004: Decodable {
    let placementTime: String?
    let releaseTime: String?
    let country: String?
    let dwellHours: Double?
    let freeTimeHours: Double?
    let chargeableHours: Double?
    let ratePerHour: Double?
    let railcarCount: Int?
    let totalCharge: Double?
    let status: String?
}

/// `railShipments.getLiveDemurrage` output (railShipments.ts:1865-1870).
private struct LiveDemurrageTip004: Decodable {
    let railRef: String?
    let headline: String?
    let action: String?
    let savings: Double?
}

/// `railDemurrageAuto.createDispute` receipt (railDemurrageAuto.ts:323-329).
private struct DisputeReceipt004: Decodable {
    let disputeId: String?
    let status: String?
    let reason: String?
    let requestedWaiver: Double?
    let submittedBy: Int?
}

/// The five reasons the server's zod enum accepts (railDemurrageAuto.ts:267).
/// Raw values are the wire values; labels are the shipper-facing words.
private enum DisputeReason004: String, CaseIterable, Identifiable {
    case serviceFailure = "service_failure"
    case weather        = "weather"
    case customerError  = "customer_error"
    case dataError      = "data_error"
    case other          = "other"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .serviceFailure: return "Carrier service failure"
        case .weather:        return "Weather"
        case .customerError:  return "Customer error"
        case .dataError:      return "Wrong data on the charge"
        case .other:          return "Other"
        }
    }
}

// MARK: - Encoded inputs
//
// Every optional is written with `encodeIfPresent`. The server's zod uses
// `.optional()`, which REJECTS an explicit null — a synthesized encoder that
// emitted `"releaseTime": null` would 400 the call.

private struct ShipmentIdIn004: Encodable { let shipmentId: Int }
private struct ShipmentDetailIn004: Encodable { let id: Int }

private struct AccrualIn004: Encodable {
    let placementTime: String
    let releaseTime: String?
    let country: String
    let railcarCount: Int

    enum CodingKeys: String, CodingKey { case placementTime, releaseTime, country, railcarCount }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(placementTime, forKey: .placementTime)
        try c.encodeIfPresent(releaseTime, forKey: .releaseTime)
        try c.encode(country, forKey: .country)
        try c.encode(railcarCount, forKey: .railcarCount)
    }
}

private struct DisputeIn004: Encodable {
    /// zod `z.literal(true)` — always true, never omitted.
    let confirm: Bool
    let demurrageId: Int
    let reason: String
    let notes: String?
    let requestedWaiverAmount: Double?

    enum CodingKeys: String, CodingKey {
        case confirm, demurrageId, reason, notes, requestedWaiverAmount
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(confirm, forKey: .confirm)
        try c.encode(demurrageId, forKey: .demurrageId)
        try c.encode(reason, forKey: .reason)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(requestedWaiverAmount, forKey: .requestedWaiverAmount)
    }
}

// MARK: - Derived view models (composed from decoded fields — never decoded)

/// One line of the accrual ledger. `amount` is always a real calculateAccrual
/// figure rendered through the country's currency; `weight` is the real hour
/// span the step covers, which is what sizes the segmented ramp above it.
private struct AccrualStep004: Identifiable {
    let id: String
    let label: String
    let detail: String
    let amount: String
    let dot: Color
    let amountTint: Color
    let weight: Double
}

/// One facet of the tri-country free-time regime band. Both lines are built
/// from that country's own calculateAccrual quote.
private struct RegimeFacet004: Identifiable {
    let id: String
    let line1: String
    let line2: String
    let active: Bool
}

// MARK: - Date helpers

/// Tolerant ISO-8601 / MySQL DATETIME parse. `placedAt` arrives as an ISO
/// string; a raw driver DATETIME ("2026-08-10 14:22:05") is accepted too so a
/// serialization change cannot silently kill the clock.
private func parseISO004(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: raw) { return d }
    let f2 = ISO8601DateFormatter()
    f2.formatOptions = [.withInternetDateTime]
    if let d = f2.date(from: raw) { return d }
    let f3 = DateFormatter()
    f3.locale = Locale(identifier: "en_US_POSIX")
    f3.timeZone = TimeZone(identifier: "UTC")
    f3.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f3.date(from: raw)
}

private func isoString004(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.string(from: date)
}

// MARK: - Screen root

struct RailDemurrageDetail_004: View {
    let theme: Theme.Palette
    let shipmentId: Int

    var body: some View {
        Shell(theme: theme) {
            RailDemurrageDetailBody004(shipmentId: shipmentId)
        } nav: {
            // Shipper band, same slot set as 002 Rail Shipment Detail. WALLET is
            // current here because demurrage is a financial surface (the SVG
            // marks it current for the same reason).
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

private struct RailDemurrageDetailBody004: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    let shipmentId: Int

    // Server state
    @State private var charges: [RailDemurrageRow004] = []
    @State private var head: RailShipmentHead004? = nil
    @State private var tip: LiveDemurrageTip004? = nil
    @State private var quoteUS: AccrualQuote004? = nil
    @State private var quoteCA: AccrualQuote004? = nil
    @State private var quoteMX: AccrualQuote004? = nil
    @State private var quoteNext24: AccrualQuote004? = nil
    @State private var quoteHold72: AccrualQuote004? = nil

    // Lifecycle
    @State private var loading = true
    @State private var loadError: String? = nil
    /// READ_CACHED(5m): the last good serve stays on screen and stamps its age.
    @State private var lastSyncedAt: Date? = nil

    // Dispute flow (ONLINE_ONLY)
    @State private var showDispute = false
    @State private var disputeReason: DisputeReason004 = .serviceFailure
    @State private var disputeNotes: String = ""
    @State private var waiverText: String = ""
    @State private var filing = false
    @State private var disputeError: String? = nil
    @State private var toast: String? = nil

    private static let cacheTTL: TimeInterval = 5 * 60   // READ_CACHED(5m)
    private let hold72Hours: Double = 72

    // MARK: Derived — the charge this screen is about

    /// Prefer the car still on the clock; else the largest charge; else the
    /// newest row. Never fabricates one.
    private var activeCharge: RailDemurrageRow004? {
        let pool = charges.isEmpty ? (head?.demurrage ?? []) : charges
        if let open = pool.first(where: { $0.isOpen && !$0.isTerminal }) { return open }
        let ranked = pool.sorted { ($0.totalCharge?.value ?? 0) > ($1.totalCharge?.value ?? 0) }
        return ranked.first ?? pool.last
    }

    private var placedAt: Date? { parseISO004(activeCharge?.placedAt) }
    private var releasedAt: Date? { parseISO004(activeCharge?.releasedAt) }

    /// The country the free-time regime comes from: the destination yard's real
    /// enum, then the origin yard's, then the quote the server echoed back.
    private var countryCode: String {
        let raw = head?.destinationYard?.country
            ?? head?.originYard?.country
            ?? quoteUS?.country
        let code = (raw ?? "US").uppercased()
        return ["US", "CA", "MX"].contains(code) ? code : "US"
    }

    /// Currency of that country. rail_demurrage carries no currency column, so
    /// this is country content — the same way the regulator caption is.
    private var currencyCode: String {
        switch countryCode {
        case "CA": return "CAD"
        case "MX": return "MXN"
        default:   return "USD"
        }
    }

    /// Who writes the free-time rule in that country.
    private var regulatorCaption: String {
        switch countryCode {
        case "CA": return "TRANSPORT CANADA"
        case "MX": return "ARTF · SICT"
        default:   return "STB · FRA"
        }
    }

    /// The live quote = this shipment's country quote (no releaseTime → the
    /// server clocked it against now).
    private var liveQuote: AccrualQuote004? {
        switch countryCode {
        case "CA": return quoteCA
        case "MX": return quoteMX
        default:   return quoteUS
        }
    }

    private var freeHours: Double {
        liveQuote?.freeTimeHours ?? Double(activeCharge?.freeTimeHours ?? 0)
    }
    private var ratePerHour: Double {
        liveQuote?.ratePerHour ?? (activeCharge?.ratePerHour?.value ?? 0)
    }
    private var railcarCount: Int {
        liveQuote?.railcarCount ?? max(1, head?.numberOfCars ?? max(1, charges.count))
    }
    private var accruedNow: Double {
        liveQuote?.totalCharge ?? (activeCharge?.totalCharge?.value ?? 0)
    }
    private var chargeableHours: Double {
        liveQuote?.chargeableHours ?? Double(activeCharge?.chargeableHours ?? 0)
    }

    /// Dwell on THIS DEVICE, off the real placedAt. There is no
    /// WS_EVENTS.DEMURRAGE_TICK to subscribe to — the clock is local and the
    /// card says so. Frozen at the release scan when the car is off the clock.
    private func dwellHours(at now: Date) -> Double {
        guard let placed = placedAt else { return liveQuote?.dwellHours ?? 0 }
        let end = releasedAt ?? now
        return max(0, end.timeIntervalSince(placed) / 3600)
    }

    private func freeRemaining(at now: Date) -> Double {
        max(0, freeHours - dwellHours(at: now))
    }

    private var hasCharge: Bool { activeCharge != nil }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                breadcrumbRow
                moneyTitle
                IridescentHairline()

                if loading && !hasCharge {
                    LifecycleCard {
                        Text("Loading the free-time clock…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError, !hasCharge {
                    LifecycleCard(accentDanger: true) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Couldn't load this shipment's demurrage")
                                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger).lineLimit(3)
                        }
                    }
                } else if !hasCharge {
                    EusoEmptyState(
                        systemImage: "clock.badge.checkmark",
                        title: "No demurrage on this shipment",
                        subtitle: "The clock starts when a car is placed. Charges and the free-time burndown appear here the moment that happens."
                    )
                } else {
                    burndownHero
                    accrualLedger
                    advisoryRow
                    disputeWindowCard
                    regimeBand
                    ctaPair
                    gapNote
                    if let err = loadError { staleNote(err, danger: true) }
                    if let stamp = cacheAgeLine { staleNote(stamp, danger: false) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $showDispute) { disputeSheet }
    }

    // MARK: - TopBar (eyebrow + free-time register)

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · RAIL · DEMURRAGE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text(freeTimeRegister)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(Brand.warning)
        }
    }

    /// "FREE TIME · 48H" — the H comes off calculateAccrual, never typed here.
    private var freeTimeRegister: String {
        guard freeHours > 0 else { return "FREE TIME · —" }
        return "FREE TIME · \(Int(freeHours.rounded()))H"
    }

    // MARK: - Breadcrumb

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
    }

    private var routeTitle: String {
        let o = nonEmpty(head?.originYard?.city) ?? nonEmpty(head?.originYard?.name)
        let d = nonEmpty(head?.destinationYard?.city) ?? nonEmpty(head?.destinationYard?.name)
        if let o, let d { return "\(o) → \(d)" }
        if let r = nonEmpty(head?.routeDescription) { return r }
        return nonEmpty(head?.shipmentNumber) ?? (loading ? "Loading…" : "Rail shipment")
    }

    // MARK: - Money title

    private var moneyTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(money(accruedNow)) chargeable")
                .font(.system(size: 32, weight: .bold)).kerning(-0.6)
                .monospacedDigit()
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(subjectLine)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
        }
    }

    /// "tankcar · <car mark> · UN1203 · <road> interchange · <yard> · RAIL-…" —
    /// every token a real column, nothing typed in.
    private var subjectLine: String {
        var parts: [String] = []
        if let car = nonEmpty(head?.carType) { parts.append(car) }
        if let mark = nonEmpty(head?.waybills?.first?.railcarNumber) { parts.append(mark) }
        if let un = nonEmpty(head?.unNumber) { parts.append("UN\(un)") }
        if let inter = nonEmpty(head?.destinationRailroad) ?? nonEmpty(head?.originRailroad) {
            parts.append("\(inter) interchange")
        }
        if let yard = yardLabel { parts.append(yard) }
        if let num = nonEmpty(head?.shipmentNumber) { parts.append(num) }
        return parts.isEmpty ? (loading ? "Loading…" : "Shipment #\(shipmentId)") : parts.joined(separator: " · ")
    }

    /// The yard the car is sitting in, matched off the charge's real yardId.
    private var yardLabel: String? {
        guard let yid = activeCharge?.yardId else { return nil }
        if head?.destinationYard?.id == yid, let n = nonEmpty(head?.destinationYard?.name) { return n }
        if head?.originYard?.id == yid, let n = nonEmpty(head?.originYard?.name) { return n }
        return "yard #\(yid)"
    }

    // MARK: - Hero free-time burndown (MONEY hero)

    /// TimelineView, not a socket. WS_EVENTS.DEMURRAGE_TICK does not exist, so
    /// the countdown ticks on this device off the real placedAt once a minute.
    /// The money on the card is whatever the server last computed — the card
    /// says so out loud rather than implying a live money feed.
    private var burndownHero: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            heroCard(now: ctx.date)
        }
    }

    private func heroCard(now: Date) -> some View {
        let dwell = dwellHours(at: now)
        let remaining = freeRemaining(at: now)
        let consumed: CGFloat = freeHours > 0 ? CGFloat(min(1.0, dwell / freeHours)) : 1.0

        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(nonEmpty(head?.shipmentNumber) ?? "charge #\(activeCharge?.id ?? 0)")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                Text(statusChipText(dwell: dwell))
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(statusChipColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(statusChipColor.opacity(0.16)))
            }

            burndownBar(consumed: consumed)

            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(remaining > 0 ? "\(Int(remaining.rounded()))h" : fmtHours(chargeableHours))
                    .font(.system(size: 22, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text(remaining > 0
                     ? "free time remaining of \(Int(freeHours.rounded()))h allowed"
                     : "past the \(Int(freeHours.rounded()))h allowance · chargeable")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }

            Text(heroFooter(remaining: remaining))
                .font(.system(size: 11))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Counting on this device from the placement time · pull down to refresh the money")
                .font(.system(size: 9, weight: .semibold)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(LinearGradient(colors: [Brand.hazmat, Brand.warning],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// Free time consumed (green) → free time left (amber wash) with a now-marker
    /// at the boundary, exactly as the SVG draws it.
    private func burndownBar(consumed: CGFloat) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let cut = max(0, min(w, w * consumed))
            ZStack(alignment: .leading) {
                Capsule().fill(palette.bgCardSoft)
                Capsule()
                    .fill(LinearGradient(colors: [Brand.success, Brand.success.opacity(0.72)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: cut)
                Rectangle()
                    .fill(Brand.warning.opacity(0.22))
                    .frame(width: max(0, w - cut))
                    .offset(x: cut)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(palette.textPrimary)
                    .frame(width: 2, height: 16)
                    .offset(x: max(0, cut - 1))
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }

    private func statusChipText(dwell: Double) -> String {
        let s = (activeCharge?.status ?? "accruing").replacingOccurrences(of: "_", with: " ").uppercased()
        return "\(s) · \(Int(dwell.rounded()))H DWELL"
    }

    private var statusChipColor: Color {
        switch (activeCharge?.status ?? "").lowercased() {
        case "paid", "waived": return Brand.success
        case "disputed":       return Brand.info
        case "invoiced":       return Brand.warning
        default:               return Brand.hazmat
        }
    }

    private func heroFooter(remaining: Double) -> String {
        let per = "\(money(ratePerHour))/hr per car"
        if remaining > 0 {
            return "Crosses into demurrage in ~\(Int(remaining.rounded()))h · then \(per)"
        }
        if let placed = placedAt {
            return "Accruing \(per) since \(shortStamp(placed)) · \(railcarCount) car\(railcarCount == 1 ? "" : "s") on the charge"
        }
        return "Accruing \(per) · \(railcarCount) car\(railcarCount == 1 ? "" : "s") on the charge"
    }

    // MARK: - Accrual ledger (the line items)

    private var accrualLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(ledgerCaption)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)

            VStack(alignment: .leading, spacing: 0) {
                stepRamp
                    .padding(.bottom, Space.s3)

                ForEach(Array(accrualSteps.enumerated()), id: \.element.id) { idx, step in
                    ledgerRow(step)
                    if idx < accrualSteps.count - 1 {
                        Divider().overlay(palette.borderFaint)
                    }
                }

                projectedTotalStrip
                    .padding(.top, Space.s3)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// The SVG captioned this "BNSF TARIFF 6004-C". No tariff table exists in the
    /// data model, so the caption carries the real rate and the country's
    /// regulator instead of a tariff number nobody can verify.
    private var ledgerCaption: String {
        guard ratePerHour > 0 else { return "ACCRUAL SCHEDULE · \(regulatorCaption)" }
        return "ACCRUAL SCHEDULE · \(money(ratePerHour))/HR · \(regulatorCaption)"
    }

    /// Four steps, each a real calculateAccrual horizon off ONE real placedAt.
    private var accrualSteps: [AccrualStep004] {
        let cars = railcarCount
        let carWord = "\(cars) car\(cars == 1 ? "" : "s")"
        let freeDays = freeHours > 0 ? Int(ceil(freeHours / 24)) : 0
        let freeLabel = freeDays > 1 ? "Day 1–\(freeDays) · free" : "Day 1 · free"

        let next24Total = quoteNext24?.totalCharge
        let hold72Total = quoteHold72?.totalCharge
        let next24Chargeable = quoteNext24?.chargeableHours ?? chargeableHours
        let hold72Chargeable = quoteHold72?.chargeableHours ?? next24Chargeable

        return [
            AccrualStep004(
                id: "free",
                label: freeLabel,
                detail: "grace · \(Int(freeHours.rounded()))h allowance · \(carWord)",
                amount: money(0),
                dot: Brand.success,
                amountTint: Brand.success,
                weight: max(1, freeHours)),
            AccrualStep004(
                id: "now",
                label: "Chargeable now",
                detail: "\(fmtHours(chargeableHours)) over free time · \(money(ratePerHour))/hr",
                amount: money(accruedNow),
                dot: Brand.hazmat,
                amountTint: accruedNow > 0 ? palette.textPrimary : palette.textSecondary,
                weight: max(0, chargeableHours)),
            AccrualStep004(
                id: "next24",
                label: "Held another 24h",
                detail: next24Total == nil
                    ? "horizon quote unavailable"
                    : "\(fmtHours(next24Chargeable)) chargeable by then",
                amount: next24Total.map { money($0) } ?? "—",
                dot: Brand.warning,
                amountTint: palette.textPrimary,
                weight: max(0, next24Chargeable - chargeableHours)),
            AccrualStep004(
                id: "hold72",
                label: "Held \(Int(hold72Hours / 24)) days",
                detail: hold72Total == nil
                    ? "horizon quote unavailable"
                    : "\(fmtHours(hold72Chargeable)) chargeable · \(carWord)",
                amount: hold72Total.map { money($0) } ?? "—",
                dot: Brand.danger,
                amountTint: Brand.danger,
                weight: max(0, hold72Chargeable - next24Chargeable))
        ]
    }

    /// Segmented ramp sized by the real hour span of each step.
    private var stepRamp: some View {
        let steps = accrualSteps
        let total = max(0.0001, steps.reduce(0.0) { $0 + max(0, $1.weight) })
        return GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(steps) { s in
                    Rectangle()
                        .fill(s.dot)
                        .frame(width: geo.size.width * CGFloat(max(0, s.weight) / total))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
        .background(palette.bgCardSoft)
        .clipShape(Capsule())
    }

    private func ledgerRow(_ step: AccrualStep004) -> some View {
        HStack(spacing: Space.s2) {
            Circle().fill(step.dot).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(step.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Text(step.amount)
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(step.amountTint)
        }
        .padding(.vertical, Space.s2)
    }

    /// The SVG's projected-exposure inset — restated as the ledger TOTAL, which
    /// is what it is. Currency-stamped so a CAD or MXN charge never reads as USD.
    private var projectedTotalStrip: some View {
        HStack(spacing: Space.s2) {
            Text("PROJECTED TOTAL · HELD \(Int(hold72Hours / 24))D · \(railcarCount) CAR")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: Space.s2)
            Text(quoteHold72?.totalCharge.map { money($0) } ?? "—")
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                .foregroundStyle(Brand.danger)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: - ESang advisory

    /// getLiveDemurrage takes NO input — it returns the caller's single worst
    /// accruing charge, which may belong to a different shipment. It is only
    /// echoed here when its railRef matches THIS shipment; otherwise the row
    /// falls back to a line derived from this shipment's own quote.
    private var advisoryRow: some View {
        let matched = tipMatchesThisShipment ? tip : nil
        let headline = matched?.headline ?? derivedAdvisoryHeadline
        let action = matched?.action ?? derivedAdvisoryAction

        return HStack(spacing: Space.s3) {
            Circle()
                .fill(LinearGradient.diagonal)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Text(action)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Space.s2)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var tipMatchesThisShipment: Bool {
        guard let ref = nonEmpty(tip?.railRef), let num = nonEmpty(head?.shipmentNumber) else { return false }
        return ref.caseInsensitiveCompare(num) == .orderedSame
    }

    private var derivedAdvisoryHeadline: String {
        if accruedNow > 0 {
            return "ESang: \(money(accruedNow)) already chargeable on this car"
        }
        return "ESang: still inside free time on this car"
    }

    private var derivedAdvisoryAction: String {
        let remaining = freeRemaining(at: Date())
        if remaining > 0 {
            return "Pull it within \(Int(remaining.rounded()))h and the charge stays at \(money(0))"
        }
        if let projected = quoteHold72?.totalCharge, projected > accruedNow {
            return "Every further day adds toward \(money(projected)) at a \(Int(hold72Hours / 24))-day hold"
        }
        return "Charge is running at \(money(ratePerHour))/hr per car"
    }

    // MARK: - Dispute window

    private var disputeWindowCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("DISPUTE WINDOW")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(disputeTint.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: disputeGlyph)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(disputeTint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(disputeTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(disputeSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s2)
                Text(heldPillText)
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4).monospacedDigit()
                    .foregroundStyle(disputeTint)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(disputeTint.opacity(0.12)))
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// The server enforces exactly three gates on createDispute: ownership,
    /// status not in (paid, waived), and no dispute already open. Those are the
    /// gates drawn here. rail_demurrage carries no dispute-window column, so the
    /// SVG's "30d left" pill shows the real elapsed hold instead.
    private var canDispute: Bool {
        guard let row = activeCharge else { return false }
        return !row.isTerminal && !row.isDisputed
    }

    private var disputeTitle: String {
        guard let row = activeCharge else { return "No charge to dispute" }
        if row.isTerminal { return "Charge is \(row.status ?? "closed")" }
        if row.isDisputed { return "Dispute already filed" }
        return "Dispute available on this charge"
    }

    private var disputeSubtitle: String {
        guard let row = activeCharge else { return "Nothing has accrued on this shipment." }
        if row.isTerminal {
            return "A \(row.status ?? "closed") charge can no longer be disputed."
        }
        if row.isDisputed {
            return "It stays out of billing while it is reviewed. Only one dispute can be open at a time."
        }
        return "A carrier-caused hold is disputable. Filing drops the charge out of billing until it is reviewed."
    }

    private var disputeTint: Color {
        guard let row = activeCharge else { return palette.textTertiary }
        if row.isTerminal { return Brand.success }
        if row.isDisputed { return Brand.warning }
        return Brand.info
    }

    private var disputeGlyph: String {
        guard let row = activeCharge else { return "clock" }
        if row.isTerminal { return "checkmark.seal" }
        if row.isDisputed { return "exclamationmark.bubble" }
        return "clock.arrow.circlepath"
    }

    private var heldPillText: String {
        let dwell = dwellHours(at: Date())
        // Reads in hours while the car is still inside its REAL free-time
        // allowance, then flips to days once it is past it. The threshold is the
        // server's freeTimeHours, not a number chosen here.
        if freeHours > 0 && dwell > freeHours {
            return "\(Int((dwell / 24).rounded()))d held"
        }
        return "\(Int(dwell.rounded()))h held"
    }

    // MARK: - Tri-country regime band (country is content, not a fork)

    private var regimeBand: some View {
        HStack(spacing: Space.s2) {
            ForEach(regimeFacets) { f in
                VStack(alignment: .leading, spacing: 3) {
                    Text(f.line1)
                        .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(f.active ? palette.textOnGradient : palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(f.line2)
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(f.active ? palette.textOnGradient.opacity(0.9) : palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.s3)
                .frame(height: 46)
                .background {
                    if f.active { LinearGradient.primary } else { palette.bgCard }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(f.active ? Color.clear : palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    /// Each facet reads that country's own calculateAccrual quote — the free
    /// time and the rate come back off railDemurrageAuto.ts:16-17, never typed.
    private var regimeFacets: [RegimeFacet004] {
        [
            regimeFacet(code: "US", quote: quoteUS, currency: "USD"),
            regimeFacet(code: "CA", quote: quoteCA, currency: "CAD"),
            regimeFacet(code: "MX", quote: quoteMX, currency: "MXN")
        ]
    }

    private func regimeFacet(code: String, quote: AccrualQuote004?, currency: String) -> RegimeFacet004 {
        let free = quote?.freeTimeHours
        let rate = quote?.ratePerHour
        return RegimeFacet004(
            id: code,
            line1: free.map { "\(code) · \(Int($0.rounded()))h free" } ?? "\(code) · —",
            line2: rate.map { "$\(trimNumber($0))/hr · \(currency)" } ?? "rate pending",
            active: code == countryCode)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            earlyReleaseRibbon
            disputeButton
        }
    }

    /// NAMED GAP — railShipments.requestEarlyRelease does not exist. The ribbon
    /// keeps the SVG's shape and position but is drawn locked, carries no tap
    /// target, and states its own unavailability to VoiceOver. Nothing queues.
    private var earlyReleaseRibbon: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .bold))
            Text("Request early release")
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.72)
        }
        .foregroundStyle(palette.textOnGradient)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(LinearGradient.primary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .opacity(0.42)
        .saturation(0.35)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Request early release")
        .accessibilityValue("Unavailable — no backing procedure has shipped")
    }

    /// The only money-moving control on the screen. ONLINE_ONLY: it never
    /// queues, and it says which of the two reasons is blocking it.
    private var disputeButton: some View {
        Button {
            disputeError = nil
            waiverText = accruedNow > 0 ? trimNumber(accruedNow) : ""
            disputeNotes = ""
            disputeReason = .serviceFailure
            showDispute = true
        } label: {
            Text("Dispute")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 132, height: 48)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canDispute || !reach.isOnline)
        .opacity((canDispute && reach.isOnline) ? 1 : 0.45)
    }

    /// The named gap plus the online-only refusal, both in plain words, with the
    /// live numbers behind the early-release CTA reachable through the house
    /// Rail context sheet.
    private var gapNote: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s2) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Brand.warning)
                Text(gapNoteText)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            RailSecondaryActionButton(
                title: "Early-release context",
                sheetTitle: "Early release · what this screen knows",
                lines: earlyReleaseContextLines,
                fillWidth: true,
                systemImage: "arrow.up.right.circle"
            )
        }
    }

    private var gapNoteText: String {
        var lines = ["Early release is unavailable here: no backing procedure has shipped yet, so nothing was requested and nothing was queued."]
        if !reach.isOnline {
            lines.append("Offline — a demurrage dispute moves money and never queues. Reconnect to file it live.")
        } else if !canDispute, let row = activeCharge {
            if row.isDisputed {
                lines.append("Dispute is closed off because one is already open on this charge.")
            } else if row.isTerminal {
                lines.append("Dispute is closed off because the charge is \(row.status ?? "closed").")
            }
        }
        return lines.joined(separator: " ")
    }

    /// Everything real the screen holds about the release decision, so the
    /// context sheet is useful even though the write path does not exist.
    private var earlyReleaseContextLines: [String] {
        var lines: [String] = []
        if let num = nonEmpty(head?.shipmentNumber) { lines.append("Shipment \(num)") }
        if let yard = yardLabel { lines.append("Car sitting at \(yard)") }
        if let placed = placedAt { lines.append("Placed \(shortStamp(placed)) · \(fmtHours(dwellHours(at: Date()))) dwell") }
        lines.append("\(Int(freeHours.rounded()))h free time · \(money(ratePerHour))/hr after · \(railcarCount) car\(railcarCount == 1 ? "" : "s")")
        lines.append("Chargeable now \(money(accruedNow)) \(currencyCode)")
        if let n = quoteNext24?.totalCharge { lines.append("Another 24h on the ground: \(money(n))") }
        if let h = quoteHold72?.totalCharge { lines.append("Held \(Int(hold72Hours / 24)) days: \(money(h))") }
        if tipMatchesThisShipment, let a = nonEmpty(tip?.action) { lines.append(a) }
        lines.append("No requestEarlyRelease procedure exists on the server — this is logged as a named gap, not a silent failure.")
        return lines
    }

    // MARK: - Stale / cache-age line (READ_CACHED 5m)

    private var cacheAgeLine: String? {
        guard let synced = lastSyncedAt else { return nil }
        let age = Date().timeIntervalSince(synced)
        guard age > Self.cacheTTL else { return nil }
        let minutes = Int(age / 60)
        return "Figures are \(minutes)m old — pull down to re-price this charge."
    }

    private func staleNote(_ text: String, danger: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: danger ? "wifi.exclamationmark" : "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(danger ? Brand.danger : Brand.warning)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Toast

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

    // MARK: - Dispute sheet (ONLINE_ONLY)

    private var disputeSheet: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("DISPUTE THIS CHARGE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }

                Text("Dispute \(money(accruedNow))")
                    .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                    .foregroundStyle(palette.textPrimary)

                Text(disputeSheetBlurb)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !reach.isOnline {
                    LifecycleCard(accentDanger: true) {
                        Text("Offline — a dispute moves money, so it is never queued. Reconnect and file it live.")
                            .font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }

                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("REASON")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    ForEach(DisputeReason004.allCases) { reason in
                        reasonRow(reason)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("REQUESTED WAIVER (\(currencyCode), optional)")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    TextField("Amount", text: $waiverText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 15, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                        .padding(Space.s3)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTES (optional · 2000 max)")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    TextField("What happened at the yard…", text: $disputeNotes, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .padding(Space.s3)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }

                if let err = disputeError {
                    Text(err)
                        .font(EType.caption).foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await fileDispute() }
                } label: {
                    HStack {
                        Spacer()
                        if filing {
                            ProgressView().tint(palette.textOnGradient)
                        } else {
                            Text(reach.isOnline ? "File dispute" : "Offline · can't file")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(palette.textOnGradient)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(filing || !reach.isOnline || !canDispute)
                .opacity((filing || !reach.isOnline || !canDispute) ? 0.55 : 1)

                Spacer(minLength: Space.s5)
            }
            .padding(Space.s5)
        }
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var disputeSheetBlurb: String {
        var parts: [String] = []
        if let yard = yardLabel { parts.append("Car held at \(yard).") }
        parts.append("\(fmtHours(chargeableHours)) chargeable at \(money(ratePerHour))/hr across \(railcarCount) car\(railcarCount == 1 ? "" : "s").")
        parts.append("Filing drops the charge out of billing while it is reviewed and writes an immutable audit entry.")
        return parts.joined(separator: " ")
    }

    private func reasonRow(_ reason: DisputeReason004) -> some View {
        Button {
            disputeReason = reason
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: disputeReason == reason ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(disputeReason == reason ? Brand.blue : palette.textTertiary)
                Text(reason.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(disputeReason == reason ? Brand.blue.opacity(0.45) : palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Formatting

    private func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        // Whole figures read clean; cents are never silently rounded away on a
        // money surface.
        f.maximumFractionDigits = (value == value.rounded()) ? 0 : 2
        return f.string(from: NSNumber(value: value)) ?? "\(currencyCode) \(trimNumber(value))"
    }

    private func trimNumber(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    private func fmtHours(_ hours: Double) -> String {
        hours == hours.rounded() ? "\(Int(hours))h" : String(format: "%.1fh", hours)
    }

    private func shortStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm"
        return f.string(from: date)
    }

    private func nonEmpty(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    // MARK: - Load
    //
    // Wave 1 fans the three reads out in parallel; the charge itself is the one
    // that may fail loudly (it is the subject of the screen), the two
    // enrichments degrade to nil. Wave 2 then prices the charge — five
    // calculateAccrual calls off ONE real placedAt: the three country regimes
    // (which is also how the live figure is obtained) plus a now+24h and a
    // placement+72h horizon. READ_CACHED(5m): on failure the last good serve
    // stays on screen with its age stamped, rather than blanking to zeros.

    private func load() async {
        loading = true
        loadError = nil

        async let chargesTask: [RailDemurrageRow004] = EusoTripAPI.shared.query(
            "railShipments.getRailDemurrage",
            input: ShipmentIdIn004(shipmentId: shipmentId))
        async let headTask: RailShipmentHead004? = EusoTripAPI.shared.query(
            "railShipments.getRailShipmentDetail",
            input: ShipmentDetailIn004(id: shipmentId))
        async let tipTask: LiveDemurrageTip004? = EusoTripAPI.shared.queryNoInput(
            "railShipments.getLiveDemurrage")

        let headValue = (try? await headTask) ?? nil
        let tipValue = (try? await tipTask) ?? nil
        if headValue != nil { head = headValue }
        tip = tipValue

        var reachedServer = headValue != nil || tipValue != nil
        do {
            let rows = try await chargesTask
            charges = rows
            reachedServer = true
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        await priceCharge()

        if reachedServer || loadError == nil { lastSyncedAt = Date() }
        loading = false
    }

    /// Every dollar on this screen is minted here, by the procedure that owns
    /// the free-time and rate constants. No local tariff table, no local rate.
    private func priceCharge() async {
        guard let row = activeCharge, let placedRaw = nonEmpty(row.placedAt), let placed = placedAt else {
            quoteUS = nil; quoteCA = nil; quoteMX = nil
            quoteNext24 = nil; quoteHold72 = nil
            return
        }
        // railcarCount is the shipment's real numberOfCars column; when that is
        // absent we fall back to the number of demurrage rows actually on the
        // charge (one row per car), never to an invented fleet size.
        let cars = max(1, head?.numberOfCars ?? charges.count)
        let release = nonEmpty(row.releasedAt)
        let country = countryCode
        let next24ISO = isoString004((releasedAt ?? Date()).addingTimeInterval(24 * 3600))
        let hold72ISO = isoString004(placed.addingTimeInterval(hold72Hours * 3600))

        async let usTask: AccrualQuote004? = EusoTripAPI.shared.query(
            "railDemurrageAuto.calculateAccrual",
            input: AccrualIn004(placementTime: placedRaw, releaseTime: release, country: "US", railcarCount: cars))
        async let caTask: AccrualQuote004? = EusoTripAPI.shared.query(
            "railDemurrageAuto.calculateAccrual",
            input: AccrualIn004(placementTime: placedRaw, releaseTime: release, country: "CA", railcarCount: cars))
        async let mxTask: AccrualQuote004? = EusoTripAPI.shared.query(
            "railDemurrageAuto.calculateAccrual",
            input: AccrualIn004(placementTime: placedRaw, releaseTime: release, country: "MX", railcarCount: cars))
        async let next24Task: AccrualQuote004? = EusoTripAPI.shared.query(
            "railDemurrageAuto.calculateAccrual",
            input: AccrualIn004(placementTime: placedRaw, releaseTime: next24ISO, country: country, railcarCount: cars))
        async let hold72Task: AccrualQuote004? = EusoTripAPI.shared.query(
            "railDemurrageAuto.calculateAccrual",
            input: AccrualIn004(placementTime: placedRaw, releaseTime: hold72ISO, country: country, railcarCount: cars))

        let us = (try? await usTask) ?? nil
        let ca = (try? await caTask) ?? nil
        let mx = (try? await mxTask) ?? nil
        let n24 = (try? await next24Task) ?? nil
        let h72 = (try? await hold72Task) ?? nil

        if us != nil { quoteUS = us }
        if ca != nil { quoteCA = ca }
        if mx != nil { quoteMX = mx }
        if n24 != nil { quoteNext24 = n24 }
        if h72 != nil { quoteHold72 = h72 }
    }

    // MARK: - Dispute submit (MUTATION · POST · ONLINE_ONLY)

    private func fileDispute() async {
        guard let row = activeCharge else { return }
        // ONLINE_ONLY (Encyclopedia v2): money movement never queues. This is the
        // refusal, not a retry — the request is not written anywhere.
        guard reach.isOnline else {
            disputeError = "Offline — a demurrage dispute moves money and is never queued. Nothing was saved. Reconnect and file it live."
            return
        }
        guard canDispute else {
            disputeError = row.isDisputed
                ? "A dispute is already open on this charge."
                : "This charge is \(row.status ?? "closed") and can no longer be disputed."
            return
        }

        filing = true
        disputeError = nil

        let trimmedNotes = disputeNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = trimmedNotes.isEmpty ? nil : String(trimmedNotes.prefix(2000))
        let waiverRaw = Double(waiverText.trimmingCharacters(in: .whitespacesAndNewlines))
        let waiver = waiverRaw.map { max(0, min(9_999_999, $0)) }

        // createDispute is a MUTATION (railDemurrageAuto.ts:264 `.mutation`).
        // mutation() issues POST; the server has no method override, so sending
        // this through query() would be a dead CTA (fault class S4).
        // `confirm: true` is a zod LITERAL — omitting it 400s the call.
        do {
            let receipt: DisputeReceipt004 = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.createDispute",
                input: DisputeIn004(
                    confirm: true,
                    demurrageId: row.id,
                    reason: disputeReason.rawValue,
                    notes: notes,
                    requestedWaiverAmount: waiver))
            showDispute = false
            showToast("Dispute \(receipt.disputeId ?? "filed") submitted")
            await load()
        } catch {
            disputeError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        filing = false
    }
}

// MARK: - Previews

#Preview("004 · Rail Demurrage Detail · Night") {
    RailDemurrageDetail_004(theme: Theme.dark, shipmentId: 0)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("004 · Rail Demurrage Detail · Light") {
    RailDemurrageDetail_004(theme: Theme.light, shipmentId: 0)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
