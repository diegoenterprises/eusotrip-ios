//
//  373_CatalystAwardedCelM04.swift
//  EusoTrip — Catalyst · Awarded (M04) · bespoke port of §369.
//
//  Wireframe slot: 03 Catalyst / 373 Catalyst Awarded Cel M04.
//  Catalyst-vantage AWARDED-confirmed receipt — the consumer side of
//  the §368 shipper AWARD-COMMIT. The shipper accepted CEL's winning
//  bid; this surface receives the tender via the loadLifecycle
//  BIDDING→AWARDED fan-out, surfaces the locked economics, the post-award
//  roster (the awarded carrier + every losing competitor), and a CEL-fleet
//  driver-assign candidate strip.
//
//  Server wiring (no stubs / no fake data — EVERY visible business value
//  binds to a real tRPC proc, or paints "-"/"—" / a real EusoEmptyState
//  until it resolves). The figma-anchor `private let` constants
//  (originCity, destinationCity, laneMiles, equipmentLabel, catalystName,
//  catalystShortCode, lost2/3/4, driverCandidates) are DELETED — there is
//  no hardcoded display data left on this surface.
//
//    • `loads.getById` ({ id }) → LoadsAPI.LoadDetail
//        Lane (pickupLocation/deliveryLocation.cityState · laneDisplay),
//        miles (distance · distanceDisplay), equipment (equipmentType),
//        commodity (commodityName ?? commodity ?? cargoType label),
//        lifecycle status, pickup/delivery reference coordinates
//        (top-level pickupCoord/deliveryCoord, merged into
//        pickupLocation.lat/lng by LoadDetail's decoder — audit M3),
//        resolved parties (driver → DRIVER ASSIGN cell, shipper →
//        initials disc + MESSAGE CTA label — 2026-06-09).
//    • `catalysts.getAcceptedBid` ({ loadId }) → AcceptedBid_373 or null
//        CEL's winning bid amount + the shipper's posted target `rate`;
//        `rate - amount` = the win headroom. Spine of the screen.
//    • `catalysts.getBidsForLoad` ({ loadId }) → [BidRow_373]
//        Every bid on the load. Losers = rows whose stripped "bid_" id
//        != the accepted-bid id; CEL rank = price-sorted index + 1.
//    • `catalysts.getMyDrivers` ({ limit }) → [CatalystAPI.FleetDriver]
//        CEL-fleet driver-assign candidates: name, HOS hours remaining,
//        honest availability (drivers.status); raw GPS is not converted
//        into route proximity without server projection.
//    • `catalysts.getProfile` (no input) → CelIdentity_373
//        CEL session carrier identity (company name; DOT/MC available).
//        Short code derived client-side from the company-name initials.
//
//  Honest backend gaps (rendered as "—", never fabricated):
//    • Driver ETA-to-pickup — no routed-ETA proc → "ETA —".
//    • Tender accept-by deadline / 24h window — no column / no proc →
//      "Tender window: pending".
//    • Driver "TENTATIVE" availability — no such drivers.status value;
//      mapped honestly to AVAILABLE / ON LOAD / OFF DUTY.
//  Driver route proximity remains pending until a server observation is
//  projected onto the exact canonical route plan.
//
//  Action wiring:
//    • ACKNOWLEDGE TENDER → catalysts.acknowledgeTender audit row.
//    • ASSIGN DRIVER      → catalysts.assignDriver with ownership, fleet,
//                            lock, audit and realtime fan-out gates.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - tRPC decode shapes

/// `catalysts.getAcceptedBid` envelope (server catalysts.ts:1122). `id`
/// is a BARE numeric bid id ("42") — NOT "bid_42"; strip the "bid_"
/// prefix off `BidRow_373.id` before matching it against this.
private struct AcceptedBid_373: Decodable {
    let id: String?
    let loadId: String?
    let amount: Double?       // CEL's awarded bid amount
    let status: String?       // "accepted"
    let notes: String?
    let submittedAt: String?
    let loadNumber: String?
    let rate: Double?         // shipper's posted target rate
}

/// One bid row from `catalysts.getBidsForLoad` (server catalysts.ts:3528).
/// Field-identical to ShipperAPI.Bid; decoded file-locally because the
/// shipped wrapper targets the shipper-gated `shippers.getBidsForLoad`.
private struct BidRow_373: Decodable, Identifiable, Hashable {
    let id: String            // "bid_<n>" — strip "bid_" to match getAcceptedBid.id
    let catalystId: String    // "car_<n>"
    let catalystName: String
    let dotNumber: String
    let safetyScore: Double    // server honest-empty 0
    let amount: Double
    let transitTime: String    // server honest-empty ""
    let submittedAt: String
    let message: String
    let recommended: Bool
}

/// CEL session carrier identity from `catalysts.getProfile` (server
/// catalysts.ts:1334). Decodes only the fields this surface uses; the
/// server returns a wider envelope (Decodable ignores the rest).
private struct CelIdentity_373: Decodable, Hashable {
    let companyName: String?
    let dotNumber: String?
    let mcNumber: String?
}

// File-local tRPC inputs.
private struct LoadIdInput_373: Encodable { let loadId: String }
private struct EmptyInput_373: Encodable {}
private struct TenderAckInput_373: Encodable { let loadId: String; let ackedAtIso: String }
private struct TenderAckResult_373: Decodable { let success: Bool; let loadId: String; let ackedAt: String? }
private struct AssignDriverInput_373: Encodable { let loadId: String; let driverId: String; let vehicleId: String?; let notes: String? }
private struct AssignDriverResult_373: Decodable { let success: Bool; let loadId: String; let driverId: String; let assignedAt: String }

// MARK: - Identity-row rank (catalyst-vantage AWARDED-confirmed roster)

private enum IdentityRowRank_373: Equatable {
    case ourselvesAwarded     // awarded carrier · filled gradient disc · AWARDED chip · 100%
    case competitorLost(Int)  // losing competitor · descending opacity by position
}

// MARK: - Local gradients (file-private · in-module symbols only)

private let eusoFaint_373 = LinearGradient(
    colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
    startPoint: .leading, endPoint: .trailing)

private let eusoWash_373 = LinearGradient(
    colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.14)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

// MARK: - Screen wrapper (Shell + catalyst BottomNav copied from 305)

struct CatalystAwardedCelM04Screen: View {
    let theme: Theme.Palette
    let loadId: String

    init(theme: Theme.Palette, loadId: String = "0") {
        self.theme = theme
        self.loadId = loadId
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystAwardedCelM04Body(loadId: loadId)
        } nav: {
            BottomNav(
                leading: catalystNavLeading_373(),
                trailing: catalystNavTrailing_373(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_373() -> [NavSlot] {
    CarrierNavRoute.leading(current: .loads)
}

private func catalystNavTrailing_373() -> [NavSlot] {
    CarrierNavRoute.trailing(current: .loads)
}

// MARK: - Body

private struct CatalystAwardedCelM04Body: View {
    let loadId: String
    @Environment(\.palette) private var palette

    // Live server-bound state — no hardcoded display anchors remain.
    @State private var award: AcceptedBid_373? = nil
    @State private var load: LoadsAPI.LoadDetail? = nil
    @State private var bids: [BidRow_373] = []
    @State private var drivers: [CatalystAPI.FleetDriver] = []
    @State private var hosEvidence: [HOSFleetDriver] = []
    @State private var identity: CelIdentity_373? = nil

    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var actionBusy: Bool = false
    @State private var actionError: String? = nil
    @State private var actionMessage: String? = nil
    @State private var showDriverPicker: Bool = false

    /// Exact renderer-safe members of the server-owned route plan. Members
    /// stay independent; this surface never joins or authors geometry.
    @State private var canonicalRouteLines: [[HereLatLng]] = []
    @State private var canonicalRouteStatus: String?
    @State private var canonicalRouteVersion: Int?
    @State private var canonicalResolvedPurpose: CanonicalRoutePlanClient.Purpose?
    @State private var canonicalRouteMode: CanonicalRoutePlanClient.Mode?

    // MARK: Derived — CEL identity (from catalysts.getProfile)

    /// Real company name, or "-" when the session has no resolved company.
    private var catalystName: String {
        let n = identity?.companyName?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "-" : n
    }

    /// Short code derived from the company-name initials (first letter of
    /// up to 3 leading words). No short-code column exists. "-" when blank.
    private var catalystShortCode: String {
        let n = identity?.companyName?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !n.isEmpty else { return "-" }
        let initials = n
            .split(separator: " ")
            .prefix(3)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        return initials.isEmpty ? "-" : initials
    }

    // MARK: Derived — lane / miles / equipment / commodity (from loads.getById)

    /// The real "<origin city, ST> → <destination city, ST>" lane from
    /// loads.getDetail; em-dash forms ("Origin → —" / "—") when ungeocoded.
    private var laneHeadline: String {
        load?.laneDisplay ?? "—"
    }
    private var originCityState: String { load?.pickupLocation?.cityState ?? "" }
    private var destinationCityState: String { load?.deliveryLocation?.cityState ?? "" }

    /// Server-reported commercial lane miles. This value is not treated as
    /// canonical route geometry or route progress.
    private var laneMiles: Int? {
        guard let d = load?.distance, d > 0 else { return nil }
        return Int(d.rounded())
    }
    /// "245 mi" / "—".
    private var laneMilesDisplay: String { load?.distanceDisplay ?? "—" }

    /// Equipment / trailer type — "—" when the shipper never specified.
    private var equipmentDisplay: String {
        let eq = load?.equipmentType?.trimmingCharacters(in: .whitespaces) ?? ""
        return eq.isEmpty ? "—" : eq
    }
    /// Lifecycle header equipment suffix — empty when unknown.
    private var equipmentSuffix: String {
        let eq = load?.equipmentType?.trimmingCharacters(in: .whitespaces) ?? ""
        return eq.isEmpty ? "" : " · \(eq.uppercased())"
    }

    /// Commodity / cargo — prefer the specific name; treat the server's
    /// forced "general" cargoType with no name as the empty case ("—").
    private var commodityDisplay: String {
        if let c = load?.commodityName?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        if let c = load?.commodity?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        let cargo = load?.cargoType?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        if cargo.isEmpty || cargo == "general" { return "—" }
        return cargo.capitalized
    }

    // MARK: Derived — economics (from getAcceptedBid + loads.getById)

    private var awardedAmount: Double? {
        guard let a = award?.amount, a > 0 else { return nil }
        return a
    }
    private var targetRate: Double? {
        guard let r = award?.rate, r > 0 else { return nil }
        return r
    }
    private var awardedAmountDisplay: String {
        guard let a = awardedAmount else { return "-" }
        return "$\(Int(a.rounded()).formatted(.number))"
    }
    private var winDisplay: String {
        guard let a = awardedAmount, let t = targetRate else { return "-" }
        let win = t - a
        let sign = win >= 0 ? "+" : "−"
        return "\(sign)$\(Int(abs(win).rounded()).formatted(.number))"
    }
    private var winVsTargetLine: String {
        guard let t = targetRate else { return "vs target" }
        return "vs $\(Int(t.rounded()).formatted(.number)) target"
    }
    /// $/mi = awarded amount ÷ real lane miles. "-" when either is absent.
    private var rpmDisplay: String {
        guard let a = awardedAmount, let d = load?.distance, d > 0 else { return "-" }
        return String(format: "$%.2f/mi", a / d)
    }
    private var loadNumberDisplay: String {
        if let n = award?.loadNumber, !n.isEmpty { return n }
        if let n = load?.loadNumber, !n.isEmpty { return n }
        return "-"
    }
    private var awardConfirmed: Bool {
        (award?.status ?? "").lowercased() == "accepted"
    }

    // MARK: Derived — losing bids + CEL rank (from getBidsForLoad + getAcceptedBid)

    /// Bare numeric id of CEL's accepted bid ("42"); used to filter the
    /// "bid_42" prefixed rows out of the loser set.
    private var acceptedBidId: String? {
        let raw = award?.id?.trimmingCharacters(in: .whitespaces) ?? ""
        return raw.isEmpty ? nil : raw
    }
    private func strippedBidId(_ id: String) -> String {
        id.hasPrefix("bid_") ? String(id.dropFirst("bid_".count)) : id
    }
    /// Every competing bid that is NOT CEL's accepted bid, price-sorted
    /// ascending (lowest first).
    private var loserBids: [BidRow_373] {
        bids
            .filter { strippedBidId($0.id) != acceptedBidId }
            .sorted { $0.amount < $1.amount }
    }
    /// CEL bid rank "1/4": total = all bids; rank = price-sorted index+1.
    /// nil-rank ("—") when the accepted bid isn't in the list; whole
    /// segment omitted when there are no bids.
    private var rankSegment: String? {
        let total = bids.count
        guard total > 0 else { return nil }
        let sorted = bids.sorted { $0.amount < $1.amount }
        if let aid = acceptedBidId,
           let idx = sorted.firstIndex(where: { strippedBidId($0.id) == aid }) {
            return "CEL bid was rank \(idx + 1)/\(total)"
        }
        return "CEL bid was rank —/\(total)"
    }

    // MARK: Derived — assignment + shipper identity (from loads.getById
    // resolved-party slots; 2026-06-09 — closes the last hardcoded
    // display copy on this surface: "pending/Naomi → fleet", "ARMED",
    // the "DU" disc and the "MESSAGE DIEGO" CTA label).

    /// True only when the load row carries a real driver assignment.
    private var driverAssigned: Bool {
        load?.driver != nil || load?.driverId != nil
    }
    /// "assigned"/"pending" straight off the load row — never a claim.
    private var driverAssignValue: String { driverAssigned ? "assigned" : "pending" }
    /// Assigned → the REAL driver name (resolved party); unassigned →
    /// honest live candidate count from catalysts.getMyDrivers.
    private var driverAssignFooter: String {
        if let n = load?.driver?.name?.trimmingCharacters(in: .whitespaces), !n.isEmpty {
            return n
        }
        if driverAssigned { return "driver on file" }
        guard !drivers.isEmpty else { return "no fleet candidates" }
        return "\(drivers.count) candidate\(drivers.count == 1 ? "" : "s")"
    }
    /// "ARMED" only when the accepted bid is really accepted; "—" until.
    private var armPickupValue: String { awardConfirmed ? "ARMED" : "—" }

    /// Shipper-of-record initials from the resolved party ("—" until).
    private var shipperInitialsDisplay: String {
        let i = load?.shipper?.initials?.trimmingCharacters(in: .whitespaces) ?? ""
        return i.isEmpty ? "—" : i
    }
    /// "MESSAGE <FIRSTNAME>" from the real shipper party, generic
    /// "MESSAGE SHIPPER" when unresolved — never a hardcoded name.
    private var messageShipperLabel: String {
        let first = load?.shipper?.name?
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "MESSAGE SHIPPER" : "MESSAGE \(first.uppercased())"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleRow
                iridescentHairline

                if loading {
                    skeletonBody
                } else if let err = loadError {
                    errorBanner(err)
                } else {
                    awardedConfirmedPill
                    eyebrowRow
                    kpiQuartet
                    // Award economics must read the immutable quote version
                    // bound to this exact load, route, capacity allocation,
                    // policies, platform fee, and payouts. Bid/load rate
                    // fields remain historical context only.
                    PricedRouteQuoteAuthorityPanel(
                        subjectType: .load,
                        subjectId: Int(loadId) ?? 0
                    )
                    lifecycleStrip
                    laneMap
                    rosterCard
                    driverAssignStrip
                    actionRibbon
                    actionFeedback
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await fetch() }
        .eusoRefreshable { await fetch() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await fetch() }
        }
        .sheet(isPresented: $showDriverPicker) {
            assignDriverSheet
                .environment(\.palette, palette)
        }
    }

    // MARK: - TopBar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                EusoTripBrandMark(size: 12)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DISPATCH · AWARDED · CEL ACK")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text(loadNumberDisplay)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var titleRow: some View {
        HStack(alignment: .center) {
            Button {
                // 373 is push-presented inside CarrierSurface's screenStack
                // (not a sheet). Post the canonical .eusoRoleNavBack which
                // CarrierSurface listens for → popOne(). Matches the 305
                // back-chevron pattern.
                NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            Text(laneHeadline)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .padding(.trailing, 4)
        }
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(eusoFaint_373)
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: - Awarded-confirmed pill (handshake-with-receipt-tick · §369 2nd member)

    private var awardedConfirmedPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
            Text("AWARDED · CEL ACK · ARM PICKUP")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Text(awardConfirmed ? "CONFIRMED" : "PENDING")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .background(LinearGradient.primary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Eyebrow row (gradient wash · founder DU pin)

    /// Trailing tokens for the mono detail line — equipment, commodity,
    /// awarded amount, CEL rank, tender window — joined with " · ", each
    /// segment omitted when its underlying value is empty.
    private var eyebrowDetailLine: String {
        var parts: [String] = []
        parts.append(equipmentDisplay)                       // "—" when unknown
        if commodityDisplay != "—" { parts.append(commodityDisplay) }
        parts.append("awarded \(awardedAmountDisplay)")
        if let rank = rankSegment { parts.append(rank) }
        parts.append("Tender window: pending")               // no real deadline source
        return parts.joined(separator: " · ")
    }

    private var eyebrowRow: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AWARDED TO \(catalystShortCode) · \(loadNumberDisplay) · WIN \(winDisplay) \(winVsTargetLine)")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(laneHeadline) · \(laneMilesDisplay)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(eyebrowDetailLine)
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Shipper-of-record disc — REAL initials from the resolved
            // shipper party on loads.getById; "—" until it resolves.
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 24, height: 24)
                Text(shipperInitialsDisplay)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(.white)
            }
            .padding(12)
        }
        .background(eusoWash_373)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(eusoFaint_373, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - KPI quartet (TENDER / WIN / DRIVER ASSIGN / ARM PICKUP)

    private var kpiQuartet: some View {
        HStack(spacing: 8) {
            kpiCell(eyebrow: "TENDER", value: awardedAmountDisplay, footer: "CEL accepted")
            kpiCell(eyebrow: "WIN", value: winDisplay, footer: winVsTargetLine)
            kpiCell(eyebrow: "DRIVER ASSIGN", value: driverAssignValue, footer: driverAssignFooter)
            kpiCell(eyebrow: "ARM PICKUP", value: armPickupValue, footer: rpmDisplay)
        }
    }

    private func kpiCell(eyebrow: String, value: String, footer: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(footer)
                .font(.system(size: 8))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(eusoFaint_373, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Lifecycle strip (AWARDED ringed-active · 8 nodes)

    /// Map the live loads.getById status onto the 8-node lifecycle index.
    /// Defaults to AWARDED (2) for this awarded-state surface when the
    /// status is unrecognized.
    private var lifecycleIdx: Int {
        switch (load?.status ?? "").lowercased() {
        case "posted", "draft":                       return 0
        case "bidding":                               return 1
        case "awarded", "assigned", "accepted":       return 2
        case "en_route_pickup", "at_pickup", "loading", "picked_up":
            return 3
        case "in_transit", "en_route", "en_route_delivery":
            return 4
        case "delivered", "at_delivery", "unloading": return 5
        case "pod", "paperwork", "documents":         return 6
        case "complete", "completed", "paid", "closed", "settled":
            return 7
        default:                                      return 2
        }
    }

    private var lifecycleStrip: some View {
        let labels = ["POST", "BID", "AWRD", "PICK", "TRAN", "DELV", "PAPR", "CLSD"]
        let currentIdx = lifecycleIdx
        return VStack(alignment: .leading, spacing: 10) {
            Text("LIFECYCLE\(equipmentSuffix)")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            GeometryReader { geo in
                let step = labels.count > 1 ? geo.size.width / CGFloat(labels.count - 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.borderFaint).frame(height: 2)
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .frame(width: step * CGFloat(currentIdx), height: 2)
                    ForEach(Array(labels.enumerated()), id: \.offset) { idx, _ in
                        node(idx: idx, currentIdx: currentIdx)
                            .position(x: step * CGFloat(idx), y: 11)
                    }
                }
            }
            .frame(height: 22)

            HStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                    Text(label)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.3)
                        .foregroundStyle(idx == currentIdx
                                         ? AnyShapeStyle(LinearGradient.diagonal)
                                         : AnyShapeStyle(idx < currentIdx ? palette.textPrimary : palette.textTertiary))
                        .frame(maxWidth: .infinity)
                }
            }

            Text("Awarded · CEL receives tender · arm pickup · assign driver")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func node(idx: Int, currentIdx: Int) -> some View {
        Group {
            if idx == currentIdx {
                ZStack {
                    Circle().stroke(LinearGradient.diagonal, lineWidth: 2).frame(width: 22, height: 22)
                    Circle().fill(LinearGradient.diagonal).frame(width: 16, height: 16)
                    Circle().fill(Color.white).frame(width: 6, height: 6)
                }
            } else if idx < currentIdx {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 12, height: 12)
            } else {
                Circle()
                    .fill(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint, lineWidth: 1.2))
                    .frame(width: 10, height: 10)
            }
        }
    }

    // MARK: - Lane map (solid post-award route · LANE LOCKED banner)

    /// Origin pin label — city/state when geocoded, else "Pickup".
    private var originPinLabel: String {
        originCityState.isEmpty ? "Pickup" : originCityState
    }
    /// Destination pin label — city/state when geocoded, else "Dest".
    private var destPinLabel: String {
        destinationCityState.isEmpty ? "Dest" : destinationCityState
    }
    /// LANE LOCKED banner — real miles when present, em-dash otherwise.
    private var laneLockedBanner: String {
        "LANE LOCKED · \(laneMilesDisplay) · Tender window: pending"
    }

    /// Resolves the awarded load's REAL pickup → delivery coordinates off
    /// the `loads.getById` envelope (`pickupLocation.lat/.lng` +
    /// `deliveryLocation.lat/.lng` — the slots the server self-heals via
    /// HERE geocode). Returns nil (→ honest "awaiting coords" placeholder)
    /// when either endpoint hasn't been geocoded yet. The exact gate
    /// 502_CatalystMatchDetail.laneCoords uses — non-nil + non-zero on
    /// both lat/lng. No fabrication, no client-side place-name geocoding.
    private var laneCoords: (pickupLat: Double, pickupLng: Double,
                             deliveryLat: Double, deliveryLng: Double)? {
        guard let p = load?.pickupLocation,
              let d = load?.deliveryLocation,
              let pickup = LatLongParser.validatedCoordinate(
                  latitude: p.lat,
                  longitude: p.lng
              ),
              let delivery = LatLongParser.validatedCoordinate(
                  latitude: d.lat,
                  longitude: d.lng
              ) else { return nil }
        return (
            pickup.latitude, pickup.longitude,
            delivery.latitude, delivery.longitude
        )
    }

    /// Real HERE map of the awarded lane (replaces the former decorative
    /// Canvas bezier). Renders ONLY when the server provided real
    /// pickup/delivery coords; otherwise an honest "awaiting coords"
    /// placeholder — never a fabricated route. Route lines appear only after
    /// an exact canonical mode plan is operational and renderer-safe.
    @ViewBuilder
    private var laneMap: some View {
        if let coords = laneCoords {
            let midLat = (coords.pickupLat + coords.deliveryLat) / 2
            let midLng = (coords.pickupLng + coords.deliveryLng) / 2
            let mapTransportMode = EusoTripMapTransportMode(
                canonicalValue: canonicalRouteMode?.rawValue ?? load?.transportMode
            )
            let requestedPurpose = canonicalRoutePurpose
            let markerLayer = HereMapLayer.markers([
                .init(at: .init(coords.pickupLat, coords.pickupLng),
                      kind: .pickup, label: originPinLabel),
                .init(at: .init(coords.deliveryLat, coords.deliveryLng),
                      kind: .delivery, label: destPinLabel)
            ])
            let mapLayers: [HereMapLayer] = canonicalRouteLines.enumerated().map { index, line in
                .eusoRoute(
                    polyline: line,
                    state: canonicalResolvedPurpose == .activeJob ? .active : .planned,
                    label: index == 0
                        ? "Eusorone \(mapTransportMode.rawValue) route plan version \(canonicalRouteVersion ?? 0)"
                        : nil
                )
            } + [markerLayer]
            ZStack(alignment: .topLeading) {
                HereLiveMapView(
                    center: canonicalRouteLines.lazy.compactMap(\.first).first
                        ?? .init(midLat, midLng),
                    zoom: 6,
                    route: [],
                    baseLayers: mapLayers,
                    addOns: mapTransportMode == .truck ? .shipperTracking : .weather,
                    activeJob: requestedPurpose == .activeJob,
                    mapModeContext: .unconfirmed(mapTransportMode)
                )
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

                // AWARDED chip overlay (top-right · single post-award member)
                HStack {
                    Spacer(minLength: 0)
                    Text("AWARDED")
                        .font(.system(size: 7, weight: .heavy))
                        .tracking(0.3)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 14)
                        .background(LinearGradient.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .padding(10)

                // LANE LOCKED banner (bottom-left)
                VStack(alignment: .leading, spacing: 4) {
                    Spacer(minLength: 0)
                    Text(laneLockedBanner)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.3)
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let canonicalRouteStatus {
                        canonicalRouteStatusPill(canonicalRouteStatus)
                    }
                }
                .padding(12)
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        } else {
            // Coord gate (Driver 013 / 502 pattern): no real fix on one or
            // both endpoints yet (awarded load carries only city names) —
            // honest placeholder, never a demo bezier, never a client-side
            // geocode of the city string.
            ZStack {
                VStack(spacing: 6) {
                    Image(systemName: "map")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                    Text("Awaiting lane coordinates")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(laneLockedBanner)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: - Roster card (awarded CEL + every losing competitor)

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("POST-AWARD ROSTER · \(bids.count) BID\(bids.count == 1 ? "" : "S")")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 6) {
                // The awarded CEL row (always rendered when there is an
                // accepted award; amount from the live getAcceptedBid).
                if award != nil {
                    identityRow(shortCode: catalystShortCode,
                                displayName: catalystName,
                                amount: Int((awardedAmount ?? 0).rounded()),
                                rank: .ourselvesAwarded)
                }

                // Losing competitors — real rows, price-sorted ascending.
                // Render ONLY as many as actually exist; never pad to 3.
                ForEach(Array(loserBids.enumerated()), id: \.element.id) { idx, bid in
                    identityRow(shortCode: shortCode(for: bid.catalystName),
                                displayName: bid.catalystName,
                                amount: Int(bid.amount.rounded()),
                                rank: .competitorLost(idx))
                }

                // Honest empty state — sole bidder / no competing bids.
                if loserBids.isEmpty {
                    competingBidsEmptyRow
                }
            }
        }
    }

    /// Compact, branded empty-row for the "no competing bids" case — reads
    /// as a real EusoEmptyState within the tight roster-row chrome.
    private var competingBidsEmptyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text(award == nil ? "No bids on this load yet" : "No competing bids — sole bidder")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Initials short code from a competitor name (first letter of up to
    /// 3 leading words). "-" when blank.
    private func shortCode(for name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return "-" }
        let initials = n
            .split(separator: " ")
            .prefix(3)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        return initials.isEmpty ? "-" : initials
    }

    private func identityRow(shortCode: String, displayName: String, amount: Int, rank: IdentityRowRank_373) -> some View {
        let opacity: Double = {
            switch rank {
            case .ourselvesAwarded:     return 1.00
            case .competitorLost(let i): return max(0.55, 0.88 - Double(i) * 0.14)
            }
        }()
        let isOurselves = rank == .ourselvesAwarded
        let amountText = amount > 0 ? "$\(amount.formatted(.number))" : "-"

        return HStack(spacing: 10) {
            ZStack {
                if isOurselves {
                    Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                } else {
                    Circle().strokeBorder(eusoFaint_373, lineWidth: 1.2).frame(width: 28, height: 28)
                }
                Text(shortCode)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(isOurselves ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(amountText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            if isOurselves {
                Text("AWARDED")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 16)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Text("LOST")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 10)
                    .frame(height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(eusoFaint_373, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .opacity(opacity)
    }

    // MARK: - Driver-assign candidate strip (CEL fleet · live getMyDrivers)

    private var driverAssignStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DRIVER ASSIGN · CEL FLEET CANDIDATES")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(palette.textTertiary)

            if drivers.isEmpty {
                driversEmptyRow
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(drivers.enumerated()), id: \.element.id) { idx, d in
                        candidateCell(d, isFirst: idx == 0)
                    }
                }
            }
        }
    }

    /// Honest empty state — no fleet drivers. A real branded empty-row,
    /// not three fabricated candidate cells.
    private var driversEmptyRow: some View {
        EusoEmptyState(
            systemImage: "person.crop.circle.badge.exclamationmark",
            title: "No fleet drivers available",
            subtitle: "Add drivers to the CEL fleet to assign this tender."
        )
        .frame(maxWidth: .infinity)
    }

    /// Driver availability chip mapped honestly from drivers.status.
    /// No "TENTATIVE" — that value does not exist in the schema.
    private func availabilityLabel(_ status: String) -> String {
        switch status.lowercased() {
        case "available", "active": return "AVAILABLE"
        case "driving", "on_load", "in_transit", "assigned": return "ON LOAD"
        case "off_duty": return "OFF DUTY"
        case "inactive", "suspended": return status.uppercased()
        case "": return "—"
        default: return status.uppercased()
        }
    }

    private func isAvailable(_ status: String) -> Bool {
        let s = status.lowercased()
        return s == "available" || s == "active"
    }

    /// Initials from a real driver name ("Last, F." → "LF" / "Jane Doe" → "JD").
    private func driverInitials(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: ",", with: " ")
        let initials = cleaned
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        return initials.isEmpty ? "—" : initials
    }

    /// HOS slug — "HOS 10h" / "HOS —" when no HOS event logged today.
    private func hosSlug(_ hours: Double?) -> String {
        guard let h = hours else { return "HOS —" }
        // Show one decimal only when fractional, else integer hours.
        if h == h.rounded() { return "HOS \(Int(h))h" }
        return String(format: "HOS %.1fh", h)
    }

    private func candidateCell(_ d: CatalystAPI.FleetDriver, isFirst: Bool) -> some View {
        let available = isAssignmentReady(d)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                ZStack {
                    if isFirst {
                        Circle().fill(LinearGradient.diagonal).frame(width: 16, height: 16)
                    } else {
                        Circle().fill(palette.borderFaint).frame(width: 16, height: 16)
                    }
                    Text(driverInitials(d.name))
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(isFirst ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
                }
                Text(d.name)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
            Text("\(hosSlug(currentDrivingHours(for: d))) · ROUTE PROJECTION PENDING")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
            // ETA has no real routed-ETA source — render "ETA —".
            Text("ETA — · \(availabilityLabel(d.status))")
                .font(.system(size: 7))
                .foregroundStyle(available ? palette.textSecondary : palette.textTertiary)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isFirst ? AnyShapeStyle(eusoFaint_373) : AnyShapeStyle(palette.borderFaint), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Action ribbon (3 CTAs · live tender / assignment)

    private var actionRibbon: some View {
        HStack(spacing: 8) {
            Button {
                Task { await acknowledgeTender() }
            } label: {
                Text(actionBusy ? "WORKING…" : "ACKNOWLEDGE TENDER")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(actionBusy || loadId.isEmpty || loadId == "0")

            Button {
                actionError = nil
                actionMessage = nil
                showDriverPicker = true
            } label: {
                Text(driverAssigned ? "REASSIGN DRIVER" : "ASSIGN DRIVER")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(eusoFaint_373, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(actionBusy || drivers.isEmpty)

            // Message the shipper-of-record via the canonical ESANG funnel.
            Button {
                NotificationCenter.default.post(
                    name: .esangOpenMeDetail,
                    object: "messages",
                    userInfo: ["loadId": loadId]
                )
            } label: {
                Text(messageShipperLabel)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var actionFeedback: some View {
        Group {
            if let actionError {
                Text(actionError)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .padding(Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.danger.opacity(0.35)))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            } else if let actionMessage {
                Text(actionMessage)
                    .font(EType.caption)
                    .foregroundStyle(Brand.blue)
                    .padding(Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.blue.opacity(0.35)))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
        }
    }

    private var assignDriverSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assign Driver")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text(loadNumberDisplay)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if actionBusy {
                    ProgressView().tint(Brand.blue)
                }
            }
            ScrollView {
                VStack(spacing: Space.s3) {
                    if drivers.isEmpty {
                        EusoEmptyState(systemImage: "person.crop.circle.badge.exclamationmark",
                                       title: "No fleet drivers available",
                                       subtitle: "Add drivers to the fleet before assigning this tender.")
                            .padding(.vertical, Space.s4)
                    }
                    ForEach(drivers) { driver in
                        assignDriverRow(driver)
                    }
                }
                .padding(.bottom, Space.s4)
            }
        }
        .padding(Space.s5)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func assignDriverRow(_ driver: CatalystAPI.FleetDriver) -> some View {
        let available = isAssignmentReady(driver)
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(available ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint))
                Text(driverInitials(driver.name))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(available ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(driver.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("\(availabilityLabel(driver.status)) · \(hosSlug(currentDrivingHours(for: driver))) · ROUTE PROJECTION PENDING")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                if !available {
                    Text(hosEligibility(for: driver).reason ?? "Driver is not currently available")
                        .font(EType.micro)
                        .foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button {
                Task { await assignDriver(driver) }
            } label: {
                Text("Assign")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 82, height: 34)
                    .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(actionBusy || !available)
            .opacity(available ? 1 : 0.45)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func acknowledgeTender() async {
        actionBusy = true
        actionError = nil
        actionMessage = nil
        defer { actionBusy = false }
        do {
            let result: TenderAckResult_373 = try await EusoTripAPI.shared.mutation(
                "catalysts.acknowledgeTender",
                input: TenderAckInput_373(loadId: loadId, ackedAtIso: ISO8601DateFormatter().string(from: Date()))
            )
            actionMessage = result.success ? "Tender acknowledged for load \(result.loadId)." : "Tender acknowledgement did not complete."
            await fetch()
        } catch {
            actionError = "Couldn't acknowledge tender: \(surfaceMessage(error))"
        }
    }

    private func assignDriver(_ driver: CatalystAPI.FleetDriver) async {
        actionBusy = true
        actionError = nil
        actionMessage = nil
        defer { actionBusy = false }
        do {
            let refreshedEvidence: [HOSFleetDriver] = try await EusoTripAPI.shared.queryNoInput("hos.getFleetHOS")
            hosEvidence = refreshedEvidence
            guard isAssignmentReady(driver) else {
                throw CatalystAwardAssignmentError_373.evidenceUnavailable
            }
            let result: AssignDriverResult_373 = try await EusoTripAPI.shared.mutation(
                "catalysts.assignDriver",
                input: AssignDriverInput_373(
                    loadId: loadId,
                    driverId: driver.id,
                    vehicleId: nil,
                    notes: "Assigned from Catalyst Awarded M04"
                )
            )
            guard result.success,
                  result.loadId == loadId,
                  result.driverId == driver.id else {
                throw CatalystAwardAssignmentError_373.unconfirmed
            }
            actionMessage = "Driver \(result.driverId) assigned to load \(result.loadId)."
            showDriverPicker = false
            await fetch()
        } catch {
            actionError = "Couldn't assign \(driver.name): \(surfaceMessage(error))"
        }
    }

    private func surfaceMessage(_ error: Error) -> String {
        let localized = error.localizedDescription
        return localized.isEmpty ? String(describing: error) : localized
    }

    // MARK: - Loading / error

    private var skeletonBody: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard).frame(height: 36)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard).frame(height: 88)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard).frame(height: 60)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard).frame(height: 120)
        }
        .redacted(reason: .placeholder)
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

    // MARK: - Canonical route authority

    private var canonicalRoutePurpose: CanonicalRoutePlanClient.Purpose {
        let normalized = (load?.status ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let active: Set<String> = [
            "assigned", "dispatched", "en_route", "enroute", "at_pickup",
            "loaded", "in_transit", "approaching_delivery", "at_receiver",
            "at_delivery", "unloading", "delivering"
        ]
        return active.contains(normalized) ? .activeJob : .planning
    }

    /// Sends only the persisted load subject and purpose. Mode, waypoints,
    /// asset profile, graph, source rights, evidence, and geometry are all
    /// resolved by the canonical server authority.
    @MainActor
    private func refreshCanonicalRoute() async {
        canonicalRouteLines = []
        canonicalRouteVersion = nil
        canonicalResolvedPurpose = nil
        canonicalRouteMode = nil
        canonicalRouteStatus = "Verified awarded route is still being prepared"
        guard let load, let numericId = Int(load.id), numericId > 0 else {
            canonicalRouteStatus = "Canonical route pending a persisted load identity"
            return
        }
        let expectedPurpose = canonicalRoutePurpose
        do {
            let result = try await CanonicalRoutePlanClient.shared.planLoad(
                id: numericId,
                purpose: expectedPurpose
            )
            switch result {
            case .persisted(let persisted):
                applyCanonicalRoute(persisted.route, expectedPurpose: expectedPurpose)
            case .pending(let pending):
                canonicalRouteStatus = pending.blockers.first?.message
                    ?? "Canonical mode-native route pending verified authority"
                await readExistingCanonicalRoute(loadId: numericId, expectedPurpose: expectedPurpose)
            }
        } catch {
            canonicalRouteStatus = error.eusoUserCopy
            await readExistingCanonicalRoute(loadId: numericId, expectedPurpose: expectedPurpose)
        }
    }

    @MainActor
    private func readExistingCanonicalRoute(
        loadId: Int,
        expectedPurpose: CanonicalRoutePlanClient.Purpose
    ) async {
        do {
            applyCanonicalRoute(
                try await CanonicalRoutePlanClient.shared.getBoundLoad(id: loadId),
                expectedPurpose: expectedPurpose
            )
        } catch {
            if canonicalRouteStatus == nil { canonicalRouteStatus = error.eusoUserCopy }
        }
    }

    @MainActor
    private func applyCanonicalRoute(
        _ route: CanonicalRoutePlanClient.BoundRoutePlan,
        expectedPurpose: CanonicalRoutePlanClient.Purpose
    ) {
        guard route.plan.purpose == expectedPurpose,
              let payload = route.rendererPayload else {
            canonicalRouteLines = []
            canonicalRouteVersion = nil
            canonicalResolvedPurpose = nil
            canonicalRouteMode = nil
            canonicalRouteStatus = "Canonical \(expectedPurpose.rawValue) route exists but is not released for rendering"
            return
        }
        canonicalRouteLines = payload.lines
        canonicalRouteVersion = payload.identity.version
        canonicalResolvedPurpose = route.plan.purpose
        canonicalRouteMode = payload.identity.mode
        canonicalRouteStatus = nil
    }

    private func canonicalRouteStatusPill(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(palette.bgCard.opacity(0.92))
            .overlay(Capsule().strokeBorder(Brand.warning.opacity(0.45)))
            .clipShape(Capsule())
            .accessibilityLabel(message)
    }

    // MARK: - Network

    private func fetch() async {
        loading = true
        loadError = nil
        defer { loading = false }
        guard !loadId.isEmpty, loadId != "0" else {
            // No load context — leave all @State nil/[]; every value
            // renders "-"/"—". No fabrication.
            canonicalRouteLines = []
            canonicalRouteVersion = nil
            canonicalResolvedPurpose = nil
            canonicalRouteMode = nil
            canonicalRouteStatus = "Canonical route pending a persisted load identity"
            return
        }
        let api = EusoTripAPI.shared
        do {
            // Fire all five reads concurrently — independent (same loadId /
            // session): award + load + bids + driver roster + CEL identity.
            async let awardTask: AcceptedBid_373?           = api.query("catalysts.getAcceptedBid", input: LoadIdInput_373(loadId: loadId))
            async let loadTask:  LoadsAPI.LoadDetail?        = api.loads.getDetail(id: loadId)
            async let bidsTask:  [BidRow_373]                = api.query("catalysts.getBidsForLoad", input: LoadIdInput_373(loadId: loadId))
            async let driversTask: [CatalystAPI.FleetDriver] = api.catalyst.getMyDrivers(limit: 5)
            async let hosTask: [HOSFleetDriver]              = api.queryNoInput("hos.getFleetHOS")
            async let identityTask: CelIdentity_373?         = api.query("catalysts.getProfile", input: EmptyInput_373())

            // Award is the spine of the screen — if it throws, surface the
            // error banner (the existing Retry path).
            self.award = try await awardTask

            // The other four are enrichment: a failure on any one must NOT
            // blank the whole surface — it degrades that section to its
            // honest empty-state ("—" / empty row).
            self.load     = (try? await loadTask)     ?? nil
            self.bids     = (try? await bidsTask)     ?? []
            self.drivers  = (try? await driversTask)  ?? []
            do {
                self.hosEvidence = try await hosTask
            } catch {
                self.hosEvidence = []
                self.actionError = "Current company HOS evidence could not refresh. Driver assignment is held."
            }
            self.identity = (try? await identityTask) ?? nil

            Task { @MainActor in await refreshCanonicalRoute() }
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func hosEvidence(for driver: CatalystAPI.FleetDriver) -> HOSFleetDriver? {
        hosEvidence.first { $0.driverId == driver.id }
    }

    private func hosEligibility(for driver: CatalystAPI.FleetDriver) -> HOSAssignmentEligibility {
        hosEvidence(for: driver)?.assignmentEligibility() ?? .notTracked
    }

    private func isAssignmentReady(_ driver: CatalystAPI.FleetDriver) -> Bool {
        isAvailable(driver.status) && hosEligibility(for: driver) == .eligible
    }

    private func currentDrivingHours(for driver: CatalystAPI.FleetDriver) -> Double? {
        guard let evidence = hosEvidence(for: driver), evidence.hasCurrentObservation(),
              let hours = evidence.hoursAvailable?.drivingRemaining,
              hours.isFinite, hours >= 0 else { return nil }
        return hours
    }
}

private enum CatalystAwardAssignmentError_373: LocalizedError {
    case evidenceUnavailable
    case unconfirmed

    var errorDescription: String? {
        switch self {
        case .evidenceUnavailable:
            return "Current, complete HOS evidence is unavailable. Refresh before assigning this load."
        case .unconfirmed:
            return "The assignment response was not an exact confirmation. Refresh before notifying the driver."
        }
    }
}

// MARK: - Previews

#Preview("373 · Catalyst · Awarded (M04) · Afternoon") {
    CatalystAwardedCelM04Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("373 · Catalyst · Awarded (M04) · Night") {
    CatalystAwardedCelM04Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
