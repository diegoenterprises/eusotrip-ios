//
//  696_RailJunctionDetentionBilling.swift
//  EusoTrip — Rail Engineer / Carrier · Detention-at-Junction Billing.
//
//  PURPOSE: turn cars held at an interchange junction into a defensible bill
//  against the road that is holding them.
//
//  Verbatim port of 05 Rail/Light-SVG/696 Rail Junction Detention Billing.svg
//  (Light + Dark). Register order is the SVG's, vector for vector: eyebrow +
//  right register · back chevron + "Junction detention" + overflow · junction
//  subtitle · 3-chip strip · iridescent hairline · amount hero · accruing
//  status card · "BREAKDOWN" section rule · stacked bar + ledger rows + TOTAL ·
//  GROSS band · dwell-reason chips · US/CA/MX regime band · Bill detention /
//  Dispute CTA pair · HOME · SHIPMENTS(current) · orb · COMPLIANCE · ME.
//
//  ARCHETYPE: MONEY. The SVG demanded it — a tabular monospaced amount hero, a
//  proportional stacked bar, a line-item ledger with per-row amount + share, a
//  TOTAL band, and a currency register. Nothing here is a board or a detail
//  card: the unit of work is a charge, and the verb is "bill it".
//
//  The differentiator is the EVIDENCE EXPANDER. Interline money is the least
//  trusted number in rail, so every ledger line opens to the proof behind the
//  charge — which event started the clock (placedAt), which ended it
//  (releasedAt, or "still holding"), what free time applied (the line's own
//  freeTimeHours off dashboard.perCarRunway, joined on demurrageId), and the
//  arithmetic re-run on device: chargeableHours × ratePerHour vs the engine's
//  stored total. When those disagree the row says so in amber instead of
//  quietly billing the counter-party road a number nobody can defend.
//
//  WIRING MANIFEST (every line re-read in the real file this fire; the SVG
//  <desc> line numbers were ALL stale and its named STUB is now closed):
//    junction picker           → railShipments.getRailYards
//                                EXISTS railShipments.ts:1251 (query)
//    amount hero · stacked bar · ledger · TOTAL
//                             → railDemurrageAuto.detentionAtJunction
//                                EXISTS railDemurrageAuto.ts:587 (query)
//    per-line free time (evidence)
//                             → railDemurrageAuto.dashboard
//                                EXISTS railDemurrageAuto.ts:47 (query, no input)
//    regime band free time + rate
//                             → railDemurrageAuto.calculateAccrual
//                                EXISTS railDemurrageAuto.ts:151 (query)
//                                — the US/CA 48h·$35 and MX 24h·$40 constants
//                                (railDemurrageAuto.ts:17-18) are READ off this
//                                response, never retyped on the client.
//    dwell-reason chips        → railDemurrageAuto.reportByDwellReason
//                                EXISTS railDemurrageAuto.ts:697 (query)
//    "Bill detention" CTA      → railDemurrageAuto.billDetention
//                                EXISTS railDemurrageAuto.ts:634 (MUTATION)
//    "Dispute" CTA             → railDemurrageAuto.createDispute
//                                EXISTS railDemurrageAuto.ts:265 (MUTATION)
//    charge-type split (junction / per-diem / storage)
//                             → STUB · named-gap. rail_demurrage has NO
//                                chargeType column (drizzle/schema.ts:11366).
//                                The ENUM the <desc> cites lives on
//                                vessel_demurrage (schema.ts:12052), a
//                                different mode. The stacked bar therefore
//                                renders the REAL dimension the router
//                                returns — byStatus — and never invents a
//                                per-diem or storage line.
//
//  FIRST CALLER — verified by sweep this fire: before this screen,
//  `billDetention` and `detentionAtJunction` had ZERO callers anywhere in the
//  product (no web page under frontend/, no other iOS view, no service). Both
//  were live, tenant-scoped, audited procedures with no surface reaching them.
//  This screen is their first and only caller; the dead-air row closes here.
//
//  WRITES: billDetention flips rail_demurrage.status accruing → invoiced under
//  an atomic status guard, and writes ONE blockchainAuditTrail row,
//  eventType "rail.detention_billed" (railDemurrageAuto.ts:657-664).
//  createDispute inserts demurrage_disputes + audits "rail.demurrage_disputed"
//  (:306). WS_EVENTS broadcast by either verb: NONE — this router only ever
//  puts a frame on the socket in resolveDispute (:506-523), which is an
//  ADMIN adjudication path this screen does not call. No live push; the board
//  reloads after every commit.
//
//  RBAC: protectedProcedure for the whole railDemurrageAuto family; the
//  junction picker is railProcedure (requireUser + requireRailMode), which is
//  the correct gate for a Rail Engineer surface. Every read and write is
//  tenant-scoped server-side on railShipments.companyId — no client-supplied
//  id can select or bill another company's rows.
//
//  transportMode = rail. COUNTRY IS CONTENT, not a fork: the selected junction
//  carries its own rail_yards.country (US · CA · MX), and the regime band
//  shows all three statutory free-time / rate pairs as returned by
//  calculateAccrual, marking the one this junction bills under — so a
//  cross-border pair (Laredo / Nuevo Laredo, Eagle Pass / Piedras Negras,
//  Detroit / Windsor) reads as two junctions with two regimes, honestly, on
//  one screen. STB/FRA · Transport Canada Rail · ARTF/SICT.
//
//  OFFLINE POLICY (Encyclopedia v2): READ_CACHED(15m) for the junction board,
//  the regime band and the dwell-reason strip — a stale read is drawn with a
//  monospaced staleness stamp in the header right register that flips to
//  Brand.warning, never passed off as live. Every commit is ONLINE_ONLY
//  because it moves money against a counter-party road: billDetention and
//  createDispute are confirm-gated and NEVER queued. No rail path is offline-
//  eligible (Services/EusoTripAPI.swift:1684 lists the only six), so the CTA
//  disables with the reason printed under it instead of silently swallowing
//  the error or pretending it queued.
//
//  HOW THIS MAKES THE RAIL USER'S JOB EASIER: the carrier can bill a
//  counter-party road for cars it held at a junction, with the clock evidence
//  attached, instead of eating the charge because nobody could prove it.
//

import SwiftUI

struct RailJunctionDetentionBilling_696: View {
    let theme: Theme.Palette
    var yardId: Int = 0
    var body: some View {
        Shell(theme: theme) { RailJunctionDetentionBillingBody696(initialYardId: yardId) } nav: {
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

// MARK: - Decodable models
//
// SHIPMENTS is the current tab: a junction detention charge hangs off a rail
// shipment (rail_demurrage.shipmentId), the router scopes every read to
// railShipments.companyId, and the operator arrives here from the movement —
// not from a compliance filing.

/// One billable line — railDemurrageAuto.detentionAtJunction `lines[]`.
private struct DetentionLine696: Decodable, Identifiable {
    let demurrageId: Int
    let railcarNumber: String?
    let status: String?
    let chargeableHours: Double?
    let ratePerHour: Double?
    let amount: Double?
    let placedAt: String?
    let releasedAt: String?
    var id: Int { demurrageId }
}

/// railDemurrageAuto.detentionAtJunction envelope.
private struct JunctionDetentionBoard696: Decodable {
    let yardId: Int
    let totalDue: Double?
    let carCount: Int?
    let byStatus: [String: Double]?
    let lines: [DetentionLine696]?
}

/// railDemurrageAuto.dashboard `perCarRunway[]` — the only place the server
/// returns a PER-LINE freeTimeHours, which is the evidence panel's spine.
private struct CarRunway696: Decodable, Identifiable {
    let demurrageId: Int
    let railcarNumber: String?
    let freeTimeHours: Double?
    let chargeableHours: Double?
    let ratePerHour: Double?
    let usdToday: Double?
    let usdProjected: Double?
    var id: Int { demurrageId }
}

private struct DemurrageDashboard696: Decodable {
    let perCarRunway: [CarRunway696]?
}

/// railShipments.getRailYards row — the junction picker. `country` is the
/// rail_yards enum US|CA|MX and is what selects this junction's regime.
private struct RailYardRow696: Decodable, Identifiable {
    let id: Int
    let name: String?
    let splcCode: String?
    let city: String?
    let state: String?
    let country: String?
    let yardType: String?
}

/// railDemurrageAuto.calculateAccrual — read purely for its echoed
/// freeTimeHours + ratePerHour, i.e. the server's own statutory constants.
private struct RegimeQuote696: Decodable {
    let country: String?
    let freeTimeHours: Double?
    let ratePerHour: Double?
}

private struct DwellReasonRow696: Decodable, Identifiable {
    let reason: String
    let count: Int?
    let totalCharges: Double?
    let avgHours: Double?
    var id: String { reason }
}

private struct WeatherHold696: Decodable {
    let enabled: Bool?
    let reason: String?
    let carsReviewed: Int?
    let carsWithDocumentedHold: Int?
    let excludableMinutes: Double?
    let excludableCharge: Double?
}

private struct DwellReport696: Decodable {
    let reasons: [DwellReasonRow696]?
    let weatherHold: WeatherHold696?
}

/// One segment of the stacked bar / one ledger-breakdown row. `id` is the
/// rail_demurrage.status key the router grouped by.
private struct StatusSlice696: Identifiable {
    let id: String
    let amount: Double
}

private struct BillResult696: Decodable {
    let success: Bool?
    let demurrageId: Int?
    let status: String?
    let amount: Double?
}

/// createDispute returns disputeId as a STRING ("DSP-<n>") — decoding it as an
/// Int fails the whole response.
private struct DisputeResult696: Decodable {
    let disputeId: String?
    let status: String?
    let reason: String?
    let requestedWaiver: Double?
}

// MARK: - Encoded inputs
//
// Server zod uses `.optional()`, which REJECTS the `null` Swift's synthesized
// encoder emits for an absent optional — so every optional below goes through
// `encodeIfPresent` in a hand-rolled `encode(to:)`. Inputs with no optional
// field use the synthesized encoder. `confirm` is a `z.literal(true)` on both
// money verbs: omit it and the call 400s.

private struct YardsIn696: Encodable { let limit: Int }
private struct JunctionIn696: Encodable { let yardId: Int; let window: String }
private struct AccrualIn696: Encodable { let placementTime: String; let country: String }
private struct DwellIn696: Encodable { let periodDays: Int }
private struct BillIn696: Encodable { let confirm: Bool; let demurrageId: Int }

private struct DisputeIn696: Encodable {
    let confirm: Bool
    let demurrageId: Int
    let reason: String
    let notes: String?
    let requestedWaiverAmount: Double?

    enum CodingKeys: String, CodingKey { case confirm, demurrageId, reason, notes, requestedWaiverAmount }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(confirm, forKey: .confirm)
        try c.encode(demurrageId, forKey: .demurrageId)
        try c.encode(reason, forKey: .reason)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(requestedWaiverAmount, forKey: .requestedWaiverAmount)
    }
}

private enum DisputeReason696: String, CaseIterable, Identifiable {
    case serviceFailure = "service_failure"
    case weather        = "weather"
    case customerError  = "customer_error"
    case dataError      = "data_error"
    case other          = "other"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .serviceFailure: return "Service failure (our road)"
        case .weather:        return "Weather / force majeure"
        case .customerError:  return "Customer error"
        case .dataError:      return "Data error (clock or rate wrong)"
        case .other:          return "Other"
        }
    }
}

// MARK: - Body

private struct RailJunctionDetentionBillingBody696: View {
    let initialYardId: Int
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    // Junction selection
    @State private var yards: [RailYardRow696] = []
    @State private var selectedYardId: Int = 0
    @State private var showJunctionPicker = false

    // Board
    @State private var board: JunctionDetentionBoard696? = nil
    @State private var runway: [CarRunway696] = []
    @State private var regimes: [RegimeQuote696] = []
    @State private var dwell: DwellReport696? = nil

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var loadedAt: Date? = nil

    // Ledger interaction
    @State private var expandedLineId: Int? = nil
    @State private var selectedLineId: Int? = nil

    // Money commits — ONLINE_ONLY, confirm-gated, never queued.
    @State private var billLine: DetentionLine696? = nil
    @State private var billing = false
    @State private var disputeLine: DetentionLine696? = nil
    @State private var disputeReason: DisputeReason696 = .dataError
    @State private var disputeNotes: String = ""
    @State private var disputeWaiverText: String = ""
    @State private var disputing = false

    @State private var toast: String? = nil
    @State private var toastOK = true
    @State private var toastTask: Task<Void, Never>? = nil

    /// Read window sent to detentionAtJunction and reportByDwellReason.
    private static let windowToken = "30d"
    private static let windowDays  = 30

    // MARK: Derived — all from decoded server fields only

    private var lines: [DetentionLine696] { board?.lines ?? [] }
    private var byStatus: [String: Double] { board?.byStatus ?? [:] }
    private var totalDue: Double { board?.totalDue ?? 0 }
    private var carCount: Int { board?.carCount ?? lines.count }

    /// Gross = every state on the junction, which is what the TOTAL band means.
    /// The hero shows totalDue (still owed) — the server's own narrower number.
    private var grossTotal: Double { byStatus.values.reduce(0, +) }

    private var selectedYard: RailYardRow696? { yards.first { $0.id == selectedYardId } }

    private var junctionTitle: String {
        guard let y = selectedYard else {
            return selectedYardId > 0 ? "Junction #\(selectedYardId)" : "No junction selected"
        }
        return y.name ?? "Junction #\(y.id)"
    }

    private var junctionSubtitle: String {
        guard let y = selectedYard else {
            return selectedYardId > 0 ? "Yard #\(selectedYardId) · \(Self.windowDays)-day window"
                                      : "Pick an interchange junction to load its detention"
        }
        var parts: [String] = []
        if let s = y.splcCode, !s.isEmpty { parts.append("SPLC \(s)") }
        let place = [y.city, y.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        if !place.isEmpty { parts.append(place) }
        if let c = y.country, !c.isEmpty { parts.append(c) }
        parts.append("\(Self.windowDays)-day window")
        return parts.joined(separator: " · ")
    }

    /// The junction's own regime, from rail_yards.country — never guessed.
    private var junctionCountry: String { selectedYard?.country ?? "" }

    private var junctionRegime: RegimeQuote696? {
        guard !junctionCountry.isEmpty else { return nil }
        return regimes.first { ($0.country ?? "") == junctionCountry }
    }

    /// Dominant status by money — drives the status card's gradient tab pill.
    private var dominantStatus: String? {
        byStatus.max { a, b in a.value < b.value }?.key
    }

    private var accruingLines: [DetentionLine696] { lines.filter { ($0.status ?? "") == "accruing" } }

    private var selectedLine: DetentionLine696? { lines.first { $0.demurrageId == selectedLineId } }

    /// The one blocking reason the Bill CTA is unavailable — printed, never mimed.
    private var billBlockReason: String? {
        if !reach.isOnline { return "OFFLINE · BILLING A COUNTER-PARTY ROAD IS ONLINE-ONLY" }
        if selectedYardId <= 0 { return "PICK A JUNCTION FIRST" }
        guard let l = selectedLine else {
            return accruingLines.isEmpty ? "NO ACCRUING CHARGE AT THIS JUNCTION"
                                         : "SELECT A LINE TO BILL"
        }
        if (l.status ?? "") != "accruing" {
            return "LINE IS \((l.status ?? "unknown").uppercased()) · ONLY ACCRUING CAN BE BILLED"
        }
        return nil
    }

    private var disputeBlocked: Bool {
        if !reach.isOnline { return true }
        guard let l = selectedLine else { return true }
        let s = l.status ?? ""
        return s == "paid" || s == "waived"
    }

    /// Cached-read honesty: the header right register stamps age past 15m.
    private var staleness: (text: String, warn: Bool) {
        guard let t = loadedAt else { return ("JUNCTION BILL", false) }
        let age = Date().timeIntervalSince(t)
        if age < 900 { return ("JUNCTION BILL", false) }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return ("AS OF \(f.string(from: t)) · STALE", true)
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                Text(junctionSubtitle)
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                chipStrip
                IridescentHairline()
                junctionField

                if loading {
                    LifecycleCard { Text("Reading detention at this junction…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if selectedYardId <= 0 {
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Pick the interchange junction you are billing for.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                            Text("Detention accrues against whoever is holding the cars. This screen bills that hold to the counter-party road, with the clock evidence attached.")
                                .font(EType.caption).foregroundStyle(palette.textTertiary)
                        }
                    }
                } else {
                    amountHero
                    statusCard
                    sectionRule
                    breakdownCard
                    ledgerSection
                    dwellSection
                    regimeBand
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $showJunctionPicker) { junctionSheet }
        .sheet(item: $billLine) { l in billSheet(l) }
        .sheet(item: $disputeLine) { l in disputeSheet(l) }
    }

    // MARK: Eyebrow + headline (SVG y=72 / y=116)

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Text("✦ CARRIER · RAIL · DETENTION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text(staleness.text)
                .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.8)
                .foregroundStyle(staleness.warn ? Brand.warning : palette.textTertiary)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Text("Junction detention")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Chip strip (SVG y=150)

    private var chipStrip: some View {
        HStack(spacing: Space.s2) {
            chip(money(totalDue), Brand.blue)
            chip("\(hours(lines.compactMap { $0.chargeableHours }.reduce(0, +))) over free", Brand.warning)
            chip("\(carCount) car\(carCount == 1 ? "" : "s")", palette.textSecondary)
            Spacer(minLength: 0)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t)
            .font(.system(size: 10, weight: .heavy)).tracking(0.3)
            .foregroundStyle(c)
            .lineLimit(1)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCard))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Junction picker field
    //
    // There is no rail-yard-scoped detention index on the server, so the
    // junction is chosen from the real rail_yards list rather than typed blind.

    private var junctionField: some View {
        Button { showJunctionPicker = true } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("JUNCTION")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(junctionTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                Text(yards.isEmpty ? "NO YARDS" : "CHANGE")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var junctionSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("INTERCHANGE JUNCTION").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Pick a junction")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                .foregroundStyle(palette.textPrimary)
            Text("Each yard carries its own country, and with it the free-time and rate regime this junction bills under.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)

            if yards.isEmpty {
                LifecycleCard {
                    Text("No active rail yards returned for this account.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Space.s2) {
                        ForEach(yards) { y in junctionRow(y) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func junctionRow(_ y: RailYardRow696) -> some View {
        let on = y.id == selectedYardId
        let place = [y.city, y.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return Button {
            selectedYardId = y.id
            selectedLineId = nil
            expandedLineId = nil
            showJunctionPicker = false
            Task { await load() }
        } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(y.name ?? "Yard #\(y.id)")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text([place, y.yardType?.replacingOccurrences(of: "_", with: " ")]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer()
                if let c = y.country, !c.isEmpty {
                    Text(c).font(.system(size: 10, weight: .heavy)).monospaced()
                        .foregroundStyle(Brand.blue)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Brand.blue.opacity(0.14)))
                }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(on ? Brand.blue.opacity(0.45) : palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Amount hero (SVG y=236)

    private var amountHero: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(money(totalDue))
                .font(.system(size: 34, weight: .heavy, design: .monospaced))
                .foregroundStyle(Brand.blue)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text("Still owed at this junction · \(carCount) car\(carCount == 1 ? "" : "s") · \(accruingLines.count) accruing")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Accruing status card (SVG y=272)

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("DETENTION · \((dominantStatus ?? "no charges").uppercased())")
                .font(.system(size: 9.5, weight: .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 22)
                .background(Capsule().fill(LinearGradient.diagonal))
            Text(junctionTitle)
                .font(.system(size: 14, weight: .heavy)).foregroundStyle(palette.textPrimary)
                .lineLimit(2)
            Text(statusCardDetail)
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var statusCardDetail: String {
        guard !lines.isEmpty else { return "No detention rows in the last \(Self.windowDays) days." }
        var parts = ["\(carCount) car\(carCount == 1 ? "" : "s")"]
        if let r = junctionRegime, let ft = r.freeTimeHours {
            parts.append("free time \(hours(ft)) (\(junctionCountry))")
        }
        let held = lines.filter { $0.releasedAt == nil }.count
        if held > 0 { parts.append("\(held) still holding · clock running") }
        return parts.joined(separator: " · ")
    }

    // MARK: Section rule (SVG y=362)

    private var sectionRule: some View {
        VStack(spacing: 6) {
            HStack {
                Text("BREAKDOWN · BY CHARGE STATE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("USD")
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)
        }
    }

    // MARK: Breakdown — stacked bar + ledger rows + TOTAL band (SVG y=378)

    /// byStatus, ordered by money desc — the real dimension the router returns.
    private var statusSlices: [StatusSlice696] {
        byStatus.map { StatusSlice696(id: $0.key, amount: $0.value) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }

    private var breakdownCard: some View {
        VStack(spacing: 0) {
            stackedBar.padding(.top, Space.s4).padding(.horizontal, Space.s4)
            if statusSlices.isEmpty {
                Text("No charges in state at this junction over the last \(Self.windowDays) days.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(statusSlices) { s in breakdownRow(s.id, s.amount) }
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, Space.s4)
            HStack {
                Text("TOTAL · GROSS")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text(money(grossTotal))
                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Brand.blue)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        }
        .padding(.vertical, Space.s1)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var stackedBar: some View {
        let lead = statusSlices.first?.id
        return GeometryReader { g in
            HStack(spacing: 0) {
                ForEach(statusSlices) { s in
                    let frac = grossTotal > 0 ? s.amount / grossTotal : 0
                    Group {
                        if s.id == lead {
                            Rectangle().fill(LinearGradient.diagonal)
                        } else {
                            Rectangle().fill(statusColor(s.id))
                        }
                    }
                    .frame(width: max(0, g.size.width * frac))
                }
                if statusSlices.isEmpty || grossTotal <= 0 {
                    Rectangle().fill(palette.borderFaint)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 12)
    }

    private func breakdownRow(_ key: String, _ amount: Double) -> some View {
        let pct = grossTotal > 0 ? amount / grossTotal * 100 : 0
        let c = statusColor(key)
        let n = lines.filter { ($0.status ?? "") == key }.count
        return HStack(spacing: Space.s3) {
            Circle().fill(c).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusLabel(key))
                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("\(n) line\(n == 1 ? "" : "s") · \(statusMeaning(key))")
                    .font(.system(size: 9.5)).foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(money(amount))
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Text(String(format: "%.0f%%", pct))
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(c)
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 10)
    }

    // MARK: Line-item ledger + evidence expander
    //
    // The MONEY archetype's core. billDetention takes ONE demurrageId, so the
    // operator must be able to see and pick the exact car. Tapping a row opens
    // the proof the counter-party road will demand.

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("LEDGER · CARS HELD AT THIS JUNCTION")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("HRS × RATE")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
            }
            if lines.isEmpty {
                LifecycleCard {
                    Text("No cars accrued detention at this junction in the last \(Self.windowDays) days.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(lines) { l in ledgerRow(l) }
                }
            }
        }
    }

    private func ledgerRow(_ l: DetentionLine696) -> some View {
        let picked = l.demurrageId == selectedLineId
        let open = l.demurrageId == expandedLineId
        let c = statusColor(l.status ?? "")
        return VStack(alignment: .leading, spacing: Space.s2) {
            Button {
                selectedLineId = picked ? nil : l.demurrageId
                withAnimation(.easeOut(duration: 0.16)) {
                    expandedLineId = open ? nil : l.demurrageId
                }
            } label: {
                HStack(spacing: Space.s3) {
                    Image(systemName: picked ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(picked ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l.railcarNumber ?? "Charge #\(l.demurrageId)")
                            .font(.system(size: 13, weight: .bold)).monospaced()
                            .foregroundStyle(palette.textPrimary).lineLimit(1)
                        Text("\(hours(l.chargeableHours ?? 0)) × \(rate(l.ratePerHour ?? 0))")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: Space.s2)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(money(l.amount ?? 0))
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textPrimary)
                        Text((l.status ?? "unknown").uppercased())
                            .font(.system(size: 9, weight: .heavy)).foregroundStyle(c)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(c.opacity(0.14)))
                    }
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if open { evidencePanel(l) }
        }
        .padding(Space.s3)
        .background(picked ? Brand.blue.opacity(0.06) : palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(picked ? Brand.blue.opacity(0.42) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// The bill's defence file. Every value is a decoded server field or an
    /// arithmetic check re-run on those fields — nothing is asserted.
    private func evidencePanel(_ l: DetentionLine696) -> some View {
        let run = runway.first { $0.demurrageId == l.demurrageId }
        let freeTime = run?.freeTimeHours
        let ch = l.chargeableHours ?? 0
        let rt = l.ratePerHour ?? 0
        let stored = l.amount ?? 0
        let recomputed = ch * rt
        let agrees = abs(recomputed - stored) < 0.01
        let regimeRate = junctionRegime?.ratePerHour

        return VStack(alignment: .leading, spacing: Space.s2) {
            Rectangle().fill(palette.borderFaint).frame(height: 1)
            Text("EVIDENCE · WHAT THE CLOCK RAN ON")
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)

            evidenceRow("Clock start · placed", l.placedAt.map(shortDate) ?? "not recorded", l.placedAt == nil ? Brand.warning : palette.textPrimary)
            evidenceRow("Clock stop · released",
                        l.releasedAt.map(shortDate) ?? "still holding · running",
                        l.releasedAt == nil ? Brand.warning : palette.textPrimary)
            if let ft = freeTime {
                evidenceRow("Free time applied", hours(ft), palette.textPrimary)
            } else {
                evidenceRow("Free time applied", "not returned on this line", Brand.warning)
            }
            evidenceRow("Chargeable over free time", hours(ch), palette.textPrimary)
            if let rr = regimeRate, rt > 0, abs(rr - rt) >= 0.01 {
                evidenceRow("Rate applied", "\(rate(rt)) · off \(junctionCountry) regime \(rate(rr))", Brand.warning)
            } else {
                evidenceRow("Rate applied", rate(rt), palette.textPrimary)
            }

            HStack(spacing: 6) {
                Image(systemName: agrees ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(agrees ? Brand.success : Brand.warning)
                Text(agrees
                     ? "Arithmetic checks: \(hours(ch)) × \(rate(rt)) = \(money(stored))"
                     : "Engine total \(money(stored)) ≠ \(hours(ch)) × \(rate(rt)) = \(money(recomputed))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(agrees ? palette.textSecondary : Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill((agrees ? Brand.success : Brand.warning).opacity(0.10)))

            if let p = run?.usdProjected, let t = run?.usdToday, p > t {
                Text("If the car is still held 24h from now this line reaches \(money(p)).")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func evidenceRow(_ k: String, _ v: String, _ tone: Color) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Text(k).font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s2)
            Text(v).font(.system(size: 10, weight: .heavy)).monospaced()
                .foregroundStyle(tone).multilineTextAlignment(.trailing)
        }
    }

    // MARK: Dwell-reason strip (SVG y=600)

    private var dwellSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("DWELL REASON · CAPTURED AT PLACEMENT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textSecondary)

            let rows = dwell?.reasons ?? []
            if rows.isEmpty {
                Text("Dwell-reason capture is not reporting for this account.")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
            } else {
                let counted = rows.filter { ($0.count ?? 0) > 0 }
                if counted.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: Space.s2) {
                            ForEach(rows.prefix(3)) { r in
                                Text("\(prettyReason(r.reason)) · 0")
                                    .font(.system(size: 9.5, weight: .heavy))
                                    .foregroundStyle(palette.textTertiary)
                                    .padding(.horizontal, 13).frame(height: 24)
                                    .background(Capsule().fill(palette.textTertiary.opacity(0.10)))
                            }
                            Spacer(minLength: 0)
                        }
                        Text("Every bucket reads zero because rail_demurrage has no dwellReason column — the server never guesses a cause it cannot prove. A cause cannot be attached to this bill yet.")
                            .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: Space.s2) {
                        ForEach(counted.prefix(3)) { r in
                            let c = reasonColor(r.reason)
                            Text("\(prettyReason(r.reason)) · \(r.count ?? 0)")
                                .font(.system(size: 9.5, weight: .heavy)).foregroundStyle(c)
                                .padding(.horizontal, 13).frame(height: 24)
                                .background(Capsule().fill(c.opacity(0.12)))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            if let w = dwell?.weatherHold, (w.enabled ?? false), (w.carsWithDocumentedHold ?? 0) > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "cloud.bolt.rain.fill")
                        .font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.info)
                    Text("WX-HOLD evidence · \(w.carsWithDocumentedHold ?? 0) of \(w.carsReviewed ?? 0) cars sat under a documented severe hold · \(money(w.excludableCharge ?? 0)) excludable")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Brand.info.opacity(0.10)))
            }
        }
    }

    // MARK: Regime band (SVG y=760)
    //
    // Free time and rate are READ off calculateAccrual's echo of the server's
    // own FREE_TIME_HOURS / RATE_PER_HOUR tables — never retyped here.

    private var regimeBand: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                ForEach(["US", "CA", "MX"], id: \.self) { code in
                    regimeCard(code)
                }
            }
            Text("Amounts are the accrual engine's stored totals; it carries them in USD (its own fields are amountUsd / usdToday). Local-currency settlement is not modelled server-side.")
                .font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func regimeCard(_ code: String) -> some View {
        let q: RegimeQuote696? = regimes.first { ($0.country ?? "") == code }
        let on = code == junctionCountry
        let tone: Color = on ? Brand.blue : palette.textSecondary

        // Both values are the server's own constants echoed back by
        // calculateAccrual. A missing quote reads "—" / "rate pend", never a
        // typed-in 48 / 24 / 35 / 40.
        let freeLine: String
        if let ft = q?.freeTimeHours { freeLine = "\(code) · \(hours(ft))" } else { freeLine = "\(code) · —" }
        let rateLine: String
        if let rp = q?.ratePerHour { rateLine = rate(rp) } else { rateLine = "rate pend" }

        return VStack(alignment: .leading, spacing: 2) {
            Text(freeLine)
                .font(.system(size: 8, weight: .heavy)).tracking(0.3)
            Text(rateLine)
                .font(.system(size: 9, weight: .heavy))
        }
        .foregroundStyle(tone)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(on ? Brand.blue.opacity(0.12) : palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(on ? Brand.blue.opacity(0.40) : palette.borderFaint))
    }

    // MARK: CTA pair (SVG y=798) — money movement, ONLINE_ONLY, confirm-gated

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                CTAButton(
                    title: "Bill detention",
                    action: { if billBlockReason == nil { billLine = selectedLine } },
                    subtitle: billBlockReason,
                    isLoading: billBlockReason != nil || billing
                )
                Button {
                    guard !disputeBlocked, let l = selectedLine else { return }
                    disputeLine = l
                    disputeReason = .dataError
                    disputeNotes = ""
                    disputeWaiverText = ""
                } label: {
                    Text("Dispute")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(disputeBlocked ? palette.textTertiary : palette.textPrimary)
                        .frame(width: 132, height: 48)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(disputeBlocked)
            }
            Text(reach.isOnline
                 ? "Billing a counter-party road is a money write — it is never queued offline and always asks first."
                 : "Offline. Detention billing and disputes stay online-only; nothing is queued and nothing is filed.")
                .font(.system(size: 9.5))
                .foregroundStyle(reach.isOnline ? palette.textTertiary : Brand.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Bill sheet — irreversible money write

    private func billSheet(_ l: DetentionLine696) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("BILL DETENTION · IRREVERSIBLE").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Bill \(money(l.amount ?? 0))")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                .foregroundStyle(palette.textPrimary)
            Text("This invoices \(l.railcarNumber ?? "charge #\(l.demurrageId)") for detention at \(junctionTitle). The charge moves accruing → invoiced and the bill is written to the immutable audit trail. It cannot be un-billed from here.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                evidenceRow("Clock start", l.placedAt.map(shortDate) ?? "not recorded", palette.textPrimary)
                evidenceRow("Clock stop", l.releasedAt.map(shortDate) ?? "still holding", palette.textPrimary)
                evidenceRow("Chargeable", hours(l.chargeableHours ?? 0), palette.textPrimary)
                evidenceRow("Rate", rate(l.ratePerHour ?? 0), palette.textPrimary)
                evidenceRow("Amount", money(l.amount ?? 0), Brand.blue)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            confirmButton(title: reach.isOnline ? "Confirm the bill" : "Offline · cannot bill",
                          busy: billing, blocked: !reach.isOnline) {
                Task { await bill(l) }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    // MARK: Dispute sheet

    private func disputeSheet(_ l: DetentionLine696) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPUTE CHARGE").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Dispute \(l.railcarNumber ?? "charge #\(l.demurrageId)")")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                .foregroundStyle(palette.textPrimary)
            Text("A disputed charge drops out of the billable rollup until an adjudicator resolves it. Filing is logged to the audit trail.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("REASON").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    ForEach(DisputeReason696.allCases) { r in
                        Button { disputeReason = r } label: {
                            HStack {
                                Image(systemName: disputeReason == r ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(disputeReason == r ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                                Text(r.label).font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                            }
                            .padding(Space.s3)
                            .background(palette.bgCard)
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(disputeReason == r ? Brand.blue.opacity(0.42) : palette.borderFaint))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Text("WAIVER REQUESTED (optional)").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    TextField("Amount", text: $disputeWaiverText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                        .padding(Space.s3)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                    Text("NOTES (optional)").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    TextField("What the other road will need to see…", text: $disputeNotes, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                        .padding(Space.s3)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
            }

            confirmButton(title: reach.isOnline ? "File dispute" : "Offline · cannot file",
                          busy: disputing, blocked: !reach.isOnline) {
                Task { await dispute(l) }
            }
        }
        .padding(20)
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func confirmButton(title: String, busy: Bool, blocked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .background(blocked ? AnyShapeStyle(Brand.neutral) : AnyShapeStyle(LinearGradient.diagonal))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy || blocked)
    }

    // MARK: Toast

    private var toastView: some View {
        Group {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(toastOK ? Brand.success : Brand.danger))
                    .padding(.horizontal, 20).padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func showToast(_ msg: String, ok: Bool = true) {
        toastTask?.cancel()
        toastOK = ok
        withAnimation(.easeOut(duration: 0.18)) { toast = msg }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
    }

    // MARK: Formatting — presentation only, no business values

    private func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
    }

    private func rate(_ v: Double) -> String { "\(money(v))/h" }

    private func hours(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))h" : String(format: "%.1fh", v)
    }

    private func shortDate(_ raw: String) -> String {
        let out = DateFormatter()
        out.dateFormat = "MMM d · HH:mm"
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return out.string(from: d) }
        let f2 = ISO8601DateFormatter()
        if let d = f2.date(from: raw) { return out.string(from: d) }
        // MySQL DATETIME ("YYYY-MM-DD HH:MM:SS") comes back unconverted.
        let f3 = DateFormatter()
        f3.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f3.timeZone = TimeZone(identifier: "UTC")
        if let d = f3.date(from: raw) { return out.string(from: d) }
        return String(raw.prefix(16))
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "accruing": return Brand.warning
        case "invoiced": return Brand.blue
        case "paid":     return Brand.success
        case "disputed": return Brand.danger
        case "waived":   return Brand.neutral
        default:         return palette.textTertiary
        }
    }

    private func statusLabel(_ s: String) -> String {
        s.isEmpty ? "Unknown" : s.prefix(1).uppercased() + s.dropFirst()
    }

    private func statusMeaning(_ s: String) -> String {
        switch s {
        case "accruing": return "clock running · billable"
        case "invoiced": return "billed to the counter-party"
        case "paid":     return "settled"
        case "disputed": return "frozen pending adjudication"
        case "waived":   return "written off"
        default:         return "state not recognised"
        }
    }

    private func prettyReason(_ r: String) -> String {
        r.replacingOccurrences(of: "_", with: " ")
    }

    private func reasonColor(_ r: String) -> Color {
        switch r {
        case "consignee_not_ready": return Brand.warning
        case "yard_congestion":     return Brand.blue
        case "no_power":            return Brand.danger
        case "weather":             return Brand.info
        default:                    return palette.textSecondary
        }
    }

    // MARK: Data — parallel fan-out; a dead section degrades alone

    private func load() async {
        loading = true
        loadError = nil

        let nowISO = ISO8601DateFormatter().string(from: Date())

        async let yardsTask: [RailYardRow696] = EusoTripAPI.shared.query(
            "railShipments.getRailYards", input: YardsIn696(limit: 60))
        async let dashTask: DemurrageDashboard696 = EusoTripAPI.shared.queryNoInput(
            "railDemurrageAuto.dashboard")
        async let usTask: RegimeQuote696 = EusoTripAPI.shared.query(
            "railDemurrageAuto.calculateAccrual", input: AccrualIn696(placementTime: nowISO, country: "US"))
        async let caTask: RegimeQuote696 = EusoTripAPI.shared.query(
            "railDemurrageAuto.calculateAccrual", input: AccrualIn696(placementTime: nowISO, country: "CA"))
        async let mxTask: RegimeQuote696 = EusoTripAPI.shared.query(
            "railDemurrageAuto.calculateAccrual", input: AccrualIn696(placementTime: nowISO, country: "MX"))
        async let dwellTask: DwellReport696 = EusoTripAPI.shared.query(
            "railDemurrageAuto.reportByDwellReason", input: DwellIn696(periodDays: Self.windowDays))

        let loadedYards = (try? await yardsTask) ?? []
        yards = loadedYards

        // Resolve the junction: an injected id, the standing choice, else the
        // first real yard the account can see. Never a fabricated id.
        if selectedYardId <= 0 {
            if initialYardId > 0 { selectedYardId = initialYardId }
            else if let first = loadedYards.first { selectedYardId = first.id }
        }

        runway = ((try? await dashTask)?.perCarRunway) ?? []
        regimes = [(try? await usTask), (try? await caTask), (try? await mxTask)].compactMap { $0 }
        dwell = try? await dwellTask

        if selectedYardId > 0 {
            do {
                board = try await EusoTripAPI.shared.query(
                    "railDemurrageAuto.detentionAtJunction",
                    input: JunctionIn696(yardId: selectedYardId, window: Self.windowToken))
                loadedAt = Date()
            } catch {
                loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        } else {
            board = nil
            loadedAt = Date()
        }

        // Drop a stale selection that no longer exists on the reloaded board.
        if let sel = selectedLineId, !(board?.lines ?? []).contains(where: { $0.demurrageId == sel }) {
            selectedLineId = nil
            expandedLineId = nil
        }

        loading = false
    }

    /// ONLINE_ONLY money write. confirm:true is a zod literal — omitting it 400s.
    private func bill(_ l: DetentionLine696) async {
        guard reach.isOnline else {
            showToast("Offline — detention billing is never queued", ok: false)
            return
        }
        billing = true
        do {
            let res: BillResult696 = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.billDetention",
                input: BillIn696(confirm: true, demurrageId: l.demurrageId))
            billLine = nil
            showToast("Billed \(money(res.amount ?? l.amount ?? 0)) · \((res.status ?? "invoiced").uppercased())")
            await load()
        } catch {
            showToast((error as? EusoTripAPIError)?.errorDescription ?? "Billing failed", ok: false)
        }
        billing = false
    }

    private func dispute(_ l: DetentionLine696) async {
        guard reach.isOnline else {
            showToast("Offline — a dispute is never queued", ok: false)
            return
        }
        let notes = disputeNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let waiver = Double(disputeWaiverText.trimmingCharacters(in: .whitespaces))

        disputing = true
        do {
            let res: DisputeResult696 = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.createDispute",
                input: DisputeIn696(confirm: true,
                                    demurrageId: l.demurrageId,
                                    reason: disputeReason.rawValue,
                                    notes: notes.isEmpty ? nil : String(notes.prefix(2000)),
                                    requestedWaiverAmount: waiver))
            disputeLine = nil
            showToast("Dispute filed \(res.disputeId ?? "") · charge frozen")
            await load()
        } catch {
            showToast((error as? EusoTripAPIError)?.errorDescription ?? "Dispute failed", ok: false)
        }
        disputing = false
    }
}

#Preview("696 · Rail Junction Detention Billing · Night") {
    RailJunctionDetentionBilling_696(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("696 · Rail Junction Detention Billing · Light") {
    RailJunctionDetentionBilling_696(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
