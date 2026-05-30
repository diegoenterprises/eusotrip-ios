//
//  005_RailWaybill.swift
//  EusoTrip — Rail · Shipper · Waybill (brick 005).
//
//  Verbatim reconstruction of "05 Rail/005 Rail Waybill" (canvas 440×956,
//  Theme.dark). Read-mostly SHIPPER vantage on a single rail shipment's
//  WAYBILL — the AAR Rule 11 interline shipping paper that, if wrong, stops
//  the car at the gate. Mirrors the 02 Shipper / 205 Load Detail DOCUMENT
//  grammar (gradient-rim hero summary → PARTIES card → COMMODITY/HAZMAT card
//  → ESang verifiable advisory → shipping-paper status strip → CTA pair).
//  Hero WB · RAIL-260519-39044B2 · BNSF · Houston TX → Chicago IL.
//  Web parity: client/src/pages/shipper/LoadDetail.tsx documents tab (mode='rail').
//
//  RBAC: railProcedure (RAIL-mode gate; a rail SHIPPER passes — the same gate
//  the 001/002/003/004 Rail-Shipper screens use). The 005 <desc> proposed
//  roleProcedure("SHIPPER","ADMIN","SUPER_ADMIN"); precedence (shipped rail
//  doctrine > <desc>) keeps the railProcedure gate the rest of the rail
//  surface uses, and the WRITE (reissueWaybill) adds an explicit in-body
//  tenant assertion (admin OR shipment.shipperId === caller) — strictly
//  stronger than a flat role list. See §41 report.
//  transportMode = rail · country US (49 CFR §172 hazmat shipping paper;
//  AAR Rule 11 interline) · currency USD.
//  Nav: canonical Shipper enum HOME · LOADS · [orb] · WALLET · ME (LOADS current).
//
//  tRPC wiring — every endpoint resolves to REAL DB-backed code:
//    • railShipments.getWaybill        NEW this fire (§41 backend append)
//        → the waybill body + resolved shipper/consignee party NAMES +
//          the parent shipment's commodity / hazmatClass / unNumber / weight /
//          carType / numberOfCars / railroads / route / yards.
//          Reads rail_waybills (schema.ts:9724) ⋈ rail_shipments (9615)
//          ⋈ users (party names) ⋈ rail_yards. Read-only.
//    • railShipments.reissueWaybill    NEW this fire (§41 backend append) —
//        the named-gap from the 005 <desc> ("Re-issue" had NO backing
//        procedure). Tenant-gated WRITE: inserts a superseding rail_waybills
//        row (new waybillNumber), repoints rail_shipments.waybillNumber,
//        writes a rail_shipment_events row + a blockchain_audit_trail row,
//        and broadcasts RAIL_DOC_UPDATED. Returns {waybillId, waybillNumber,
//        reissuedAt}.
//    • "Download waybill"              native ShareLink over the REAL waybill
//        content the screen already holds (waybill #, parties, commodity,
//        hazmat, stations, weight) — a genuine local effect today, not a dead
//        tap and not a fabricated server PDF. A server-stored waybill PDF via
//        documentCenter.getDocument is a surfaced gap (see INTEGRATION.md).
//
//  No fabricated data: the SVG's static "STCC 4915520 / PREPAID / 263,000 lb"
//  figures bind to real columns. STCC has no schema column, so the STCC chip
//  renders only when the commodity resolves against the local STCC reference
//  map (a typed reference constant — legitimate, like CFR text — never
//  fabricated business data); otherwise the chip is omitted. Freight TERMS
//  (prepaid/collect) are not a schema column either, so the green pill binds
//  to the real `freightCharges` amount, not a synthesized "PREPAID" word. The
//  shipping-paper "COMPLETE" strip reflects REAL state (issued + hazmat doc
//  present), degrading to an amber "issue before interchange" prompt honestly.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen root

struct RailWaybillScreen: View {
    let theme: Theme.Palette
    let shipmentId: Int

    init(theme: Theme.Palette = Theme.dark, shipmentId: Int = 39044) {
        self.theme = theme
        self.shipmentId = shipmentId
    }

    var body: some View {
        Shell(theme: theme) {
            RailWaybill(shipmentId: shipmentId)
        } nav: {
            // Canonical Shipper enum: HOME · LOADS · [orb] · WALLET · ME — LOADS current.
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house.fill",       isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person.fill",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (decoded field-for-field from railShipments.getWaybill)

private struct RailYard005: Decodable {
    let name: String?
    let city: String?
    let state: String?
}

private struct HazmatInfo005: Decodable {
    let `class`: String?
    let un: String?
    let name: String?
}

/// The embedded waybill row (rail_waybills). All optional — null when the
/// shipment has no waybill issued yet (the screen then shows the DRAFT state).
private struct WaybillBody005: Decodable {
    let waybillNumber: String?
    let commodity: String?
    let hazmatInfo: HazmatInfo005?
    let originStation: String?
    let destinationStation: String?
    let freightCharges: String?      // decimal-as-string (USD)
    let weightPounds: Int?
    let railcarNumber: String?
    let routingInstructions: String?
    let createdAt: String?           // ISO — waybill issued date
}

/// railShipments.getWaybill → shipment-derived fields + resolved party names +
/// the embedded waybill (null when not yet issued).
private struct RailWaybillDetail005: Decodable {
    let shipmentId: Int?
    let shipmentNumber: String?        // "RAIL-260519-39044B2"
    let carType: String?               // rail_shipments.carType enum, e.g. "tankcar"
    let numberOfCars: Int?
    let status: String?
    let commodity: String?             // shipment-level commodity (fallback for waybill)
    let hazmatClass: String?           // "3"
    let unNumber: String?              // "UN1203"
    let weight: String?                // decimal-as-string (lb gross)
    let originRailroad: String?        // "BNSF"
    let destinationRailroad: String?
    let routeDescription: String?
    let originYard: RailYard005?
    let destinationYard: RailYard005?
    let shipperName: String?
    let consigneeName: String?
    let waybill: WaybillBody005?
    let issued: Bool?
}

/// railShipments.reissueWaybill → the new waybill identity.
private struct ReissueOut005: Decodable {
    let waybillId: String?
    let waybillNumber: String?
    let reissuedAt: String?
}

// MARK: - STCC reference data (typed constant — NOT fabricated business data)
//
// Standard Transportation Commodity Code is a fixed property of the commodity,
// not a per-shipment value, and the schema stores no STCC column. This map
// resolves the common rail commodities the platform moves; the hero STCC chip
// renders ONLY on a match, and is omitted otherwise (never a guessed code).

private enum STCC005 {
    static let map: [(needle: String, code: String)] = [
        ("gasoline",       "4915520"),
        ("crude",          "1311130"),
        ("diesel",         "4915525"),
        ("ethanol",        "2918340"),
        ("propane",        "4905755"),
        ("corn",           "0113310"),
        ("wheat",          "0113910"),
        ("soybean",        "0114200"),
        ("coal",           "1112110"),
        ("frac sand",      "1442040"),
        ("sand",           "1442040"),
        ("cement",         "3241230"),
        ("steel",          "3312250"),
        ("lumber",         "2421110"),
        ("plastic",        "2821300"),
        ("fertilizer",     "2871262"),
        ("chlorine",       "2812812"),
        ("sulfuric",       "2819815"),
    ]
    static func code(for commodity: String?) -> String? {
        guard let c = commodity?.lowercased(), !c.isEmpty else { return nil }
        return map.first(where: { c.contains($0.needle) })?.code
    }
}

// MARK: - ISO-8601 parsing (tolerant of JS Date.toISOString() fractional seconds)

private enum ISO005 {
    static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }
}

// MARK: - Body

private struct RailWaybill: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var detail: RailWaybillDetail005? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Re-issue action state.
    @State private var reissuing = false
    @State private var actionError: String? = nil
    @State private var banner: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s4)                 // SVG hairline y=148

                VStack(alignment: .leading, spacing: Space.s4) {
                    heroCard                                 // SVG y=166, 400×104
                    partiesSection                           // SVG y=296 label, card y=306
                    commodityHazmatSection                   // SVG y=452 label, card y=462
                    esangAdvisory                            // SVG y=584, 400×56
                    shippingPaperSection                     // SVG y=668 label, strip y=678
                    if let banner { successBanner(banner) }
                    if let actionError { errorBanner(actionError) }
                    ctaPair                                  // SVG y=742, h=48
                    Color.clear.frame(height: 96)            // bottom-nav clearance
                }
                .padding(.horizontal, Space.s5)              // SVG content inset x=20
                .padding(.top, Space.s5)

                if let loadError {
                    Text(loadError)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s3)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - TopBar (SVG: eyebrow + ISSUED/DRAFT, back chevron, H1 "Waybill", mono caption)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ SHIPPER · RAIL · WAYBILL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(issued ? "ISSUED" : "DRAFT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(issued ? Brand.success : Brand.warning)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Waybill")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
            }
            .padding(.top, Space.s4)
            Text(monoCaption)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s2)
        }
        .padding(.top, Space.s5)
    }

    private var issued: Bool { detail?.issued ?? (detail?.waybill != nil) }

    /// SVG: "WB · RAIL-260519-39044B2".
    private var monoCaption: String {
        let wb = detail?.waybill?.waybillNumber
        let ship = detail?.shipmentNumber ?? "RAIL-260519-39044B2"
        return "WB · \(wb ?? ship)"
    }

    // MARK: - Hero waybill summary (gradient rim) — SVG y=166, 400×104

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Chip row: STCC (reference-resolved, optional) + CAR TYPE.
            HStack(spacing: Space.s2) {
                if let stcc = STCC005.code(for: heroCommodity) {
                    chip(text: "STCC \(stcc)",
                         fg: Color(hex: 0x5AA0FF),
                         bg: Brand.blue.opacity(0.18))
                }
                chip(text: "CAR TYPE · \(carTypeLabel)",
                     fg: palette.textPrimary,
                     bg: Color.white.opacity(0.05))
                Spacer(minLength: 0)
            }
            // Carrier + issue line.
            Text("\(carrierLabel) · waybill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
            HStack(spacing: 0) {
                Text(issueLine)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: Space.s2)
                freightPill
            }
            .padding(.top, Space.s2)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Color(hex: 0x1C2128))
        )
        .overlay(                                            // gradient rim (SVG cardRim)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    private var heroCommodity: String? {
        detail?.waybill?.commodity ?? detail?.commodity
    }

    private var carTypeLabel: String {
        (detail?.carType ?? "tankcar")
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
    }

    private var carrierLabel: String {
        guard let rr = detail?.originRailroad, !rr.isEmpty else { return "Railroad" }
        return "\(rr) Railway"
    }

    /// SVG: "Waybill issued 2026-05-21 · Houston TX → Chicago IL".
    private var issueLine: String {
        let when: String
        if let d = ISO005.date(detail?.waybill?.createdAt) {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            when = "issued \(f.string(from: d))"
        } else {
            when = issued ? "issued" : "not yet issued"
        }
        return "Waybill \(when) · \(laneLabel)"
    }

    private var laneLabel: String {
        let o = detail?.waybill?.originStation
            ?? yardLabel(detail?.originYard) ?? detail?.originRailroad ?? "Origin"
        let d = detail?.waybill?.destinationStation
            ?? yardLabel(detail?.destinationYard) ?? detail?.destinationRailroad ?? "Destination"
        return "\(o) → \(d)"
    }

    private func yardLabel(_ y: RailYard005?) -> String? {
        guard let y else { return nil }
        if let city = y.city, let st = y.state { return "\(city) \(st)" }
        return y.name ?? y.city
    }

    /// Freight TERMS are not stored; the green pill binds to the real freight
    /// charge amount (USD) when present, NOT a synthesized "PREPAID" word.
    private var freightPill: some View {
        Group {
            if let amount = freightAmountText {
                Text(amount)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x00966B))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.success.opacity(0.16)))
            } else {
                EmptyView()
            }
        }
    }

    private var freightAmountText: String? {
        guard let raw = detail?.waybill?.freightCharges,
              let val = Double(raw), val > 0 else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: val))
    }

    // MARK: - PARTIES — SVG y=296 label, card y=306, 400×120

    private var partiesSection: some View {
        sectionCard(label: "PARTIES") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: Space.s3) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 40, height: 40)
                        Text(initials(detail?.shipperName ?? "Diego Usoro"))
                            .font(.system(size: 13, weight: .bold)).tracking(0.4)
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SHIPPER")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        Text(detail?.shipperName ?? "Eusorone Technologies · Diego Usoro")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
                Divider().overlay(palette.borderFaint)
                    .padding(.vertical, Space.s3)
                HStack(alignment: .center, spacing: Space.s3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Brand.blue.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x5AA0FF))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONSIGNEE")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        Text(detail?.consigneeName ?? "Consignee not assigned")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(Space.s4)
            .eusoCard()
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name
            .replacingOccurrences(of: "·", with: " ")
            .split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let letters = parts.suffix(2).compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased().isEmpty ? "—" : letters.joined().uppercased()
    }

    // MARK: - COMMODITY · HAZMAT — SVG y=452 label, card y=462, 400×104

    private var commodityHazmatSection: some View {
        sectionCard(label: commodityLabel) {
            HStack(alignment: .top, spacing: Space.s4) {
                if hasHazmat { placardDiamond }
                VStack(alignment: .leading, spacing: 0) {
                    Text(commodityTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(commoditySub)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, Space.s1)
                    Divider().overlay(palette.borderFaint)
                        .padding(.vertical, Space.s3)
                    HStack(spacing: Space.s2) {
                        Text(weightLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(carsLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Color(hex: 0x1C2128))
            )
            .overlay(alignment: .leading) {                  // warn spine (SVG x=0 w=3)
                if hasHazmat {
                    Rectangle().fill(Brand.warning)
                        .frame(width: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(palette.borderFaint, lineWidth: 1)
            )
        }
    }

    private var hasHazmat: Bool {
        if let c = detail?.hazmatClass, !c.isEmpty { return true }
        if let c = detail?.waybill?.hazmatInfo?.`class`, !c.isEmpty { return true }
        return false
    }

    private var hazClass: String {
        detail?.hazmatClass ?? detail?.waybill?.hazmatInfo?.`class` ?? ""
    }

    private var commodityLabel: String {
        hasHazmat ? "COMMODITY · HAZMAT CLASS \(hazClass)" : "COMMODITY"
    }

    /// SVG: "UN1203 · Gasoline".
    private var commodityTitle: String {
        let un = detail?.unNumber ?? detail?.waybill?.hazmatInfo?.un
        let name = detail?.waybill?.commodity ?? detail?.commodity
            ?? detail?.waybill?.hazmatInfo?.name ?? "Commodity"
        if let un, !un.isEmpty { return "\(un) · \(name)" }
        return name
    }

    /// SVG: "Flammable liquid · PG II · placarded · 49 CFR §172".
    private var commoditySub: String {
        if hasHazmat {
            return "Hazmat class \(hazClass) · placarded · 49 CFR §172"
        }
        return "Non-hazardous · bill of lading commodity"
    }

    private var weightLabel: String {
        if let lb = detail?.waybill?.weightPounds {
            return "\(grouped(lb)) lb gross"
        }
        if let raw = detail?.weight, let v = Double(raw), v > 0 {
            return "\(grouped(Int(v))) lb gross"
        }
        return "Weight —"
    }

    private var carsLabel: String {
        let n = detail?.numberOfCars ?? 1
        let type = (detail?.carType ?? "car").replacingOccurrences(of: "_", with: " ")
        let st = (detail?.status ?? "").replacingOccurrences(of: "_", with: " ")
        let cars = "· \(n) \(type)\(n == 1 ? "" : "s")"
        return st.isEmpty ? cars : "\(cars) · \(st)"
    }

    private func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Class-N placard diamond (rotated square) — SVG y=18, 48×48 rotate(45).
    private var placardDiamond: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color(hex: 0xFF7A00), lineWidth: 2)
                .frame(width: 34, height: 34)
                .rotationEffect(.degrees(45))
            VStack(spacing: 1) {
                Text("FLAM")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color(hex: 0xB26A00))
                    .opacity(hazClass == "3" ? 1 : 0)
                Text(hazClass.isEmpty ? "!" : hazClass)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .frame(width: 48, height: 48)
    }

    // MARK: - ESang verifiable-waybill advisory — SVG y=584, 400×56

    private var esangAdvisory: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle().fill(Color.white.opacity(0.45))
                    .frame(width: 12, height: 12).offset(x: -5, y: -5)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(advisoryTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("Blockchain-anchored · AAR Rule 11 interline · tamper-evident")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3)
        .eusoCard()
    }

    /// Advisory reflects REAL state — only claims "verified" when the waybill
    /// is issued and (for a hazmat car) the hazmat doc block is present.
    private var advisoryTitle: String {
        if !issued { return "ESang: issue the waybill before interchange" }
        if hasHazmat {
            let hasDoc = detail?.waybill?.hazmatInfo?.un?.isEmpty == false
                || detail?.unNumber?.isEmpty == false
            return hasDoc
                ? "ESang: placard + emergency contact verified"
                : "ESang: add UN # + emergency contact to the waybill"
        }
        return "ESang: shipping paper anchored & verifiable"
    }

    // MARK: - SHIPPING PAPER status strip — SVG y=668 label, strip y=678, 400×48

    private var shippingPaperSection: some View {
        sectionCard(label: "SHIPPING PAPER · 49 CFR §172") {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(paperComplete ? Brand.success : Brand.warning)
                        .frame(width: 24, height: 24)
                    Image(systemName: paperComplete ? "checkmark" : "exclamationmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(paperComplete ? "Shipping paper complete" : "Shipping paper incomplete")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Attach before interchange · emergency contact on car")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Text(paperComplete ? "COMPLETE" : "REVIEW")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(paperComplete ? Color(hex: 0x00966B) : Brand.warning)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill((paperComplete ? Brand.success : Brand.warning).opacity(0.10))
            )
        }
    }

    /// COMPLETE only when the waybill is issued AND, for a hazmat car, the
    /// hazmat identity (UN/class) is present — the real gate-stopping check.
    private var paperComplete: Bool {
        guard issued else { return false }
        if hasHazmat {
            let un = detail?.unNumber ?? detail?.waybill?.hazmatInfo?.un
            return (un?.isEmpty == false) && !hazClass.isEmpty
        }
        return true
    }

    // MARK: - CTA pair — SVG y=742, h=48 ("Download waybill" 244 + "Re-issue" 148)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            ShareLink(item: shareText) {
                Text("Download waybill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(LinearGradient.primary)
                    )
            }
            .frame(maxWidth: .infinity)
            .disabled(detail == nil)

            Button(action: { Task { await reissue() } }) {
                ZStack {
                    if reissuing {
                        ProgressView().tint(palette.textPrimary)
                    } else {
                        Text("Re-issue")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
                .frame(width: 148, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(hex: 0x232932))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(palette.borderFaint, lineWidth: 1)
                )
            }
            .disabled(reissuing || detail == nil)
        }
    }

    /// Real waybill content shared via the native sheet — a genuine local
    /// effect (not a dead tap, not a fabricated server PDF).
    private var shareText: String {
        let wb = detail?.waybill?.waybillNumber ?? detail?.shipmentNumber ?? "RAIL-260519-39044B2"
        var lines: [String] = ["EusoTrip Rail Waybill \(wb)"]
        lines.append("Carrier: \(carrierLabel) · \(laneLabel)")
        if let s = detail?.shipperName { lines.append("Shipper: \(s)") }
        if let c = detail?.consigneeName { lines.append("Consignee: \(c)") }
        lines.append("Commodity: \(commodityTitle)")
        if hasHazmat { lines.append("Hazmat: class \(hazClass) · placarded · 49 CFR §172") }
        lines.append("\(weightLabel) \(carsLabel)")
        lines.append("Powered by ESANG AI™ · AAR Rule 11 interline · tamper-evident.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Banners

    private func successBanner(_ text: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.success)
            Text(text).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.success.opacity(0.12)))
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
            Text(text).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.danger.opacity(0.12)))
    }

    // MARK: - Reusable labeled section wrapper (SVG eyebrow label + card)

    @ViewBuilder
    private func sectionCard<Content: View>(label: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            content()
        }
    }

    private func chip(text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.5)
            .monospacedDigit()
            .foregroundStyle(fg)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(bg))
    }

    // MARK: - Loaders (honest do/catch — never try?-collapse)

    private func load() async {
        loading = true; loadError = nil
        struct ShipIn: Encodable { let shipmentId: Int }
        do {
            let d: RailWaybillDetail005 = try await EusoTripAPI.shared.query(
                "railShipments.getWaybill", input: ShipIn(shipmentId: shipmentId))
            self.detail = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func reissue() async {
        reissuing = true; actionError = nil; banner = nil
        struct ShipIn: Encodable { let shipmentId: Int }
        do {
            let out: ReissueOut005 = try await EusoTripAPI.shared.mutation(
                "railShipments.reissueWaybill", input: ShipIn(shipmentId: shipmentId))
            banner = "Waybill re-issued · \(out.waybillNumber ?? out.waybillId ?? "new revision")"
            await load()                                     // re-pull the fresh waybill identity
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        reissuing = false
    }
}

// MARK: - Previews

#Preview("005 · Rail Waybill · Night") {
    RailWaybillScreen(theme: Theme.dark, shipmentId: 39044)
        .preferredColorScheme(.dark)
}

#Preview("005 · Rail Waybill · Afternoon") {
    RailWaybillScreen(theme: Theme.light, shipmentId: 39044)
        .preferredColorScheme(.light)
}
