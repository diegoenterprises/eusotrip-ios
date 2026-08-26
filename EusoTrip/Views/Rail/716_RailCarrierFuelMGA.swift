//
//  716_RailCarrierFuelMGA.swift
//  EusoTrip — Rail Carrier · Fuel and MGA (CARRIER/ENGINEER SIDE · money band).
//
//  Author of record: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  MGA = Mileage and Gallonage Accounting: the carrier's own per-locomotive
//  fuel-burn accounting that feeds the surcharge.
//
//  Faithful 1:1 port of "05 Rail/Light-SVG/716 Rail Carrier Fuel and MGA.svg"
//  and its Dark twin. Same sections, same order, same encodings.
//
//  WHAT THIS SCREEN CAN AND CANNOT SAY (fire 17, 2026-08-25). The composition
//  is the wireframe's; the DATA behind it is not rail data. Every fuel source
//  reachable from here is the highway fleet fuel-card table, and there is no
//  reporting mark on file for the signed-in account. So: the chart and the
//  ledger are drawn and labelled as the highway-fleet figures they are, and
//  the surcharge derivation — which would have to name a railroad and bill a
//  distance — is not drawn at all. No value below is invented, and where a
//  value is absent the screen renders the absence by name rather than a
//  stand-in. The remaining fabrications are on the server, are listed by
//  named gap below, and are refused here rather than passed through.
//
//  ARCHETYPE: MONEY. The hero is a COMBO COLUMN-AND-STEP CHART — monthly
//  gallons as columns with the price paid per gallon drawn OVER them as a step
//  line on a second implied axis, axis labels in mono, the current period's
//  column inked in the house gradient and every other column neutral. Under it
//  a FUEL LEDGER — the wireframe's per-locomotive MGA ledger, carrying the only
//  rows that exist: highway fleet fuel by driver (miles, gallons, gross
//  ton-miles per gallon, right-aligned, the status pill parked in its own
//  column so it can never collide). Then a SURCHARGE DERIVATION card that shows
//  its work — index → peg → step → cents-per-mile, closed by a ruled total —
//  which today renders its suppressed state instead. Deliberately
//  unlike 640 (a smooth area trend line over PADD regional bars, no columns)
//  and unlike 577 (a ¢/mi-vs-diesel staircase over a mileage table, no burn
//  series and no per-unit ledger). 716 leads with a CHART; the money appears
//  only where the arithmetic lands.
//
//  ── WIRING MANIFEST ────────────────────────────────────────────────────────
//    fuelManagement.getFuelTrendAnalysis        EXISTS fuelManagement.ts:1672
//        → {trends:[{month, avgPrice, totalGallons, totalCost, avgMpg,
//          costPerMile}], summary}. BOTH hero series come from this ONE tick:
//          totalGallons draws the columns, avgPrice draws the step line.
//          HIGHWAY SOURCE: it groups `fuelTransactions` (companyId-scoped, the
//          truck fuel-card table) by month. `avgPrice` is the company's OWN
//          average pump price paid — NOT a published index — and `avgMpg` is a
//          flat 6.5 for every month (:1702 miles = gallons * 6.5), so it is a
//          constant and not a measurement. The chart is labelled accordingly.
//    fuelSurchargeIndex.currentDieselIndex      EXISTS fuelSurchargeIndex.ts:56
//        → {source, weekOf, nationalAverage, padd1…padd5}. The current index
//          point. See RAIL-CAR-716-INDEX-MOCK below — the figure is fixed in
//          source and self-declares as a mock, so it is gated on `source`.
//    fuelSurchargeIndex.calculateSteppedFsc     EXISTS fuelSurchargeIndex.ts:27
//        → {dieselPrice, baselinePrice, dieselOverBaseCents, stepsAboveBase,
//          centsPerMile, mileage, fscPerCar, railcarCount, totalFsc}. EVERY
//          line of the derivation card is one of these fields — the view never
//          re-does the arithmetic, it renders the server's working. NOT CALLED
//          TODAY: its two identity inputs are absent. See RAIL-CAR-716-CARRIER-
//          MARK and RAIL-CAR-716-RAIL-MILEAGE.
//    fuelSurchargeIndex.generateFscSchedule     EXISTS fuelSurchargeIndex.ts:70
//        → {carrier, dieselPrice, centsPerMile, schedule:[{mileage,fscPerCar}]}
//          — the mileage breakpoints behind the "Schedule" CTA. NOT CALLED
//          TODAY, same two gaps; the CTA is an honest disable.
//    fuelManagement.getFuelTransactions         EXISTS fuelManagement.ts:403
//        → {transactions:[{id, vehicleId, driverId, stationName, gallons,
//          pricePerGallon, totalAmount, date}], total}. The ledger's gallons
//          and spend per unit. HIGHWAY SOURCE: `vehicleId` is an integer FK
//          into the highway `vehicles` table (:421 parseInt) — there is no
//          locomotive, consist or reporting-mark column on this row.
//    fuelManagement.getFuelEfficiencyRanking    EXISTS fuelManagement.ts:1208
//        → {rankings:[{rank,id,name,mpg,totalGallons,totalSpent,costPerMile,
//          transactions,trend}], fleetAvgMpg}. HIGHWAY SOURCE, AND NOT KEYED
//          THE WAY ITS INPUT CLAIMS: the resolver signature is
//          `.query(async ({ ctx }) => …` at :1214 — `input` is never read, so
//          `rankBy: "vehicle"` is silently discarded and the rows are ALWAYS
//          grouped by `fuelTransactions.driverId` (:1230). `id` is the driver
//          id and `name` is the literal "Driver <id>" (:1273-1274). Miles come
//          from `loads.distance` (highway truckload distance) or, for a driver
//          with no delivered load, from `gallons * 6.5` (:1256, :1264). The
//          ledger therefore lists HIGHWAY DRIVERS, not locomotive runs, and
//          says so on screen.
//    fuelManagement.getIdlingReport             EXISTS fuelManagement.ts:1526
//        → byVehicle[{vehicleId, idlingHours, fuelWasted, costWasted, pctIdle,
//          status}]. Drives the IDLE pill on a low-efficiency ledger row.
//    fuelManagement.getFuelSurchargeHistory     EXISTS fuelManagement.ts:1108
//        → {history:[{week, doePrice, surchargePerMile}], basePrice}. The
//          published surcharge series behind the staleness check.
//    railShipments.getRailFinancialSummary      EXISTS railShipments.ts:2487
//        → {settlements[], demurrage[]} — the rail money the peg lands in, and
//          the mileage anchor for the derivation when a settlement carries one.
//
//    STUB · named-gap RAIL-CAR-716-LOCO-MGA
//        There is NO per-locomotive gross-ton-mile accounting on disk.
//        VERIFIED ABSENT: grep for grossTonMile / gross_ton_mile / tonMiles /
//        gtm across railTariff.ts, railFreightAudit.ts, fuelManagement.ts and
//        railShipments.ts returns zero matches, and fuelTransactions is keyed
//        to vehicleId (highway units) with no locomotive / reporting-mark
//        column and no trailing-tonnage join. The gtm/gal column therefore
//        renders as an explicit unwired dash with a named-gap notice, and
//        NEVER as a computed number.
//    STUB · named-gap RAIL-CAR-716-INDEX-COUNTRY
//        currentDieselIndex returns a US EIA shape only (nationalAverage +
//        padd1…5, USD) with no currency field and no CA NRCan / MX CRE index.
//        The CA and MX tiles read as the regime they are; the money stays in
//        the active tile's currency and the screen says when a country's index
//        is not wired rather than converting a US number into pesos.
//    STUB · named-gap RAIL-CAR-716-CARRIER-MARK
//        VERIFIED ABSENT 2026-08-25: this screen has NO way to learn which
//        railroad the signed-in account actually is. `companies` carries no
//        scac / reportingMark / railCarrierId column, `users` carries no
//        carrier FK, and `railCarriers.reportingMark` (drizzle/schema.ts:11133)
//        is reachable only through `railShipments.carrierId` — i.e. only from
//        inside one specific shipment, which a carrier-seat operator standing
//        on a period-level money screen does not have. No procedure on disk
//        returns the CALLER's own mark; the nearest real org identity is a
//        plain company NAME (companies.getProfile → name), which is not a
//        reporting mark and cannot select a tariff.
//        The surcharge input `carrier` is a closed enum of six real Class I
//        marks with a server-side default (fuelSurchargeIndex.ts:30), so there
//        is no neutral value to send and omitting it does not help — the server
//        picks one anyway and echoes it back as the tariff the tenant is billed
//        under. Sending any of them would attribute a published tariff position
//        to a real railroad the tenant may have no relationship with, so the
//        procedure is NOT CALLED and the derivation is not drawn at all.
//    STUB · named-gap RAIL-CAR-716-RAIL-MILEAGE
//        VERIFIED ABSENT 2026-08-25: there is no locomotive-keyed distance on
//        disk. Every mileage this screen can reach resolves to highway data —
//        see the getFuelEfficiencyRanking and getFuelTrendAnalysis notes above.
//        A highway distance is not a rail billing basis at any level of
//        disclosure: the number is not merely mislabelled, it measures a
//        different vehicle over a different network. It is therefore DISCLOSED
//        where it is displayed (the ledger, the hero) and REFUSED where it
//        would be billed (the surcharge mileage), rather than annotated and
//        billed anyway.
//    STUB · named-gap RAIL-CAR-716-IDLE-JOIN
//        getIdlingReport keys its rows to `vehicles.id`, emitted as "V007"
//        (fuelManagement.ts:1584); getFuelEfficiencyRanking keys its rows to
//        `fuelTransactions.driverId` (:1273). Neither payload carries the
//        other's key, so the ledger's status pill had been joining a driver to
//        an unrelated vehicle by matching digits. No verdict is drawn from it
//        now. The report's numbers are in any case a declared placeholder
//        ("placeholder until ELD integration", :1561): idling is modelled as
//        15% of a gallons-derived engine-hour estimate, which pins pctIdle to
//        15 and status to "acceptable" for every row on every fleet — so the
//        green "IN SERVICE" the pill used to show was a constant wearing the
//        colour of a measurement, not an observation.
//    STUB · named-gap RAIL-CAR-716-INDEX-MOCK
//        currentDieselIndex returns a fixed nationalAverage (fuelSurchargeIndex
//        .ts:64) under the source string "EIA retail diesel average (mock)"
//        (:62). A fixed number is not a DOE/EIA publication and is never drawn
//        as one: the country tile is gated on `source` and reads "unpublished"
//        until the procedure names a real publisher.
//
//    Writers: none today — every read above is a query. "Post MGA period" is
//        the proposed money-moving commit. When it lands it must write the MGA
//        period row + a blockchainAuditTrail row eventType rail.mga_period_posted
//        and broadcast WS_EVENTS.RAIL_CONSIST_UPDATE (websocket-events.ts:411)
//        on WS_CHANNELS.RAIL_DISPATCH (websocket-events.ts:623).
//    RBAC: protectedProcedure (companyId-scoped) on the fuel family;
//        railCommercialReadProcedure (railShipments.ts:130) on the rail
//        financial read — RAIL_SHIPPER · RAIL_CATALYST · RAIL_BROKER ·
//        RAIL_DISPATCHER · RAIL_ENGINEER · FACTORING · COMPLIANCE_OFFICER ·
//        ADMIN · SUPER_ADMIN. (Corrected 2026-08-25: this block had named
//        railReadProcedure at :94, which is not the guard on this procedure.)
//    OFFLINE: READ_CACHED(6h) for the chart and the ledger — the EIA index
//        publishes weekly, so a cached burn series is honest for hours and the
//        staleness line says exactly how old it is. Posting an MGA period is
//        ONLINE_ONLY: it fixes the gallons and miles a surcharge is billed
//        from, so a queued replay could bill a period twice or bill it against
//        a superseded index. Money movement is never queued.
//    NAV (carrier family): HOME · SHIPMENTS · [orb] · COMPLIANCE · ME(current).
//
//  ── S13 · SERVER-SIDE MONEY DEFECT · VERIFIED IN SOURCE 2026-08-25 ─────────
//    frontend/server/routers/fuelSurchargeIndex.ts:38
//        const fscPerCar = input.mileage * centsPerMile;
//    `centsPerMile` (:37) is steps × CENTS_PER_MILE_STEP — a rate in CENTS per
//    mile. The product is returned as fscPerCar (:50) and totalFsc (:52) in
//    DOLLARS with no ÷100, so every FSC amount this screen receives from
//    calculateSteppedFsc is overstated by a factor of one hundred.
//    generateFscSchedule repeats the same arithmetic at :83, so the mileage
//    breakpoints behind the "Schedule" CTA carry it too.
//    The fix belongs on the SERVER and is not made here. The client does NOT
//    divide by 100: patching it on this side would conceal the defect and put
//    the two halves of the system into silent disagreement. Instead every
//    amount derived from that arithmetic is presented — and ANNOUNCED — as
//    UNVERIFIED and not billable, while the ¢/mi rate, the diesel index and
//    the baseline (all unaffected) continue to read normally.
//    Unaffected: centsPerMile, dieselPrice, baselinePrice, dieselOverBaseCents,
//    stepsAboveBase, nationalAverage.
//    When :38 and :83 are corrected, flip `fscTotalsUnverified` to false and
//    the provisional treatment retires with it.
//    RE-VERIFIED 2026-08-25 (fire 17): :38 and :83 are UNCHANGED on disk — the
//    ÷100 is still missing and `fscTotalsUnverified` stays true. It is now a
//    dormant gate rather than a live one, because the two procedures behind it
//    are no longer called at all (see RAIL-CAR-716-CARRIER-MARK and
//    RAIL-CAR-716-RAIL-MILEAGE). Fixing :38 and :83 alone does NOT re-enable
//    this card: the basis was wrong before the arithmetic was, and both gaps
//    have to close before a surcharge may be drawn here.
//
//  ── S16 · ACCESSIBILITY (added 2026-08-25) ────────────────────────────────
//    Labels on every control and information-bearing composite; the disabled
//    post CTA announces WHY; currency is announced in full with its code, never
//    as a bare number; a provisional amount says it is provisional in its
//    accessibility value and not only on screen. The tri-country tiles were
//    30pt against the 44pt floor and are raised.
//

import SwiftUI

// MARK: - Screen

struct RailCarrierFuelMGAScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailCarrierFuelMGABody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Flexible decode helpers (the wire mixes DECIMAL strings and numbers)

private func flex716Double<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
    if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
    if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
    return nil
}

private func flex716Int<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
    if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i }
    if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Int(s) }
    if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d) }
    return nil
}

// MARK: - Data shapes

/// `fuelManagement.getFuelTrendAnalysis` (:1672) — the hero's ONE tick.
private struct FuelTrendEnvelope716: Decodable {
    let trends: [FuelTrendPoint716]?
    let summary: FuelTrendSummary716?
}

private struct FuelTrendSummary716: Decodable {
    let avgPriceOverPeriod: Double?
    let priceDirection: String?
    let efficiencyDirection: String?

    enum CodingKeys: String, CodingKey { case avgPriceOverPeriod, priceDirection, efficiencyDirection }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        avgPriceOverPeriod  = flex716Double(c, .avgPriceOverPeriod)
        priceDirection      = try? c.decodeIfPresent(String.self, forKey: .priceDirection)
        efficiencyDirection = try? c.decodeIfPresent(String.self, forKey: .efficiencyDirection)
    }
}

private struct FuelTrendPoint716: Decodable, Identifiable {
    /// "2026-08"
    let month: String
    let avgPrice: Double?
    let totalGallons: Double?
    let totalCost: Double?
    let avgMpg: Double?
    let costPerMile: Double?

    var id: String { month }

    enum CodingKeys: String, CodingKey { case month, avgPrice, totalGallons, totalCost, avgMpg, costPerMile }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month        = (try? c.decode(String.self, forKey: .month)) ?? ""
        avgPrice     = flex716Double(c, .avgPrice)
        totalGallons = flex716Double(c, .totalGallons)
        totalCost    = flex716Double(c, .totalCost)
        avgMpg       = flex716Double(c, .avgMpg)
        costPerMile  = flex716Double(c, .costPerMile)
    }

    /// "AUG" — the mono x-axis tick. Derived from the decoded month string only.
    var shortLabel: String {
        let parts = month.split(separator: "-")
        guard parts.count >= 2, let m = Int(parts[1]), (1...12).contains(m) else { return month.uppercased() }
        return ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"][m - 1]
    }
}

/// `fuelSurchargeIndex.currentDieselIndex` (:56).
private struct DieselIndex716: Decodable {
    let source: String?
    let weekOf: String?
    let nationalAverage: Double?
    let padd1: Double?
    let padd2: Double?
    let padd3: Double?
    let padd4: Double?
    let padd5: Double?

    enum CodingKeys: String, CodingKey {
        case source, weekOf, nationalAverage, padd1, padd2, padd3, padd4, padd5
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source          = try? c.decodeIfPresent(String.self, forKey: .source)
        weekOf          = try? c.decodeIfPresent(String.self, forKey: .weekOf)
        nationalAverage = flex716Double(c, .nationalAverage)
        padd1 = flex716Double(c, .padd1); padd2 = flex716Double(c, .padd2)
        padd3 = flex716Double(c, .padd3); padd4 = flex716Double(c, .padd4)
        padd5 = flex716Double(c, .padd5)
    }
}

/// `fuelSurchargeIndex.calculateSteppedFsc` (:27) — the whole derivation card.
private struct SteppedFsc716: Decodable {
    let carrier: String?
    let method: String?
    let dieselPrice: Double?
    let baselinePrice: Double?
    let dieselOverBaseCents: Int?
    let stepsAboveBase: Int?
    let centsPerMile: Double?
    let mileage: Double?
    let fscPerCar: Double?
    let railcarCount: Int?
    let totalFsc: Double?

    enum CodingKeys: String, CodingKey {
        case carrier, method, dieselPrice, baselinePrice, dieselOverBaseCents
        case stepsAboveBase, centsPerMile, mileage, fscPerCar, railcarCount, totalFsc
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        carrier             = try? c.decodeIfPresent(String.self, forKey: .carrier)
        method              = try? c.decodeIfPresent(String.self, forKey: .method)
        dieselPrice         = flex716Double(c, .dieselPrice)
        baselinePrice       = flex716Double(c, .baselinePrice)
        dieselOverBaseCents = flex716Int(c, .dieselOverBaseCents)
        stepsAboveBase      = flex716Int(c, .stepsAboveBase)
        centsPerMile        = flex716Double(c, .centsPerMile)
        mileage             = flex716Double(c, .mileage)
        fscPerCar           = flex716Double(c, .fscPerCar)
        railcarCount        = flex716Int(c, .railcarCount)
        totalFsc            = flex716Double(c, .totalFsc)
    }
}

/// `fuelSurchargeIndex.generateFscSchedule` (:70).
private struct FscSchedule716: Decodable {
    let carrier: String?
    let dieselPrice: Double?
    let centsPerMile: Double?
    let schedule: [FscScheduleRow716]?
}

private struct FscScheduleRow716: Decodable, Identifiable {
    let mileage: Double
    let fscPerCar: Double
    var id: Double { mileage }

    enum CodingKeys: String, CodingKey { case mileage, fscPerCar }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mileage   = flex716Double(c, .mileage) ?? 0
        fscPerCar = flex716Double(c, .fscPerCar) ?? 0
    }
}

/// `fuelManagement.getFuelEfficiencyRanking` (:1208) — the ledger's spine.
private struct EfficiencyEnvelope716: Decodable {
    let rankings: [EfficiencyRow716]?
    let fleetAvgMpg: Double?
}

private struct EfficiencyRow716: Decodable, Identifiable {
    let rank: Int
    let id: String
    let name: String?
    let mpg: Double?
    let totalGallons: Double?
    let totalSpent: Double?
    let costPerMile: Double?
    let transactions: Int?
    let trend: String?

    enum CodingKeys: String, CodingKey {
        case rank, id, name, mpg, totalGallons, totalSpent, costPerMile, transactions, trend
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank         = flex716Int(c, .rank) ?? 0
        id           = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name         = try? c.decodeIfPresent(String.self, forKey: .name)
        mpg          = flex716Double(c, .mpg)
        totalGallons = flex716Double(c, .totalGallons)
        totalSpent   = flex716Double(c, .totalSpent)
        costPerMile  = flex716Double(c, .costPerMile)
        transactions = flex716Int(c, .transactions)
        trend        = try? c.decodeIfPresent(String.self, forKey: .trend)
    }

    /// HIGHWAY miles. This restates the server's own derivation (mpg × gallons)
    /// rather than guessing — but the server's mpg is itself
    /// `loads.distance ÷ gallons` for a highway driver, or a flat 6.5 fleet
    /// constant when that driver has no delivered load. So this is a truck
    /// distance, it is not a locomotive distance, and the ledger labels it
    /// "hwy mi". It is DISPLAYED with that label and is never used as a rail
    /// billing basis. nil when either factor is absent.
    var derivedMiles: Double? {
        guard let m = mpg, let g = totalGallons, m > 0, g > 0 else { return nil }
        return m * g
    }
}

/// `fuelManagement.getFuelTransactions` (:403).
private struct FuelTxEnvelope716: Decodable {
    let transactions: [FuelTx716]?
    let total: Int?
}

private struct FuelTx716: Decodable, Identifiable {
    let id: String
    let vehicleId: String?
    let stationName: String?
    let gallons: Double?
    let pricePerGallon: Double?
    let totalAmount: Double?
    let date: String?

    enum CodingKeys: String, CodingKey {
        case id, vehicleId, stationName, gallons, pricePerGallon, totalAmount, date
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        vehicleId      = try? c.decodeIfPresent(String.self, forKey: .vehicleId)
        stationName    = try? c.decodeIfPresent(String.self, forKey: .stationName)
        gallons        = flex716Double(c, .gallons)
        pricePerGallon = flex716Double(c, .pricePerGallon)
        totalAmount    = flex716Double(c, .totalAmount)
        date           = try? c.decodeIfPresent(String.self, forKey: .date)
    }
}

/// `fuelManagement.getIdlingReport` (:1526).
private struct IdlingEnvelope716: Decodable {
    let byVehicle: [IdlingRow716]?
}

private struct IdlingRow716: Decodable, Identifiable {
    let vehicleId: String
    let idlingHours: Double?
    let costWasted: Double?
    let pctIdle: Double?
    let status: String?

    var id: String { vehicleId }

    enum CodingKeys: String, CodingKey { case vehicleId, idlingHours, costWasted, pctIdle, status }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vehicleId   = (try? c.decode(String.self, forKey: .vehicleId)) ?? ""
        idlingHours = flex716Double(c, .idlingHours)
        costWasted  = flex716Double(c, .costWasted)
        pctIdle     = flex716Double(c, .pctIdle)
        status      = try? c.decodeIfPresent(String.self, forKey: .status)
    }

    /// Trailing digits of "V007" with leading zeros dropped — the join back to
    /// an efficiency row's id. Derived from decoded text only.
    var numericKey: String {
        let digits = vehicleId.filter(\.isNumber)
        let trimmed = String(digits.drop(while: { $0 == "0" }))
        return trimmed.isEmpty ? digits : trimmed
    }
}

/// `fuelManagement.getFuelSurchargeHistory` (:1108).
private struct FscHistoryEnvelope716: Decodable {
    let history: [FscHistoryRow716]?
    let basePrice: Double?
}

private struct FscHistoryRow716: Decodable, Identifiable {
    let week: String
    let doePrice: Double?
    let surchargePerMile: Double?
    var id: String { week }

    enum CodingKeys: String, CodingKey { case week, doePrice, surchargePerMile }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        week             = (try? c.decode(String.self, forKey: .week)) ?? ""
        doePrice         = flex716Double(c, .doePrice)
        surchargePerMile = flex716Double(c, .surchargePerMile)
    }
}

/// `railShipments.getRailFinancialSummary` (railShipments.ts:2487) — only what the mileage
/// anchor needs. Settlement rows carry the rail money the peg lands in.
private struct RailFinancial716: Decodable {
    let settlements: [RailSettlement716]?
}

private struct RailSettlement716: Decodable, Identifiable {
    let id: Int
    let railShipmentId: Int?
    let totalAmount: Double?
    let status: String?

    enum CodingKeys: String, CodingKey { case id, railShipmentId, totalAmount, status }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = flex716Int(c, .id) ?? 0
        railShipmentId = flex716Int(c, .railShipmentId)
        totalAmount    = flex716Double(c, .totalAmount)
        status         = try? c.decodeIfPresent(String.self, forKey: .status)
    }
}

// MARK: - Body

private struct RailCarrierFuelMGABody: View {
    @Environment(\.palette) private var palette

    /// The country tile is a real gate: it selects the index authority AND the
    /// currency every money figure below is formatted in.
    private enum Regime716: String, CaseIterable {
        case us = "US", ca = "CA", mx = "MX"
        var authority: String {
            switch self {
            case .us: return "US · DOE/EIA"
            case .ca: return "CA · NRCan"
            case .mx: return "MX · CRE"
            }
        }
        var currencyCode: String {
            switch self {
            case .us: return "USD"
            case .ca: return "CAD"
            case .mx: return "MXN"
            }
        }
        var indexNote: String {
            switch self {
            case .us: return "weekly retail"
            case .ca: return "weekly"
            case .mx: return "IEnova"
            }
        }
        /// Only the US index is on disk. RAIL-CAR-716-INDEX-COUNTRY.
        var indexWired: Bool { self == .us }
    }

    @State private var regime: Regime716 = .us

    @State private var trend: FuelTrendEnvelope716? = nil
    @State private var index: DieselIndex716? = nil
    @State private var fsc: SteppedFsc716? = nil
    @State private var schedule: FscSchedule716? = nil
    @State private var efficiency: EfficiencyEnvelope716? = nil
    @State private var transactions: [FuelTx716] = []
    @State private var idling: [IdlingRow716] = []
    @State private var fscHistory: FscHistoryEnvelope716? = nil
    @State private var financial: RailFinancial716? = nil

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var lastGoodTick: Date? = nil
    @State private var actionNotice: (text: String, ok: Bool)? = nil

    /// READ_CACHED(6h) — the EIA index publishes weekly, so a cached burn
    /// series is honest for hours. Past the TTL the chart says so and the
    /// money-moving CTA is disabled rather than fired at a stale index.
    private let cacheTTL: TimeInterval = 6 * 3600

    // MARK: Derived

    private var points: [FuelTrendPoint716] { trend?.trends ?? [] }

    private var staleSeconds: TimeInterval? { lastGoodTick.map { Date().timeIntervalSince($0) } }
    private var isStale: Bool { (staleSeconds ?? .greatestFiniteMagnitude) > cacheTTL }

    private var cacheChipText: String {
        guard let s = staleSeconds else { return "NO TICK" }
        let mins = Int(s / 60)
        return mins >= 1 ? "CACHED \(mins)m" : "CACHED \(Int(s))s"
    }

    /// The staleness line quotes the REAL publish week from currentDieselIndex
    /// and, when the persisted surcharge series has one, the last week the DOE
    /// price was actually written. Neither is ever invented.
    private var stalenessLine: String {
        let publish = index?.weekOf.map { "index wk \($0)" } ?? "index week unreported"
        let lastWritten = fscHistory?.history?.last?.week
        let tail = lastWritten.map { " · last publish \($0)" } ?? ""
        return "READ_CACHED(6h) · \(publish)\(tail)"
    }

    // MARK: Spoken forms of the composites above

    /// The cache chip is a terse token on screen; VoiceOver gets the sentence.
    private var cacheSpoken: String {
        guard let s = staleSeconds else { return "No read has landed yet." }
        let mins = Int(s / 60)
        let age = mins >= 1 ? "\(mins) minutes old" : "\(Int(s)) seconds old"
        return isStale
            ? "Cached \(age), past the six hour window."
            : "Cached \(age), within the six hour window."
    }

    /// Same facts as `stalenessLine`, said in words.
    private var stalenessSpoken: String {
        let publish = index?.weekOf.map { "index week of \($0)" } ?? "index week not reported"
        let lastWritten = fscHistory?.history?.last?.week
        let tail = lastWritten.map { ", last publish week of \($0)" } ?? ""
        return "Read from a six hour cache, \(publish)\(tail)."
    }

    /// The chart described from decoded points only — first and last period, the
    /// real gallon total, and the real index at each end. Absent values say so.
    private var chartSpoken: String {
        guard let first = points.first, let last = points.last else {
            return "No series is recorded."
        }
        var bits: [String] = ["\(points.count) months, \(first.shortLabel) through \(last.shortLabel)"]
        bits.append(totalGallons.map { "\(n($0)) highway fleet gallons in total" } ?? "total gallons not reported")
        bits.append(last.totalGallons.map { "\(n($0)) gallons in the current period" }
                    ?? "gallons for the current period not reported")
        bits.append(first.avgPrice.map { "price paid opens at \(spokenPerGallon($0))" } ?? "opening price not reported")
        bits.append(last.avgPrice.map { "price paid closes at \(spokenPerGallon($0))" } ?? "closing price not reported")
        return bits.joined(separator: ". ") + "."
    }

    /// Gallons per VEHICLE straight off the fuel transactions. Correctly keyed
    /// to `fuelTransactions.vehicleId`, and therefore NOT usable as a fallback
    /// for a ledger row, whose key is a driverId — see the note in `ledgerRow`
    /// and RAIL-CAR-716-IDLE-JOIN. Left in place, correctly keyed, for the day
    /// a payload carries both keys; it feeds nothing on screen today.
    private var gallonsByVehicle: [String: Double] {
        var m: [String: Double] = [:]
        for t in transactions {
            guard let v = t.vehicleId, let gal = t.gallons else { continue }
            m[v, default: 0] += gal
        }
        return m
    }

    private var totalGallons: Double? {
        let g = points.compactMap(\.totalGallons)
        return g.isEmpty ? nil : g.reduce(0, +)
    }

    /// The subline names the SOURCE, because the source is not what a rail MGA
    /// screen implies. It carried an invented division name until fire 17; this
    /// account has no railroad reporting mark and no rail division on file
    /// (RAIL-CAR-716-CARRIER-MARK), so no identity is asserted here at all.
    private var subline: String {
        var bits = ["Highway fleet fuel"]
        bits.append(points.isEmpty ? "no burn recorded" : "\(points.count) mo")
        if let gal = totalGallons { bits.append("\(intFmt.string(from: NSNumber(value: gal)) ?? "—") gal") }
        if let cpm = fsc?.centsPerMile { bits.append("peg \(cpmFmt.string(from: NSNumber(value: cpm)) ?? "-")¢/mi") }
        return bits.joined(separator: " · ")
    }

    // MARK: Formatters — currency follows the ACTIVE country tile

    private var money: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = regime.currencyCode
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }
    private var perGallon: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = regime.currencyCode
        f.maximumFractionDigits = 3
        f.minimumFractionDigits = 3
        return f
    }
    private var intFmt: NumberFormatter {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }
    private var cpmFmt: NumberFormatter {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.minimumFractionDigits = 3; f.maximumFractionDigits = 3; return f
    }
    private func m(_ v: Double?) -> String {
        guard let v else { return "—" }
        return money.string(from: NSNumber(value: v)) ?? "—"
    }
    private func g(_ v: Double?) -> String {
        guard let v else { return "—" }
        return perGallon.string(from: NSNumber(value: v)) ?? "—"
    }
    private func n(_ v: Double?) -> String {
        guard let v else { return "—" }
        return intFmt.string(from: NSNumber(value: v)) ?? "—"
    }
    /// The published cents-per-mile rate, formatted — or NIL when the server did
    /// not send one. The rate is the one figure the S13 notice certifies as
    /// unaffected, so an omitted rate is never coerced to 0.000: callers render
    /// the absence instead. See the `if let cpm` guard in `derivationLines`.
    private func cpm(_ v: Double?) -> String? {
        guard let v else { return nil }
        return cpmFmt.string(from: NSNumber(value: v))
    }

    // MARK: Honesty gate — S13

    /// TRUE while the server returns a cents-per-mile product as dollars.
    /// See the S13 block in the file header for the exact file and line. While
    /// this holds, no amount derived from calculateSteppedFsc or
    /// generateFscSchedule is presented or announced as a confirmed charge.
    /// Flip to false only when the server arithmetic is corrected.
    private var fscTotalsUnverified: Bool { true }

    // MARK: Honesty gates — the inputs the derivation is not allowed to invent

    /// The railroad reporting mark this account's surcharge would be billed
    /// under. RAIL-CAR-716-CARRIER-MARK: there is no tenant-scoped source for
    /// it on disk, so it is nil and the derivation is not drawn. A mark chosen
    /// by the client would put a real railroad's published tariff position on a
    /// tenant that never agreed to it, which is the one substitution this
    /// screen may never make. When a `companies → railCarriers` link lands,
    /// return the real mark here and the card resumes on its own.
    private var carrierReportingMark: String? { nil }

    /// The RAIL distance a surcharge would be billed against.
    /// RAIL-CAR-716-RAIL-MILEAGE: nothing on disk is keyed to a locomotive.
    /// The miles this screen can reach are highway-fleet miles — a truck
    /// odometer over a road network, or a flat 6.5 mpg constant where even that
    /// is missing. Those miles are shown, labelled as what they are, in the
    /// ledger; they are NOT handed to the surcharge, because relabelling a
    /// number does not make it the right number to bill from.
    private var railBillingMileage: Double? { nil }

    /// TRUE only when the index procedure names a real publisher.
    /// RAIL-CAR-716-INDEX-MOCK: `currentDieselIndex` returns a fixed national
    /// average and self-declares as a mock in its own `source` string, so the
    /// figure is not a DOE/EIA publication and is never drawn as one.
    private var indexPublished: Bool {
        guard let s = index?.source?.lowercased(), !s.isEmpty else { return false }
        return !s.contains("mock") && !s.contains("sample") && !s.contains("placeholder")
    }

    /// Why no surcharge is drawn, naming every input that is missing rather
    /// than one generic "unavailable". SUPPRESS THE VERDICT: the card keeps its
    /// place in the composition and states what cannot be judged and why.
    private var derivationUnavailableReason: String {
        var missing: [String] = []
        if carrierReportingMark == nil {
            missing.append("this account has no railroad reporting mark on file, so there is no published tariff to derive against")
        }
        if railBillingMileage == nil {
            missing.append("no locomotive-keyed mileage is recorded — the miles on this screen are highway fleet miles and are not a rail billing basis")
        }
        if !regime.indexWired {
            missing.append("the \(regime.rawValue) diesel index is not wired")
        } else if !indexPublished {
            missing.append("the diesel index feed is not a published figure")
        }
        guard !missing.isEmpty else {
            return "No surcharge peg is recorded for this period, so there is no calculation to show."
        }
        return "No fuel surcharge is derived here, because "
            + missing.joined(separator: "; ")
            + ". Contact rail finance for the surcharge actually billed."
    }

    // MARK: Spoken money — a money screen must be unambiguous to VoiceOver

    /// VoiceOver gets the amount AND its currency code, never a bare number.
    /// A figure the screen cannot vouch for says so in the same breath.
    private func spokenMoney(_ v: Double?, unverified: Bool = false) -> String {
        guard let v else { return "amount not reported" }
        let amount = money.string(from: NSNumber(value: v)) ?? "\(v)"
        let base = "\(amount) \(regime.currencyCode)"
        guard unverified else { return base }
        return base + ". Unverified — this amount is not billable as shown."
    }

    /// Per-gallon prices spoken with their currency and unit.
    private func spokenPerGallon(_ v: Double?) -> String {
        guard let v else { return "price not reported" }
        let amount = perGallon.string(from: NSNumber(value: v)) ?? "\(v)"
        return "\(amount) \(regime.currencyCode) per gallon"
    }

    /// The house separator "·" and the em dash read as symbols. Spoken strings
    /// swap them so a combined composite reads as one sentence. Never changes
    /// what is displayed — only how it is announced.
    private func spoken(_ s: String) -> String {
        s.replacingOccurrences(of: " · ", with: ", ")
         .replacingOccurrences(of: "hwy mi", with: "highway miles")
         .replacingOccurrences(of: "gtm/gal", with: "gross ton-miles per gallon")
         .replacingOccurrences(of: " ¢/mi", with: " cents per mile")
         .replacingOccurrences(of: "¢/mi", with: " cents per mile")
         .replacingOccurrences(of: " /gal", with: " per gallon")
         .replacingOccurrences(of: "/gal", with: " per gallon")
         .replacingOccurrences(of: "¢", with: " cents")
         .replacingOccurrences(of: "−", with: "minus ")
         .replacingOccurrences(of: "×", with: "times")
         .replacingOccurrences(of: "÷", with: "divided by")
         .replacingOccurrences(of: "→", with: "to")
         .replacingOccurrences(of: "—", with: "not reported")
    }

    // MARK: View

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline()

                if loading && points.isEmpty && fsc == nil {
                    LifecycleCard {
                        Text("Loading the fuel series…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Loading the fuel series")
                } else if let err = loadError, points.isEmpty, fsc == nil {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Fuel and MGA unavailable")
                    .accessibilityValue(err)
                } else {
                    comboChartHero
                    highwayBasisNotice
                    if let a = actionNotice { noticeCard(a) }
                    // Grouped so this block stays inside ViewBuilder's ten-child
                    // limit; Group is transparent to the stack's spacing.
                    Group {
                        sectionLabel("FUEL LEDGER · HIGHWAY FLEET, BY DRIVER",
                                     trailing: "hwy mi · gallons · gtm/gal")
                        ledgerCard
                        gtmGapNotice
                    }
                    sectionLabel("SURCHARGE DERIVATION",
                                 trailing: fsc == nil ? "not derived" : "index → peg → step → ¢/mi")
                    derivationCard
                    triCountryBand
                    onlineOnlyNote
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Text("✦").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                .accessibilityHidden(true)
            Text("RAIL CARRIER · FUEL AND MGA")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer(minLength: 0)
            Text(points.last.map { "MGA · PERIOD \($0.month)" } ?? "MGA · NO PERIOD")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).monospaced()
                .foregroundStyle(palette.textTertiary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rail carrier, fuel and mileage and gallonage accounting")
        .accessibilityValue(points.last.map { "Accounting period \($0.month)" } ?? "No accounting period recorded")
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .accessibilityHidden(true)
                Text("Fuel and MGA")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityHidden(true)
            }
            Text(subline)
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 27)
                .accessibilityLabel("Period summary")
                .accessibilityValue(spoken(subline))
        }
    }

    // MARK: HERO — combo column + step chart
    //
    // Both series come from ONE getFuelTrendAnalysis tick: totalGallons draws
    // the columns against the LEFT axis, avgPrice draws the step line against
    // the RIGHT (second implied) axis. The current period's column is inked in
    // the house gradient; every other column is neutral.

    private var comboChartHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HIGHWAY FLEET GALLONS vs PRICE PAID · \(points.count) MONTHS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(Brand.info)
                Spacer(minLength: 8)
                Text(cacheChipText)
                    .font(.system(size: 10, weight: .heavy)).kerning(0.3)
                    .foregroundStyle(isStale ? Brand.danger : Brand.warning)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill((isStale ? Brand.danger : Brand.warning).opacity(0.16)))
            }
            .padding(.horizontal, 16).frame(height: 38)
            .background(LinearGradient(colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.06)],
                                       startPoint: .leading, endPoint: .trailing))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Highway fleet gallons versus price paid, \(points.count) months")
            .accessibilityValue(cacheSpoken)
            .accessibilityAddTraits(.isHeader)

            if points.isEmpty {
                // Degraded: axes without invented columns. A flat zero series
                // would read as "we burned nothing", which is a different and
                // false claim.
                VStack(alignment: .leading, spacing: 6) {
                    Text("No fuel recorded for this period")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("No highway fleet fuel transactions are recorded for this period, so the chart remains empty. There is no rail fuel series on file to draw instead.")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.vertical, 22)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No fuel recorded for this period")
                .accessibilityValue("No highway fleet fuel transactions are recorded for this period, so the chart remains empty. There is no rail fuel series on file to draw instead.")
            } else {
                chartPlot.frame(height: 116).padding(.horizontal, 14).padding(.top, 10)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Combined chart, monthly highway fleet gallons as columns with the average price the fleet paid at the pump drawn over them as a step line. This is not a published diesel index.")
                    .accessibilityValue(chartSpoken)
                xAxis.padding(.horizontal, 14).padding(.top, 6)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(palette.textPrimary.opacity(0.16))
                    .frame(width: 12, height: 6)
                    .accessibilityHidden(true)
                Text("hwy gallons").font(.system(size: 8)).foregroundStyle(palette.textSecondary)
                Rectangle().fill(Brand.info).frame(width: 16, height: 2).padding(.leading, 8)
                    .accessibilityHidden(true)
                Text("price paid \(regime.currencyCode)/gal")
                    .font(.system(size: 8)).foregroundStyle(palette.textSecondary)
                Spacer(minLength: 4)
                Text(stalenessLine)
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(isStale ? Brand.danger : Brand.warning)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Chart legend. Columns are highway fleet gallons, the step line is the average price the fleet paid in \(regime.currencyCode) per gallon — not a published index.")
            .accessibilityValue(stalenessSpoken + (isStale ? " The cached series is past its six hour window." : ""))
        }
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private var gallonMax: Double { max(points.compactMap(\.totalGallons).max() ?? 1, 1) }
    private var priceLo: Double {
        let p = points.compactMap(\.avgPrice)
        return (p.min() ?? 0) - 0.05
    }
    private var priceHi: Double {
        let p = points.compactMap(\.avgPrice)
        return max((p.max() ?? 1) + 0.05, priceLo + 0.01)
    }

    private var chartPlot: some View {
        HStack(alignment: .top, spacing: 6) {
            // LEFT axis — gallons, mono
            VStack(alignment: .trailing, spacing: 0) {
                Text(n(gallonMax)).font(.system(size: 8, design: .monospaced)).monospacedDigit()
                Spacer()
                Text(n(gallonMax / 2)).font(.system(size: 8, design: .monospaced)).monospacedDigit()
                Spacer()
                Text("0").font(.system(size: 8, design: .monospaced)).monospacedDigit()
            }
            .foregroundStyle(palette.textTertiary)
            .frame(width: 42, alignment: .trailing)

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let pitch = w / CGFloat(max(points.count, 1))
                let barW = max(pitch * 0.6, 4)
                ZStack(alignment: .bottomLeading) {
                    // Gridlines + baseline
                    VStack(spacing: 0) {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                        Spacer()
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                        Spacer()
                        Rectangle().fill(palette.borderSoft).frame(height: 1)
                    }
                    // Columns — current period inked in the gradient.
                    ForEach(Array(points.enumerated()), id: \.element.id) { pair in
                        let i = pair.offset
                        let v = pair.element.totalGallons ?? 0
                        let bh = CGFloat(v / gallonMax) * (h - 2)
                        let isCurrent = i == points.count - 1
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isCurrent
                                  ? AnyShapeStyle(LinearGradient.diagonal)
                                  : AnyShapeStyle(palette.textPrimary.opacity(0.16)))
                            .frame(width: barW, height: max(bh, 1))
                            .offset(x: pitch * CGFloat(i) + (pitch - barW) / 2, y: 0)
                    }
                    // Step line on the SECOND implied axis.
                    stepPath(w: w, h: h)
                        .stroke(Brand.info, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    if let last = points.last?.avgPrice {
                        let y = h - CGFloat((last - priceLo) / (priceHi - priceLo)) * h
                        Circle().fill(Brand.info).frame(width: 7, height: 7)
                            .offset(x: w - 4, y: y - h + 3.5)
                    }
                }
            }

            // RIGHT axis — the price the fleet paid per gallon, mono. Not an
            // index: these are the company's own fuel-card prices.
            VStack(alignment: .leading, spacing: 0) {
                Text(g(priceHi)).font(.system(size: 8, design: .monospaced)).monospacedDigit()
                Spacer()
                Text(g((priceHi + priceLo) / 2)).font(.system(size: 8, design: .monospaced)).monospacedDigit()
                Spacer()
                Text(g(priceLo)).font(.system(size: 8, design: .monospaced)).monospacedDigit()
            }
            .foregroundStyle(palette.textTertiary)
            .frame(width: 46, alignment: .leading)
        }
    }

    /// A true step: one horizontal run per period, a riser between periods.
    private func stepPath(w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        guard !points.isEmpty, priceHi > priceLo else { return p }
        let pitch = w / CGFloat(points.count)
        for (i, pt) in points.enumerated() {
            guard let v = pt.avgPrice else { continue }
            let y = h - CGFloat((v - priceLo) / (priceHi - priceLo)) * h
            let x0 = pitch * CGFloat(i)
            let x1 = pitch * CGFloat(i + 1)
            if p.isEmpty { p.move(to: CGPoint(x: x0, y: y)) } else { p.addLine(to: CGPoint(x: x0, y: y)) }
            p.addLine(to: CGPoint(x: x1, y: y))
        }
        return p
    }

    private var xAxis: some View {
        GeometryReader { geo in
            let pitch = geo.size.width / CGFloat(max(points.count, 1))
            ZStack(alignment: .topLeading) {
                ForEach(Array(points.enumerated()), id: \.element.id) { pair in
                    let i = pair.offset
                    if i == points.count - 1 || i % 3 == 0 {
                        Text(pair.element.shortLabel)
                            .font(.system(size: 7.5,
                                          weight: i == points.count - 1 ? .heavy : .regular,
                                          design: .monospaced))
                            .foregroundStyle(i == points.count - 1 ? palette.textPrimary : palette.textTertiary)
                            .frame(width: pitch)
                            .offset(x: pitch * CGFloat(i))
                    }
                }
            }
        }
        .frame(height: 12)
        .padding(.leading, 48).padding(.trailing, 52)
    }

    // MARK: Fuel ledger — highway fleet, by driver

    /// One row per HIGHWAY DRIVER that burned fuel this period. The ranking
    /// procedure discards its `rankBy` input and always groups the highway
    /// fuel-card table by driverId, so these are not units and not locomotive
    /// runs; the section label and every row say so. Miles restate the server's
    /// own mpg × gallons and are labelled "hwy mi"; gtm/gal is the named gap
    /// and is drawn as an explicit dash.
    private var ledgerRows: [EfficiencyRow716] {
        Array((efficiency?.rankings ?? []).prefix(3))
    }

    /// The empty state says WHICH source is empty, and separately that the rail
    /// source it is standing in for does not exist. An empty highway ledger is
    /// not evidence that no locomotive burned fuel — nothing on file could ever
    /// have told us that.
    private let ledgerEmptyCopy =
        "No highway fleet fuel transactions are recorded for this period. This ledger reads the highway fuel-card table; there is no locomotive-keyed fuel source on file, so it cannot report on locomotive burn either way."

    private var ledgerCard: some View {
        Group {
            if ledgerRows.isEmpty {
                LifecycleCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No fuel ledger rows for this period")
                            .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Text(ledgerEmptyCopy)
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No fuel ledger rows for this period")
                .accessibilityValue(ledgerEmptyCopy)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ledgerRows.enumerated()), id: \.element.id) { pair in
                        ledgerRow(pair.element)
                        if pair.offset < ledgerRows.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.horizontal, 16)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .padding(.vertical, 10)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Highway fleet fuel ledger, \(ledgerRows.count) driver\(ledgerRows.count == 1 ? "" : "s"). These are highway fuel-card rows, not locomotive runs.")
            }
        }
    }

    /// SUPPRESS THE VERDICT · RAIL-CAR-716-IDLE-JOIN.
    /// This join cannot be made correctly and is no longer attempted.
    /// `getIdlingReport` keys its rows to `vehicles.id`, emitted as "V007"
    /// (fuelManagement.ts:1584), while these ledger rows are keyed to
    /// `fuelTransactions.driverId` (:1273). Matching the digits of one against
    /// the digits of the other pairs driver 7 with vehicle V007 — two unrelated
    /// records — and then states a service verdict about the wrong thing.
    /// There is no driver→vehicle key on either payload, so no verdict is drawn
    /// and the pill reports the absence instead. The report's own numbers are
    /// in any case a declared placeholder (idling is modelled as 15% of an
    /// engine-hour estimate, which pins every row to "acceptable"), so a green
    /// "IN SERVICE" here was a fixed value wearing the colour of a measurement.
    private func idlingFor(_ row: EfficiencyRow716) -> IdlingRow716? { nil }

    private func ledgerRow(_ row: EfficiencyRow716) -> some View {
        let idle = idlingFor(row)
        let excessive = (idle?.status ?? "").lowercased() == "excessive"
        let idleKnown = idle != nil
        let pillColor: Color = idleKnown ? (excessive ? Brand.warning : Brand.success)
                                         : palette.textTertiary
        let pillText: String = {
            guard idleKnown else { return "IDLE UNKNOWN" }
            if excessive, let p = idle?.pctIdle { return "IDLE \(Int(p))%" }
            if excessive { return "IDLE HIGH" }
            return "IN SERVICE"
        }()
        // Gallons: the ranking's own total for this driver, or nothing.
        // The per-vehicle fallback that used to sit here looked `row.id` up in
        // `gallonsByVehicle` — but `row.id` is a driverId and that map is keyed
        // by vehicleId, so it could hand this driver a different vehicle's
        // gallons whenever the two integers happened to coincide. Same defect
        // as RAIL-CAR-716-IDLE-JOIN; the fallback is gone rather than guarded,
        // because there is no key on either payload that would make it right.
        let gallons = row.totalGallons
        let sub: String = {
            var bits: [String] = []
            // "hwy mi" — DISCLOSE THE BASIS. These are highway-fleet miles from
            // the truck fuel-card table, never locomotive miles.
            bits.append(row.derivedMiles.map { "\(n($0)) hwy mi" } ?? "miles unreported")
            bits.append(gallons.map { "\(n($0)) gal" } ?? "gallons unreported")
            return bits.joined(separator: " · ")
        }()
        // Spoken form: units said in full, the pill said as a sentence, and the
        // named gap said out loud instead of read as a bare dash.
        let spokenSub: String = {
            var bits: [String] = []
            bits.append(row.derivedMiles.map { "\(n($0)) highway miles" } ?? "miles unreported")
            bits.append(gallons.map { "\(n($0)) gallons" } ?? "gallons unreported")
            return bits.joined(separator: ", ")
        }()
        let spokenPill: String = {
            guard idleKnown else {
                return "Idling unknown. The idling report is keyed to vehicles and this row is keyed to a driver, so there is no way to tell which record belongs to this row and no service state is claimed"
            }
            if excessive, let p = idle?.pctIdle {
                return "Idling \(Int(p)) percent of the time, flagged excessive"
            }
            if excessive { return "Idling flagged excessive" }
            return "In service"
        }()

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name ?? "Fleet driver \(row.id)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(sub)
                    .font(.system(size: 10, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            // Pill in its own column — it can never reach the numeric column.
            Text(pillText)
                .font(.system(size: 9, weight: .heavy)).kerning(0.3)
                .foregroundStyle(pillColor)
                .padding(.horizontal, 9).frame(height: 18)
                .background(Capsule().fill(pillColor.opacity(0.14)))
                .fixedSize()
            VStack(alignment: .trailing, spacing: 1) {
                // STUB · RAIL-CAR-716-LOCO-MGA — no gross-ton-mile source.
                Text("—")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                Text("gtm/gal")
                    .font(.system(size: 8.5, weight: .bold)).kerning(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
            .fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name ?? "Fleet driver \(row.id)")
        .accessibilityValue("\(spokenSub). \(spokenPill). Gross ton-miles per gallon unavailable.")
    }

    /// DISCLOSE THE BASIS · RAIL-CAR-716-RAIL-MILEAGE.
    /// The one line this screen owes the operator: what they are actually
    /// looking at, and what follows from it. It names the substitution (highway
    /// fuel-card data standing where rail data would be), the key it is
    /// recorded against (driver, not locomotive), and the consequence (no
    /// surcharge is derived from it). It sits directly under the hero so it is
    /// read before any number below it.
    private let highwayBasisCopy =
        "Every figure on this screen comes from the highway fleet fuel-card table. Gallons and prices are the fleet's own transactions, and the miles are highway miles recorded against a driver — there is no locomotive, consist or reporting-mark column anywhere in this data. Nothing here measures rail fuel burn, and none of it is used to derive a rail fuel surcharge."

    private var highwayBasisNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("SOURCE · HIGHWAY FLEET FUEL, NOT RAIL")
                    .font(.system(size: 9, weight: .heavy)).kerning(0.5)
                    .foregroundStyle(Brand.warning)
                Text(highwayBasisCopy)
                    .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.warning.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.warning.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source, highway fleet fuel, not rail")
        .accessibilityValue(highwayBasisCopy)
    }

    private var gtmGapNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textTertiary)
                .accessibilityHidden(true)
            Text("Gross-ton-mile efficiency is unavailable because fuel transactions do not include locomotive reporting marks or trailing tonnage. The value remains blank.")
                .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderSoft))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gross-ton-mile efficiency unavailable")
        .accessibilityValue("Fuel transactions do not include locomotive reporting marks or trailing tonnage. The value remains blank.")
    }

    // MARK: Surcharge derivation — the screen shows its work

    /// Every line is a FIELD from calculateSteppedFsc. The view restates the
    /// server's arithmetic; it never performs it.
    private var derivationLines: [(String, String)] {
        guard let f = fsc else { return [] }
        var out: [(String, String)] = []
        let wk = index?.weekOf.map { " · wk \($0)" } ?? ""
        out.append(("\(regime.authority.replacingOccurrences(of: "\(regime.rawValue) · ", with: "")) retail diesel\(wk)",
                    "\(g(f.dieselPrice)) /gal"))
        if let b = f.baselinePrice {
            out.append(("less \(f.carrier ?? "carrier") published base", "−\(g(b)) /gal"))
        }
        if let cents = f.dieselOverBaseCents, let steps = f.stepsAboveBase {
            out.append(("over base \(cents)¢ ÷ step", "\(steps) steps"))
        }
        if let steps = f.stepsAboveBase, let cpm = f.centsPerMile {
            out.append(("\(steps) steps × 0.01¢/mi per step",
                        "\(cpmFmt.string(from: NSNumber(value: cpm)) ?? "—") ¢/mi"))
        }
        return out
    }

    /// The closing line's left half. When the carrier's cents-per-mile rate is
    /// absent the line says so — it is never printed as 0.000¢/mi, which would
    /// state a rate the server never sent.
    private func fscClosingLine(_ f: SteppedFsc716) -> String {
        guard let rate = cpm(f.centsPerMile) else {
            return "FSC · \(n(f.mileage)) mi · rate not reported"
        }
        return "FSC · \(n(f.mileage)) mi × \(rate)¢/mi"
    }

    /// The same line spoken, so VoiceOver hears the same absence the screen
    /// shows rather than a confirmed zero rate.
    private func fscClosingSpoken(_ f: SteppedFsc716) -> String {
        guard let rate = cpm(f.centsPerMile) else {
            return "Fuel surcharge for \(n(f.mileage)) miles. The cents-per-mile rate is not reported."
        }
        return "Fuel surcharge for \(n(f.mileage)) miles at \(rate) cents per mile"
    }

    private var derivationCard: some View {
        Group {
            if let f = fsc, !derivationLines.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("\(f.carrier ?? "CARRIER") STEPPED SCHEDULE · \(n(f.mileage)) mi · \(f.railcarCount ?? 1) car")
                            .font(.system(size: 9, weight: .heavy)).kerning(0.6)
                            .foregroundStyle(palette.textTertiary).lineLimit(1)
                        Spacer()
                        Text(regime.currencyCode)
                            .font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(0.6)
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(f.carrier ?? "Carrier") stepped schedule")
                    .accessibilityValue("\(n(f.mileage)) miles, \(f.railcarCount ?? 1) car, amounts in \(regime.currencyCode)")
                    .accessibilityAddTraits(.isHeader)

                    Divider().overlay(palette.borderFaint).padding(.horizontal, 16)
                        .accessibilityHidden(true)

                    VStack(spacing: 6) {
                        ForEach(Array(derivationLines.enumerated()), id: \.offset) { pair in
                            HStack(alignment: .firstTextBaseline) {
                                Text(pair.element.0).font(.system(size: 10.5))
                                    .foregroundStyle(palette.textSecondary).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(pair.element.1)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .monospacedDigit().foregroundStyle(palette.textPrimary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(spoken(pair.element.0))
                            .accessibilityValue(spoken(pair.element.1))
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 10)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Surcharge working, \(derivationLines.count) lines")

                    // The rule. A money screen closes its working with a line.
                    Rectangle().fill(palette.borderSoft).frame(height: 1)
                        .padding(.horizontal, 16).padding(.top, 12)
                        .accessibilityHidden(true)

                    // S13 · the closing amount is the ONE figure the server
                    // defect lands on. It keeps its place in the composition but
                    // loses the house gradient — that ink is reserved for a
                    // figure the screen can vouch for — and carries an explicit
                    // UNVERIFIED mark. The number itself is NOT adjusted here.
                    HStack(alignment: .firstTextBaseline) {
                        Text(fscClosingLine(f))
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(palette.textPrimary).lineLimit(1)
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(m(f.totalFsc ?? f.fscPerCar))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(fscTotalsUnverified
                                                 ? AnyShapeStyle(Brand.warning)
                                                 : AnyShapeStyle(LinearGradient.diagonal))
                            if fscTotalsUnverified {
                                Text("UNVERIFIED")
                                    .font(.system(size: 8, weight: .heavy)).kerning(0.5)
                                    .foregroundStyle(Brand.warning)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(Brand.warning.opacity(0.16)))
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(fscClosingSpoken(f))
                    .accessibilityValue(spokenMoney(f.totalFsc ?? f.fscPerCar, unverified: fscTotalsUnverified))

                    if fscTotalsUnverified { fscUnverifiedNotice }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(fscTotalsUnverified
                                  ? AnyShapeStyle(Brand.warning.opacity(0.45))
                                  : AnyShapeStyle(palette.borderFaint)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else {
                // SUPPRESS THE VERDICT. The card keeps its place in the
                // composition and states what cannot be judged and why, naming
                // each missing input. It does not show a peg, a mileage, a
                // carrier or a total, because it has none of them.
                LifecycleCard(accentWarning: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No surcharge derived")
                            .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Text(derivationUnavailableReason)
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No surcharge derived")
                .accessibilityValue(derivationUnavailableReason)
            }
        }
    }

    /// S13 · the gap surfaced in place, directly under the figure it qualifies.
    /// The screen does not correct the number and does not hide it; it refuses
    /// to present it as a confirmed charge. Same device as the gtm gap notice,
    /// carried in the warning register because money is at stake.
    private var fscUnverifiedNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.warning)
                .accessibilityHidden(true)
            Text("This surcharge total is unverified and is not billable as shown. The per-mile rate is published in cents, and the total is returned in dollars without that conversion, so the amount is overstated. The cents-per-mile rate, the diesel index and the published base above are unaffected. Confirm the total with rail finance before billing.")
                .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.warning.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.warning.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .padding(.horizontal, 16).padding(.bottom, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Surcharge total unverified")
        .accessibilityValue("This surcharge total is unverified and is not billable as shown. The per-mile rate is published in cents, and the total is returned in dollars without that conversion, so the amount is overstated. The cents-per-mile rate, the diesel index and the published base are unaffected. Confirm the total with rail finance before billing.")
    }

    // MARK: Tri-country band — index authority AND currency

    private var triCountryBand: some View {
        HStack(spacing: Space.s2) {
            ForEach(Regime716.allCases, id: \.self) { r in
                Button { regime = r; Task { await load() } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.authority).font(.system(size: 8, weight: .heavy)).kerning(0.3)
                        Text(bandBottom(r)).font(.system(size: 9, weight: .heavy)).lineLimit(1)
                    }
                    .foregroundStyle(r == regime ? Brand.info : palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 44pt floor. This tile was 30pt — under the minimum target
                    // size for a control on iOS — and is raised to 44.
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .background(r == regime ? Brand.blue.opacity(0.12) : palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(r == regime ? Color.clear : palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(r == regime ? .isSelected : .isButton)
                .accessibilityLabel(spoken(r.authority))
                .accessibilityValue(bandSpoken(r))
                .accessibilityHint("Switches the index authority and the currency every amount on this screen is shown in.")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Index authority and currency, three regimes")
    }

    /// What the tile is actually holding, said in words. An unwired regime says
    /// it is unwired rather than implying a converted figure.
    private func bandSpoken(_ r: Regime716) -> String {
        guard r.indexWired else {
            return "\(r.currencyCode). No index is wired for this regime, so no amount is available."
        }
        if r == regime, !indexPublished {
            return "\(r.currencyCode). The index feed does not name a publisher, so no price is shown. A figure that is not published is not an authority's figure."
        }
        if r == regime, let v = index?.nationalAverage {
            return "\(r.currencyCode). National average \(spokenPerGallon(v))."
        }
        return "\(r.currencyCode). \(r.indexNote) index."
    }

    /// The active tile shows the REAL index it is holding; an unwired regime
    /// says so instead of showing a converted US number, and a feed that does
    /// not name a publisher reads "unpublished" rather than being drawn under
    /// the authority's name (RAIL-CAR-716-INDEX-MOCK).
    private func bandBottom(_ r: Regime716) -> String {
        if r == regime, r.indexWired, !indexPublished {
            return "\(r.currencyCode) · unpublished"
        }
        if r == regime, r.indexWired, let v = index?.nationalAverage {
            return "\(r.currencyCode) · \(g(v))"
        }
        return r.indexWired ? "\(r.currencyCode) · \(r.indexNote)" : "\(r.currencyCode) · unavailable"
    }

    private var onlineOnlyNote: some View {
        Text(scheduleEnabled
             ? "POSTING UNAVAILABLE · contact rail finance to record the period · schedule review remains available"
             : "POSTING UNAVAILABLE · no surcharge is derived here · contact rail finance for the billed period and its schedule")
            .font(.system(size: 8.5, weight: .bold, design: .monospaced)).kerning(0.3)
            .foregroundStyle(palette.textTertiary)
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Posting unavailable")
            .accessibilityValue(scheduleEnabled
                ? "Contact rail finance to record the period. Schedule review remains available."
                : "No surcharge is derived on this screen and no schedule is available. Contact rail finance for the billed period and its schedule.")
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { postPeriod() } label: {
                Text("Post MGA period")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(LinearGradient.primary))
                    .opacity(postEnabled ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!postEnabled)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Post MGA period")
            .accessibilityValue(postSpokenValue)

            // HONEST DISABLE. The breakpoints come from the same suppressed
            // derivation, so there is nothing behind this control today. It
            // stays visible at full size and says why, rather than vanishing.
            Button { showSchedule() } label: {
                Text("Schedule")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 148)
                    .frame(minHeight: 48)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
                    .opacity(scheduleEnabled ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!scheduleEnabled)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Schedule")
            .accessibilityValue(scheduleSpokenValue)
            .accessibilityHint(scheduleEnabled
                ? "Shows the carrier's mileage breakpoints for this surcharge peg. Nothing is posted or billed."
                : "No surcharge is derived on this screen, so there are no mileage breakpoints to show.")
        }
    }

    private var postEnabled: Bool { false }

    /// The schedule CTA is live only when real breakpoints landed. They come
    /// from `generateFscSchedule`, which is not called while the carrier mark
    /// and the rail mileage are missing, so today this is always false and the
    /// control carries a named reason instead of an empty sheet.
    private var scheduleEnabled: Bool { (schedule?.schedule?.isEmpty == false) }

    /// A disabled money-moving control has to say WHY out loud, not just look dim.
    private var postSpokenValue: String {
        guard !postEnabled else { return "Available." }
        return "Unavailable. There is no writer for an MGA period, so nothing can be posted and nothing is queued. Contact rail finance to record the period."
    }

    private var scheduleSpokenValue: String {
        guard let rows = schedule?.schedule, !rows.isEmpty else {
            return "Unavailable. \(derivationUnavailableReason)"
        }
        let count = "\(rows.count) mileage breakpoint\(rows.count == 1 ? "" : "s")"
        return fscTotalsUnverified
            ? "\(count). The per-car amounts are unverified and are not billable as shown."
            : count + "."
    }

    /// ONLINE_ONLY and NOT YET WIRED. There is no writer for an MGA period on
    /// the server, so the CTA states the gap and posts nothing. It is never
    /// queued: a replayed post would bill the same gallons twice, or bill them
    /// against a superseded index.
    private func postPeriod() {
        let period = points.last?.month ?? "this period"
        // Settlement context is real: a period whose rail settlements have
        // already been paid out cannot be re-posted, and the notice says so.
        let settled = (financial?.settlements ?? [])
            .filter { ["completed", "paid", "processing"].contains(($0.status ?? "").lowercased()) }
            .count
        let settlementNote = settled > 0
            ? " \(settled) rail settlement\(settled == 1 ? "" : "s") for this book are already in flight, so a re-post would bill against money that has moved."
            : ""
        actionNotice = (
            "Nothing was posted. MGA-period posting is unavailable, so period \(period) remains open. Contact rail finance to record it.\(settlementNote)",
            false)
    }

    /// S13 · every fscPerCar in this schedule comes from the same defective
    /// arithmetic (fuelSurchargeIndex.ts:83), so the breakpoints are shown but
    /// are never announced as confirmed charges — the notice keeps the warning
    /// register rather than the success one, and says why in place.
    private func showSchedule() {
        guard let rows = schedule?.schedule, !rows.isEmpty else {
            actionNotice = (derivationUnavailableReason, false)
            return
        }
        let line = rows.prefix(4)
            .map { "\(n($0.mileage)) mi \(m($0.fscPerCar))" }
            .joined(separator: " · ")
        let caveat = fscTotalsUnverified
            ? " The per-car amounts are unverified and are not billable as shown; the cents-per-mile rate is unaffected. Confirm with rail finance before billing."
            : ""
        // The peg's ¢/mi rate is stated only when the server sent one. An absent
        // rate is named, never printed as 0.000.
        let head: String
        if let rate = cpm(schedule?.centsPerMile) {
            head = "FSC schedule at \(rate)¢/mi"
        } else {
            head = "FSC schedule · rate not reported"
        }
        actionNotice = ("\(head) — \(line).\(caveat)", !fscTotalsUnverified)
    }

    private func noticeCard(_ a: (text: String, ok: Bool)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: a.ok ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(a.ok ? Brand.success : Brand.warning)
                .accessibilityHidden(true)
            Text(a.text).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background((a.ok ? Brand.success : Brand.warning).opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder((a.ok ? Brand.success : Brand.warning).opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a.ok ? "Notice" : "Attention")
        .accessibilityValue(spoken(a.text))
    }

    private func sectionLabel(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(trailing).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(title.lowercased().capitalized))
        .accessibilityValue(spoken(trailing))
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Data

    private struct TrendInput716: Encodable { let months: Int; let metric: String }
    private struct FscInput716: Encodable {
        let dieselPriceUsdPerGallon: Double
        let mileage: Double
        let carrier: String
        let railcarCount: Int
    }
    private struct ScheduleInput716: Encodable {
        let carrier: String
        let dieselPriceUsdPerGallon: Double
        let maxMileage: Double
        let mileageIncrement: Double
    }
    private struct TxInput716: Encodable { let limit: Int; let offset: Int }
    private struct RankInput716: Encodable { let rankBy: String; let period: String; let limit: Int }
    private struct IdlingInput716: Encodable { let period: String }
    private struct HistoryInput716: Encodable { let months: Int }

    private func load() async {
        loading = true; loadError = nil

        // 1 · The hero's ONE tick — both series.
        do {
            trend = try await EusoTripAPI.shared.query(
                "fuelManagement.getFuelTrendAnalysis",
                input: TrendInput716(months: 12, metric: "consumption"))
        } catch {
            loadError = error.eusoUserCopy
        }

        // 2 · The current index. Only the US shape exists on disk
        //     (RAIL-CAR-716-INDEX-COUNTRY) — for CA/MX we do not substitute it.
        if regime.indexWired {
            index = try? await EusoTripAPI.shared.queryNoInput("fuelSurchargeIndex.currentDieselIndex")
        } else {
            index = nil
        }

        // 3 · Rail money — the real rail settlements this book already has in
        //     flight, read only to tell the operator that a period cannot be
        //     re-posted over money that has moved. Settlement rows carry no
        //     mileage and none is taken from them.
        financial = try? await EusoTripAPI.shared.queryNoInput("railShipments.getRailFinancialSummary")

        // 4 · The ledger spine + its raw transactions. Asked for BY DRIVER,
        //     because that is what the procedure returns whatever is asked of
        //     it — it groups the highway fuel-card table by driverId and never
        //     reads this input at all. Sending "vehicle" here would have the
        //     client claim a keying the payload does not have, and would flip
        //     the ledger's meaning under a fixed server without anyone noticing.
        //     Nothing on this read reaches the surcharge; see step 5.
        efficiency = try? await EusoTripAPI.shared.query(
            "fuelManagement.getFuelEfficiencyRanking",
            input: RankInput716(rankBy: "driver", period: "month", limit: 20))
        if let env: FuelTxEnvelope716 = try? await EusoTripAPI.shared.query(
            "fuelManagement.getFuelTransactions", input: TxInput716(limit: 50, offset: 0)) {
            transactions = env.transactions ?? []
        } else {
            transactions = []
        }

        // 5 · The derivation. THREE real inputs are required and none may be
        //     supplied by this view: the published index, the account's own
        //     railroad reporting mark, and a rail mileage. All three are gated
        //     above; when any is absent NO call is made and the card renders
        //     its honest unavailable state naming what is missing.
        //     The peg is derived from the published INDEX only — the company's
        //     own average pump price is a different number and is never
        //     substituted for it, and for CA/MX there is no index on disk at
        //     all (RAIL-CAR-716-INDEX-COUNTRY).
        //     The mark and the mileage are nil today (RAIL-CAR-716-CARRIER-MARK,
        //     RAIL-CAR-716-RAIL-MILEAGE), so these two queries do not fire. They
        //     are left wired, correctly typed, so that closing either gap is a
        //     one-line change here and nothing has to be reconstructed. The
        //     railcarCount the surcharge needs is likewise not on file, so it
        //     stays out of the billing path with the rest.
        let diesel = (regime.indexWired && indexPublished) ? index?.nationalAverage : nil
        if let d = diesel, let mark = carrierReportingMark, let mi = railBillingMileage,
           d > 0, mi > 0 {
            fsc = try? await EusoTripAPI.shared.query(
                "fuelSurchargeIndex.calculateSteppedFsc",
                input: FscInput716(dieselPriceUsdPerGallon: d, mileage: mi,
                                   carrier: mark, railcarCount: 1))
            schedule = try? await EusoTripAPI.shared.query(
                "fuelSurchargeIndex.generateFscSchedule",
                input: ScheduleInput716(carrier: mark, dieselPriceUsdPerGallon: d,
                                        maxMileage: 3000, mileageIncrement: 250))
        } else {
            fsc = nil; schedule = nil
        }

        // 6 · Idle burn. Read but NOT joined to the ledger — its rows are keyed
        //     to vehicles and the ledger's rows are keyed to drivers, so there
        //     is no correct pairing to make. See `idlingFor` and
        //     RAIL-CAR-716-IDLE-JOIN. Kept wired so the join can be made the
        //     day one of the two payloads carries the other's key.
        if let env: IdlingEnvelope716 = try? await EusoTripAPI.shared.query(
            "fuelManagement.getIdlingReport", input: IdlingInput716(period: "month")) {
            idling = env.byVehicle ?? []
        } else {
            idling = []
        }

        // 7 · The published surcharge series behind the staleness check.
        fscHistory = try? await EusoTripAPI.shared.query(
            "fuelManagement.getFuelSurchargeHistory", input: HistoryInput716(months: 12))

        if loadError == nil || !points.isEmpty { lastGoodTick = Date() }
        loading = false
    }

    // REMOVED in fire 17 — `derivedMileage`. It took the largest highway
    // driver's mpg × gallons, or else the trailing month's gallons × avgMpg
    // (which the server fixes at exactly 6.5), and handed the result to
    // `calculateSteppedFsc` as the `mileage` the surcharge is billed on. That
    // made one truck's 30-day road distance — or a bare gallons × 6.5 constant
    // — the billing basis of a rail fuel surcharge. Nothing on this screen may
    // stand in for a locomotive mile; see RAIL-CAR-716-RAIL-MILEAGE and
    // `railBillingMileage`. Highway miles still appear in the ledger, labelled
    // as highway miles, where they are a fleet fact and not a charge.
}

#Preview("716 · Rail Carrier Fuel and MGA · Light") {
    RailCarrierFuelMGAScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("716 · Rail Carrier Fuel and MGA · Dark") {
    RailCarrierFuelMGAScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
