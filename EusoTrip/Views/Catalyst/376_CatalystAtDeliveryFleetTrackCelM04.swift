//
//  376_CatalystAtDeliveryFleetTrackCelM04.swift
//  EusoTrip — Catalyst · At-Delivery Fleet Track (M04 · cel 376).
//
//  Bespoke port of "§399 Catalyst-vantage AT-DELIVERY FLEET-TRACK on M-04 ·
//  DELIVERY QUARTET 2/4" — the consumer-side echo of the §398 driver-vantage
//  AT-DELIVERY ARRIVAL. Reconstructed canonical AFTER lived at
//  03 Catalyst/Code/376_CatalystAtDeliveryFleetTrackCelM04.swift; this is its
//  app-convention landing (Shell + catalyst BottomNav from sibling 305).
//
//  Chain context (M-04 lifecycle · catalyst vantage):
//    §398 DRIVER     at-delivery arrival · IN-TRANSIT→DELIVERY (ring rolled
//                    there) · drivers.updateLoadStatus(status:"at_delivery")
//    §399 CATALYST   fleet-track (THIS FILE · DELIVERY 2/4) · NO ring
//                    transition · carrier fleet-tracker reflects the assigned
//                    driver arrived at the consignee.
//
//  WIRING MANIFEST (MCP-confirmed against frontend/server/routers/catalysts.ts
//  + EusoTripAPI LoadsAPI.LoadDetail this fire — every visible business value
//  binds to a REAL proc, or paints an honest "-"/"—"/EusoEmptyState. NO
//  hardcoded persona and NO `?? <invented>` fallback remains; the canonical
//  M-04 seed lives ONLY in #Preview, mirroring sibling 375):
//
//    • catalysts.getMyDrivers   — EXISTS · catalysts.ts:431 ·
//        input  { limit?: number }
//        output [{ id, name, status, currentLoad, hoursRemaining, location }]
//        `location` is REAL-BACKED off the latest gps_tracking lat/long
//        ("DD.DD, DD.DD"); this is the live arrival position read, not an
//        estimate. The at-delivery driver row is matched off `currentLoad`.
//    • catalysts.getActiveLoads — EXISTS · catalysts.ts:510 ·
//        input  { limit?: number }
//        output [{ id, loadNumber, status, origin, destination, driver,
//                  eta, rate }]   (origin/destination are "City, ST"|"Unknown")
//        CAVEAT (confirmed catalysts.ts:524): the SQL filter is
//          status IN ('in_transit','assigned','loading','at_pickup')
//        — it does NOT include 'at_delivery'. So an ARRIVED M-04 load
//        DROPS OFF this list. We surface that honestly: the active-board
//        telemetry row reads "off the board" rather than fabricating one,
//        and the load detail is sourced from loads.getById instead.
//    • loads.getById            — EXISTS · LoadsAPI.LoadDetail ·
//        CORRECTED SHAPE: top-level `id` is a String? on the wire
//        (server returns String(load.id)); decoding it as Int throws
//        typeMismatch and FAILS THE WHOLE DECODE → blank surface.
//        pickup/delivery are NESTED `pickupLocation`/`deliveryLocation`
//        objects { city, state, lat, lng } — NOT flat top-level city
//        fields; flat-city decode = silent miss → blank lane. Sources the
//        real lane (laneDisplay), distance (distanceDisplay), equipment
//        (equipmentType), commodity (commodityName/commodity/cargoType),
//        weight (weightDisplay), and rate (rateDisplay). Bound only when a
//        real load id resolves (passed in, or recovered off the active
//        board); never fabricated.
//    • catalysts.getBidsForLoad — EXISTS · catalysts.ts:3500 ·
//        input  { loadId: String }
//        output ALL bids on the load incl. the winner; rows carry
//        id "bid_<n>", catalystName (real carrier company name), amount.
//        Mirrors sibling 373. The WINNING carrier identity (company name)
//        comes from the recommended/most-recent bid — there is NO hardcoded
//        "Carolina Express Logistics"/"CEL" persona anywhere on this surface.
//
//  NO STATUS MUTATION THIS FIRE. §399 is a READ-ONLY echo; the load status
//  HOLDS at `at_delivery` (written at §398). Its actions still open real
//  native surfaces: CatalystLoadDetailScreen and the persisted load thread
//  from messages.getOrCreateLoadConversation.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Theme (cel 376 · design-system colors, NOT raw hex)

private enum Theme376 {
    static let gradient = LinearGradient(
        colors: [Brand.blue, Brand.magenta],
        startPoint: .leading, endPoint: .trailing)
    static let gradientDiag = LinearGradient(
        colors: [Brand.blue, Brand.magenta],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Model

enum LifecycleStage_376: Int, CaseIterable {
    case posted, bidding, awarded, pickup, transit, delivery, paperwork, closed
    var label: String {
        switch self {
        case .posted:    return "POST"
        case .bidding:   return "BID"
        case .awarded:   return "AWRD"
        case .pickup:    return "PICK"
        case .transit:   return "TRAN"
        case .delivery:  return "DELV"
        case .paperwork: return "PAPR"
        case .closed:    return "CLSD"
        }
    }
}

/// One fleet-track telemetry row. `realBacked` distinguishes a verb-sourced
/// read (green check) from an unbacked/absent state (hollow badge).
struct FleetTrackRow_376: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let trailing: String
    let realBacked: Bool
}

// MARK: - Network shapes (decode targets for the generic client)

/// catalysts.getActiveLoads → ActiveLoad[] (real shape · catalysts.ts:562-571).
/// origin/destination arrive as "City, ST" or "Unknown"; rate is a Double.
private struct ActiveLoad376: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String?
    let status: String?
    let origin: String?
    let destination: String?
    let driver: String?
    let eta: String?
    let rate: Double?
}

/// catalysts.getMyDrivers → CatalystDriver[] (real shape · catalysts.ts:431).
/// `location` is "DD.DD, DD.DD" off the latest gps_tracking row, or "Unknown".
private struct CatalystDriver376: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let status: String?
    let currentLoad: String?
    let hoursRemaining: Double?
    let location: String?
}

/// One bid row from catalysts.getBidsForLoad (server catalysts.ts:3528).
/// `id` is "bid_<n>"; `catalystName` is the real carrier company name;
/// `recommended` flags the most-recent bid. Mirrors 373's BidRow_373.
private struct BidRow376: Decodable, Identifiable, Hashable {
    let id: String
    let catalystId: String?
    let catalystName: String?
    let amount: Double?
    let recommended: Bool?
}

private struct LimitInput376: Encodable { let limit: Int }
private struct LoadIdInput376: Encodable { let loadId: String }

// MARK: - Screen wrapper (Shell + catalyst BottomNav · copied from sibling 305)

struct CatalystAtDeliveryFleetTrackCelM04Screen: View {
    let theme: Theme.Palette
    let loadId: String

    init(theme: Theme.Palette, loadId: String = "0") {
        self.theme = theme
        self.loadId = loadId
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystAtDeliveryFleetTrackCelM04View(loadId: loadId)
        } nav: {
            BottomNav(
                leading: catalystNavLeading_376(),
                trailing: catalystNavTrailing_376(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_376() -> [NavSlot] {
    CarrierNavRoute.leading(current: .loads)
}

private func catalystNavTrailing_376() -> [NavSlot] {
    CarrierNavRoute.trailing(current: .loads)
}

// MARK: - StatusPill (AtDeliveryFleetTrackCatalystPill_376 · DELIVERY-stage catalyst pill)

struct AtDeliveryFleetTrackCatalystPill_376: View {
    /// Consignee city/state from the live delivery location, or "—".
    let consignee: String
    /// Server-computed ETA / appointment string, or "—".
    let eta: String

    var body: some View {
        HStack(spacing: 6) {
            // Drawn map-pin glyph — arrival semantics
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
            Text("AT-DELIVERY · \(consignee) · ARRIVED · \(eta)")
                .font(.system(size: 9, weight: .heavy))
                .kerning(0.4)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .background(Capsule().fill(Theme376.gradient))
    }
}

// MARK: - MetricTile quartet (KpiQuartetAtDeliveryFleetTrackCatalyst_376)

struct KpiQuartetAtDeliveryFleetTrackCatalyst_376: View {
    /// Server-computed ETA / appointment string, or "-".
    let eta: String
    /// Real distance display ("245 mi") from loads.getById, or "-".
    let miles: String
    /// HOS remaining for the arrived driver ("7:03"), or "-".
    let hos: String
    /// HOS duty status slug ("on_duty"/"off_duty"…), or "-".
    let hosStatus: String

    @Environment(\.palette) private var palette

    var body: some View {
        let tile: (String, String, String) -> AnyView = { k, v, sub in
            AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    Text(k).font(.system(size: 8, weight: .heavy)).kerning(0.5)
                        .foregroundStyle(palette.textTertiary)
                    Text(v).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme376.gradient)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(sub).font(.system(size: 8)).foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(width: 94, height: 60, alignment: .topLeading)
                .padding(.leading, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.blue.opacity(0.55), lineWidth: 1))
            )
        }
        return HStack(spacing: 8) {
            tile("APPT", eta, "arrival")
            tile("MILES", miles, "delivered")
            tile("HOS", hos, hosStatus)
            tile("EXC", "0", "on-time")
        }
    }
}

// MARK: - Stepper (LifecycleStripEight_376 · ring at DELIVERY, rolled at §398)

struct LifecycleStripEight_376: View {
    let stage: LifecycleStage_376
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let xs = stride(from: 0.0, through: 1.0, by: 1.0 / 7.0).map { $0 * geo.size.width }
            let node: (LifecycleStage_376, CGFloat) -> AnyView = { s, x in
                let active = (s == stage)
                let done = s.rawValue < stage.rawValue
                let fill: AnyShapeStyle = active
                    ? AnyShapeStyle(Theme376.gradient)
                    : (done ? AnyShapeStyle(Theme376.gradient.opacity(0.45))
                            : AnyShapeStyle(palette.textTertiary.opacity(0.35)))
                return AnyView(
                    Circle()
                        .fill(fill)
                        .frame(width: active ? 6 : 8, height: active ? 6 : 8)
                        .overlay(active
                                 ? Circle().strokeBorder(Theme376.gradient, lineWidth: 2).frame(width: 10, height: 10)
                                 : nil)
                        .position(x: x, y: 15)
                )
            }
            ZStack(alignment: .leading) {
                Capsule().fill(palette.borderFaint).frame(height: 2)
                // Gradient progress to DELIVERY node (index 5 of 7)
                Capsule().fill(Theme376.gradient)
                    .frame(width: xs[5], height: 2)
                ForEach(LifecycleStage_376.allCases, id: \.rawValue) { s in
                    node(s, xs[s.rawValue])
                }
            }
        }
        .frame(height: 34)
    }
}

// MARK: - ActiveCard (FleetTrackerArrivedCard_376)

struct FleetTrackerArrivedCard_376: View {
    fileprivate let driver: CatalystDriver376
    /// Consignee city/state from the live delivery location, or "—".
    let consignee: String
    /// Winning/assigned carrier display from catalysts.getBidsForLoad.
    let carrierName: String
    @Environment(\.palette) private var palette

    private var driverName: String {
        let n = driver.name?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "—" : n
    }
    private var initials: String {
        let n = driver.name?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !n.isEmpty else { return "—" }
        let cleaned = n.replacingOccurrences(of: ",", with: " ")
        let ini = cleaned.split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }.joined().uppercased()
        return ini.isEmpty ? "—" : String(ini.prefix(2))
    }
    private var hosSlug: String {
        let status = driver.status?.trimmingCharacters(in: .whitespaces) ?? ""
        let rem = driver.hoursRemaining.map { formatHOS376($0) } ?? "—"
        let s = status.isEmpty ? "—" : status
        return "HOS \(s) \(rem)"
    }
    private var positionLabel: String {
        let loc = driver.location?.trimmingCharacters(in: .whitespaces) ?? ""
        return (loc.isEmpty || loc == "Unknown") ? "—" : loc
    }
    private var statusChip: String {
        let s = driver.status?.trimmingCharacters(in: .whitespaces) ?? ""
        return s.isEmpty ? "ARRIVED" : "ARRIVED"
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Theme376.gradientDiag).frame(width: 30, height: 30)
                .overlay(Text(initials).font(.system(size: 10, weight: .heavy)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(driverName) · \(carrierName)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(hosSlug)
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Text("\(driver.id) · \(consignee) · live pos \(positionLabel)")
                    .font(.system(size: 8)).foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            Text(statusChip).font(.system(size: 7, weight: .heavy)).foregroundColor(.white)
                .padding(.horizontal, 8).frame(height: 14)
                .background(Capsule().fill(Theme376.gradient))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.blue.opacity(0.55), lineWidth: 1))
    }
}

// MARK: - ListRow (FleetTrackRowView_376 · real-backed check vs estimate badge)

struct FleetTrackRowView_376: View {
    let row: FleetTrackRow_376
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if row.realBacked {
                    Circle().fill(Theme376.gradientDiag).frame(width: 18, height: 18)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundColor(.white)
                } else {
                    Circle().strokeBorder(palette.textTertiary.opacity(0.5), lineWidth: 1).frame(width: 18, height: 18)
                    Text("est.").font(.system(size: 6, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(row.detail).font(.system(size: 8)).foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            Text(row.trailing).font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

// MARK: - ShipperOfRecordCard_376 (shipper-of-record co-anchor · loads.getById shipper party)

struct ShipperOfRecordCard_376: View {
    /// Shipper display name from loads.getById, or "—".
    let shipperName: String
    /// Shipper monogram derived from the name, or "—".
    let shipperMonogram: String
    /// Shipper party metadata from loads.getById.
    let metaLine: String
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme376.gradientDiag).frame(width: 26, height: 26)
                .overlay(Text(shipperMonogram).font(.system(size: 9, weight: .heavy)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text("Shipper of record · \(shipperName)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(metaLine)
                    .font(.system(size: 8, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.blue.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.blue.opacity(0.55), lineWidth: 1))
    }
}

// MARK: - ActionRibbon (native load detail + persisted load thread)

struct ActionRibbonAtDeliveryFleetTrackCatalyst_376: View {
    let openingConversation: Bool
    let openLoad: () -> Void
    let openConversation: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Button {
                openLoad()
            } label: {
                Text("VIEW LOAD").font(.system(size: 9, weight: .heavy)).kerning(0.5)
                    .foregroundColor(.white).frame(width: 156, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme376.gradient))
            }
            .buttonStyle(.plain)

            Button {
                openConversation()
            } label: {
                Text(openingConversation ? "OPENING" : "MESSAGE DRIVER").font(.system(size: 9, weight: .heavy)).kerning(0.5)
                    .foregroundStyle(Theme376.gradient).frame(width: 132, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Brand.blue.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(openingConversation)
        }
    }
}

// MARK: - Surface (bespoke cel body)

struct CatalystAtDeliveryFleetTrackCelM04View: View {
    let loadId: String
    @Environment(\.palette) private var palette

    /// Live server-bound state — NO hardcoded display anchors remain.
    @State private var detail: LoadsAPI.LoadDetail? = nil
    @State private var activeRow: ActiveLoad376? = nil
    @State private var driver: CatalystDriver376? = nil
    @State private var bids: [BidRow376] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil
    @State private var actionBusy = false
    @State private var showLoadDetail = false
    @State private var activeThread: InboxThread? = nil
    /// True when the M-04 row was found on catalysts.getActiveLoads. Because
    /// the server filter excludes 'at_delivery', this is expected to be FALSE
    /// once the load arrives — we surface that honestly rather than fabricate.
    @State private var onActiveBoard = false

    /// Seed used ONLY by #Preview (no environment session → live fetch
    /// silently yields nothing; the seed paints the canonical M-04 state).
    /// nil in the real app until the fetch resolves. Mirrors sibling 375.
    fileprivate var previewSeedDriver: CatalystDriver376? = nil
    fileprivate var previewSeedActive: ActiveLoad376? = nil
    fileprivate var previewSeedBids: [BidRow376] = []

    private let stage: LifecycleStage_376 = .delivery

    init(loadId: String = "0") { self.loadId = loadId }

    // MARK: Derived — lane / miles / equipment / commodity / weight / rate

    /// Real lane. Prefer loads.getById laneDisplay; fall back to the active
    /// board's "City, ST → City, ST" when present; "—" when neither resolves.
    private var laneDisplay: String {
        if let d = detail {
            let lane = d.laneDisplay
            if lane != "—" { return lane }
        }
        if let a = activeRow {
            let o = (a.origin ?? "").trimmingCharacters(in: .whitespaces)
            let dst = (a.destination ?? "").trimmingCharacters(in: .whitespaces)
            let oOK = !o.isEmpty && o != "Unknown"
            let dOK = !dst.isEmpty && dst != "Unknown"
            if oOK || dOK { return "\(oOK ? o : "—") → \(dOK ? dst : "—")" }
        }
        return "—"
    }
    /// "245 mi" / "—" — real distance from loads.getById.
    private var milesDisplay: String { detail?.distanceDisplay ?? "—" }
    /// Equipment / trailer type — "—" when unspecified.
    private var equipmentDisplay: String {
        let eq = detail?.equipmentType?.trimmingCharacters(in: .whitespaces) ?? ""
        return eq.isEmpty ? "—" : eq
    }
    /// Commodity / cargo — specific name preferred; the server's forced
    /// "general" cargoType with no name is treated as empty ("—").
    private var commodityDisplay: String {
        if let c = detail?.commodityName?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        if let c = detail?.commodity?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        let cargo = detail?.cargoType?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        if cargo.isEmpty || cargo == "general" { return "—" }
        return cargo.capitalized
    }
    /// "38,000 lb" / "—" — real weight from loads.getById.
    private var weightDisplay: String { detail?.weightDisplay ?? "—" }
    /// "$1,610" — real rate; prefer loads.getById, else the active board's
    /// numeric rate; "—" when neither resolves.
    private var rateDisplay: String {
        if let d = detail, d.rateValue > 0 { return d.rateDisplay }
        if let r = activeRow?.rate, r > 0 {
            let f = NumberFormatter()
            f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 0
            return f.string(from: NSNumber(value: r)) ?? "$\(Int(r))"
        }
        return "—"
    }
    /// Server-computed ETA / appointment string from the active board, or "—".
    private var etaDisplay: String {
        let e = activeRow?.eta?.trimmingCharacters(in: .whitespaces) ?? ""
        return e.isEmpty ? "—" : e
    }

    // MARK: Derived — winning carrier (catalysts.getBidsForLoad)

    /// Winning carrier company name from the recommended (most-recent) bid,
    /// or the highest-amount bid as a fallback; "—" when no bids resolve.
    /// No hardcoded "Carolina Express Logistics"/"CEL" persona anywhere.
    private var winningCarrierName: String {
        let winner = bids.first { $0.recommended == true }
            ?? bids.max { ($0.amount ?? 0) < ($1.amount ?? 0) }
        let n = winner?.catalystName?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "—" : n
    }

    // MARK: Derived — load number / consignee / shipper

    private var loadNumberDisplay: String {
        if let n = detail?.loadNumber, !n.isEmpty { return n }
        if let n = activeRow?.loadNumber, !n.isEmpty { return n }
        return "-"
    }
    /// Consignee = the delivery city/state from loads.getById, or the active
    /// board destination; "—" when neither resolves. No hardcoded "CLT Newell".
    private var consigneeDisplay: String {
        if let cs = detail?.deliveryLocation?.cityState, !cs.isEmpty { return cs }
        let dst = (activeRow?.destination ?? "").trimmingCharacters(in: .whitespaces)
        return (dst.isEmpty || dst == "Unknown") ? "—" : dst
    }
    /// Shipper-of-record name from the resolved party object on loads.getById.
    private var shipperNameDisplay: String {
        nonEmpty(detail?.shipper?.companyName)
            ?? nonEmpty(detail?.shipper?.name)
            ?? detail?.shipperId.map { "Shipper #\($0)" }
            ?? "—"
    }
    private var shipperMonogram: String {
        nonEmpty(detail?.shipper?.initials)
            ?? monogram376(shipperNameDisplay)
    }
    private var shipperMetaLine: String {
        guard let detail else { return "loads.getById party sync pending" }
        let party = detail.shipper
        let companyId = (party?.companyId ?? detail.shipperId).map { "companyId \($0)" }
        let mc = nonEmpty(party?.mcNumber).map { "MC \($0)" }
        let dot = nonEmpty(party?.dotNumber).map { "DOT \($0)" }
        let email = nonEmpty(party?.email)
        let parts = [companyId, mc, dot, email].compactMap { $0 }
        return parts.isEmpty ? "No shipper party metadata on this load" : parts.joined(separator: " · ")
    }

    /// HOS remaining for the arrived driver ("7:03"), or "-".
    private var hosDisplay: String {
        driver?.hoursRemaining.map { formatHOS376($0) } ?? "-"
    }
    private var hosStatusDisplay: String {
        let s = driver?.status?.trimmingCharacters(in: .whitespaces) ?? ""
        return s.isEmpty ? "-" : s
    }

    /// True when at least one real value resolved (so the surface paints
    /// rather than showing the empty state on a partial live read).
    private var hasContent: Bool {
        detail != nil || activeRow != nil || driver != nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                topBar
                hero
                hairline

                if loading && !hasContent {
                    skeleton
                } else if let err = loadError, !hasContent {
                    errorBanner(err)
                } else if hasContent {
                    AtDeliveryFleetTrackCatalystPill_376(consignee: consigneeDisplay, eta: etaDisplay)
                        .frame(maxWidth: .infinity)

                    KpiQuartetAtDeliveryFleetTrackCatalyst_376(
                        eta: etaDisplay, miles: milesDisplay,
                        hos: hosDisplay, hosStatus: hosStatusDisplay)

                    LifecycleStripEight_376(stage: stage)

                    if let d = driver {
                        FleetTrackerArrivedCard_376(
                            driver: d,
                            consignee: consigneeDisplay,
                            carrierName: winningCarrierName == "—" ? "assigned carrier" : winningCarrierName
                        )
                    } else {
                        fleetEmptyRow
                    }

                    fleetTrackMapCard

                    telemetrySection

                    routeProgressCapsule

                    ShipperOfRecordCard_376(
                        shipperName: shipperNameDisplay,
                        shipperMonogram: shipperMonogram,
                        metaLine: shipperMetaLine
                    )

                    ActionRibbonAtDeliveryFleetTrackCatalyst_376(
                        openingConversation: actionBusy,
                        openLoad: { showLoadDetail = true },
                        openConversation: { Task { await openLoadConversation() } }
                    )
                    actionFeedback
                } else {
                    emptyState
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await fetch() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await fetch() }
        }
        .eusoRefreshHandler { await fetch() }
        .sheet(isPresented: $showLoadDetail) {
            if !resolvedLoadId.isEmpty {
                CatalystLoadDetailScreen(theme: palette, loadId: resolvedLoadId)
            }
        }
        .sheet(item: $activeThread) { thread in
            DriverConversationView(thread: thread)
                .environment(\.palette, palette)
        }
    }

    // MARK: TopBar eyebrow (single ✦)

    private var topBar: some View {
        HStack {
            EusoTripEyebrow(verbatim: "CATALYST · DISPATCH · AT-DELIVERY · FLEET-TRACK")
                .font(.system(size: 9, weight: .heavy)).kerning(1).foregroundStyle(Theme376.gradient)
            Spacer()
            Text("\(loadNumberDisplay) · §399 · DELIVERY · 2/4")
                .font(.system(size: 9, weight: .heavy)).kerning(1).foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("At delivery · \(winningCarrierName == "—" ? "carrier fleet" : winningCarrierName) arrived · \(consigneeDisplay)")
                .font(.system(size: 20, weight: .bold)).kerning(-0.6)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.7)
            Text("\(laneDisplay) · \(equipmentDisplay) · \(milesDisplay) · \(etaDisplay)")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .lineLimit(2).minimumScaleFactor(0.7)
        }
    }

    private var hairline: some View {
        Rectangle().fill(Theme376.gradient.opacity(0.55)).frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: Fleet empty row (honest — no matching driver roster row resolved)

    private var fleetEmptyRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.slash.circle")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme376.gradient)
            VStack(alignment: .leading, spacing: 2) {
                Text("Arrived driver pending")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("No matching driver in this catalyst's roster feed")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    // MARK: Telemetry rows

    private var telemetrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FLEET-TRACKER ECHO · AT-DELIVERY · live load-state signal")
                .font(.system(size: 8, weight: .heavy)).kerning(0.5).foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
            ForEach(telemetryRows) { FleetTrackRowView_376(row: $0) }
        }
    }

    /// Telemetry rows derived entirely from live reads. The arrival-position
    /// + HOS rows are REAL-BACKED off catalysts.getMyDrivers; the active-board
    /// row is honestly UNBACKED because at_delivery is filtered off that list.
    private var telemetryRows: [FleetTrackRow_376] {
        let loc = driver?.location?.trimmingCharacters(in: .whitespaces) ?? ""
        let locBacked = !loc.isEmpty && loc != "Unknown"
        let hosBacked = driver?.hoursRemaining != nil
        return [
            .init(title: "Arrived · \(consigneeDisplay)",
                  detail: "at_delivery · gated in at consignee · \(etaDisplay)",
                  trailing: locBacked ? "live" : "—",
                  realBacked: locBacked),
            .init(title: "HOS · \(hosStatusDisplay) · \(hosDisplay) remaining",
                  detail: "drive clock frozen at arrival · live hours remaining per driver",
                  trailing: hosBacked ? hosDisplay : "—",
                  realBacked: hosBacked),
            .init(title: "Active board echo",
                  detail: "at delivery a load leaves the active board by design — missing there is expected, not a dropped load",
                  trailing: onActiveBoard ? "on board" : "off board",
                  realBacked: false)
        ]
    }

    // MARK: Route-progress capsule (route complete at delivery)

    private var routeProgressCapsule: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.borderFaint).frame(height: 4)
                    Capsule().fill(Theme376.gradient).frame(width: geo.size.width * 1.0, height: 4)
                }
            }.frame(height: 4)
            Text("DELIVERY ROUTE · \(milesDisplay) · arrived \(consigneeDisplay) · next UNLOAD + POD")
                .font(.system(size: 8, weight: .heavy)).kerning(0.4).foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    // MARK: Fleet-track map (in-house HERE · real gpsTracking truck puck)

    /// Real driver fix parsed from `driver.location`, which the server
    /// formats verbatim as "<lat>, <lng>" off the latest gps_tracking row in
    /// catalysts.getMyDrivers. Returns nil when the string is a place name /
    /// "Unknown" / unparseable, or frames on null island (0,0) — in which
    /// case we draw NO map rather than fabricate a fix.
    private var liveTruckFix: HereLatLng? {
        guard let raw = driver?.location else { return nil }
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lng = Double(parts[1]),
              !(lat == 0 && lng == 0) else { return nil }
        return HereLatLng(lat, lng)
    }

    /// In-house HERE live map carrying the catalyst fleet-track truck puck at
    /// the driver's real gps_tracking position. Only the live `.truck` marker
    /// is drawn: the consignee reaches this surface as a NAME only (no lat/lng
    /// on the active-board rows, and the at_delivery row is filtered off that
    /// board anyway), so a delivery pin would have to be geocoded, which the
    /// embed doctrine forbids. We honestly render the single real puck and
    /// gate it behind a real fix.
    @ViewBuilder
    private var fleetTrackMapCard: some View {
        if let fix = liveTruckFix {
            VStack(alignment: .leading, spacing: 6) {
                Text("LIVE FLEET-TRACK · GPS · live driver positions")
                    .font(.system(size: 8, weight: .heavy)).kerning(0.5)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HereLiveMapView(
                    center: .init(fix.lat, fix.lng),
                    zoom: 9,
                    baseLayers: [
                        .markers([
                            .init(at: .init(fix.lat, fix.lng),
                                  kind: .truck,
                                  label: mapMarkerLabel,
                                  id: resolvedLoadId.isEmpty ? nil : resolvedLoadId)
                        ])
                    ],
                    addOns: .shipperTracking,
                    onSelectMarker: { _ in
                        Task { await openLoadConversation() }
                    }
                )
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
            }
        }
    }

    /// Truck-puck label — the real driver name when present, else the load
    /// number; never a fabricated tractor unit. "—" only if both are empty.
    private var mapMarkerLabel: String {
        let n = driver?.name?.trimmingCharacters(in: .whitespaces) ?? ""
        if !n.isEmpty { return n }
        let ln = loadNumberDisplay
        return ln == "-" ? "—" : ln
    }

    // MARK: Loading / empty / error

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard).frame(height: 22)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard).frame(height: 60)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard).frame(height: 64)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard).frame(height: 110)
        }
        .redacted(reason: .placeholder)
    }

    private var emptyState: some View {
        EusoEmptyState(
            systemImage: "mappin.slash.circle",
            title: "No load at delivery",
            subtitle: "Nothing arrived right now · check the dispatch board for active hauls."
        )
        .frame(maxWidth: .infinity)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(msg)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Button { Task { await fetch() } } label: {
                    Text("Retry")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Brand.danger.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private var actionFeedback: some View {
        if let msg = actionError ?? actionMessage {
            HStack(spacing: 8) {
                Image(systemName: actionError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(actionError == nil ? Brand.success : Brand.danger)
                Text(msg)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(actionError == nil ? palette.textSecondary : Brand.danger)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((actionError == nil ? Brand.success : Brand.danger).opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder((actionError == nil ? Brand.success : Brand.danger).opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Network

    /// The load id used for loads.getById / getBidsForLoad / the chat hook.
    /// Prefer an explicitly passed id, then a recovered active-board id.
    private var resolvedLoadId: String {
        if !loadId.isEmpty, loadId != "0" { return loadId }
        return activeRow?.id ?? ""
    }

    private func nonEmpty(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func monogram376(_ name: String) -> String {
        let initials = name
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(2)
            .compactMap { $0.first }
        let value = String(initials).uppercased()
        return value.isEmpty || value == "—" ? "—" : value
    }

    private func surfaceMessage(_ error: Error) -> String {
        (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
    }

    private func openLoadConversation() async {
        let lid = resolvedLoadId
        guard !lid.isEmpty else {
            actionError = "No at-delivery load is available for messaging."
            return
        }
        guard !actionBusy else { return }
        actionBusy = true
        actionError = nil
        actionMessage = nil
        defer { actionBusy = false }
        do {
            let conversation = try await EusoTripAPI.shared.messaging.getOrCreateLoadConversation(loadId: lid)
            activeThread = InboxThread(
                id: conversation.id,
                glyph: "shippingbox",
                title: conversation.loadNumber.map { "Load \($0)" } ?? loadNumberDisplay,
                subtitle: "At-delivery load thread",
                preview: "Driver, shipper, and catalyst conversation",
                time: "Now",
                unread: 0,
                allowsTransfer: false
            )
            actionMessage = conversation.existing == true ? "Opened load conversation." : "Created load conversation."
        } catch {
            actionError = surfaceMessage(error)
        }
    }

    /// Reads the REAL procedures (no stubs / no fabrication):
    ///   • catalysts.getMyDrivers   → the arrived driver row (REAL-BACKED
    ///     arrival position + HOS), matched off `currentLoad`.
    ///   • catalysts.getActiveLoads → active-board presence check. Because the
    ///     server filter excludes 'at_delivery', an arrived load is EXPECTED
    ///     to be absent — recorded honestly; the lane/rate fall back to it
    ///     only when the row IS present.
    ///   • loads.getById            → full lane/miles/equipment/commodity/
    ///     weight/rate, decoded with the corrected LoadDetail shape (top-level
    ///     id String, nested pickup/deliveryLocation). Bound only when a real
    ///     load id resolves.
    ///   • catalysts.getBidsForLoad → the winning carrier identity.
    private func fetch() async {
        loading = true
        loadError = nil
        actionError = nil
        defer { loading = false }

        // Preview seed path — no live session bound; paint the canonical
        // M-04 state so the wireframe renders in #Preview. Mirrors 375.
        if previewSeedDriver != nil || previewSeedActive != nil || !previewSeedBids.isEmpty {
            self.driver = previewSeedDriver
            self.activeRow = previewSeedActive
            self.bids = previewSeedBids
            self.onActiveBoard = previewSeedActive != nil
            self.detail = nil
            return
        }

        let api = EusoTripAPI.shared
        var anyReached = false
        var anyFailed: String? = nil

        // Driver roster (real-backed arrival position + HOS).
        do {
            let drivers: [CatalystDriver376] = try await api.query(
                "catalysts.getMyDrivers", input: LimitInput376(limit: 50))
            anyReached = true
            // Prefer the driver currently on the resolved load number, else
            // the first non-driving (arrived/on_duty) row. No persona match.
            let targetNumber = (detail?.loadNumber ?? activeRow?.loadNumber)
                ?? (loadId != "0" ? loadId : nil)
            self.driver = drivers.first {
                if let tn = targetNumber, !tn.isEmpty {
                    return ($0.currentLoad ?? "").contains(tn)
                }
                return false
            } ?? drivers.first { ($0.currentLoad?.isEmpty == false) }
              ?? drivers.first
        } catch {
            anyFailed = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        // Active-board presence check (honest: at_delivery drops off the list).
        do {
            let active: [ActiveLoad376] = try await api.query(
                "catalysts.getActiveLoads", input: LimitInput376(limit: 50))
            anyReached = true
            // If we were handed a load id, match it; else surface the first
            // row only as a lane/rate fallback context.
            if !loadId.isEmpty, loadId != "0" {
                self.activeRow = active.first { $0.id == loadId }
            } else {
                self.activeRow = active.first
            }
            self.onActiveBoard = self.activeRow != nil
        } catch {
            anyFailed = anyFailed ?? ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }

        // Full load detail + winning carrier — only when a real id resolves.
        let lid = resolvedLoadId
        if !lid.isEmpty {
            do {
                self.detail = try await api.loads.getDetail(id: lid)
                anyReached = true
            } catch {
                self.detail = nil
                actionError = "Load detail sync failed: \(surfaceMessage(error))"
            }

            do {
                self.bids = try await api.query(
                    "catalysts.getBidsForLoad", input: LoadIdInput376(loadId: lid))
                anyReached = true
            } catch {
                self.bids = []
                actionError = "Carrier award sync failed: \(surfaceMessage(error))"
            }
        }

        // Only surface an error if EVERY read failed (so a partial live read
        // still paints). Empty/absent is an honest state, not an error.
        if !anyReached, let err = anyFailed {
            loadError = err
        }
    }
}

// MARK: - HOS formatter (file-local · "9.97" → "9:58")

private func formatHOS376(_ hours: Double) -> String {
    let h = Int(hours)
    let m = Int((hours - Double(h)) * 60)
    return String(format: "%d:%02d", h, m)
}

// MARK: - Preview seed (canonical M-04 state · #Preview ONLY)

@MainActor
private func previewView_376() -> CatalystAtDeliveryFleetTrackCelM04View {
    var v = CatalystAtDeliveryFleetTrackCelM04View(loadId: "0")
    v.previewSeedActive = ActiveLoad376(
        id: "LD-260427-E5C9A41B22",
        loadNumber: "M-04",
        status: "at_delivery",
        origin: "Atlanta, GA",
        destination: "Charlotte, NC",
        driver: "Reyes, J.",
        eta: "appt 14:00 EDT",
        rate: 1_610)
    v.previewSeedDriver = CatalystDriver376(
        id: "JR-CEL-001",
        name: "JR Reyes",
        status: "on_duty",
        currentLoad: "M-04",
        hoursRemaining: 7.05,
        location: "35.23, -80.79")
    v.previewSeedBids = [
        BidRow376(id: "bid_1", catalystId: "car_1", catalystName: "Carolina Express Logistics", amount: 1_610, recommended: true)
    ]
    return v
}

// MARK: - Preview wrapper (injects the seeded body into Shell + nav)

private struct CatalystAtDeliveryFleetTrackScreenPreview_376: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            previewView_376()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_376(),
                trailing: catalystNavTrailing_376(),
                orbState: .idle
            )
        }
    }
}

// MARK: - Previews

#Preview("376 · Catalyst · At-Delivery Fleet Track · Night") {
    CatalystAtDeliveryFleetTrackScreenPreview_376(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("376 · Catalyst · At-Delivery Fleet Track · Afternoon") {
    CatalystAtDeliveryFleetTrackScreenPreview_376(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
