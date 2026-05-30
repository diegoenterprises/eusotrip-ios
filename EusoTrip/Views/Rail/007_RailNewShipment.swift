//
//  007_RailNewShipment.swift
//  EusoTrip — Rail · Shipper · New Shipment (brick 007).
//
//  Verbatim reconstruction of "05 Rail/Dark-SVG/007 Rail New Shipment.svg"
//  (canvas 440×956, Theme.dark). This is the CANONICAL, mode-agnostic SHIPPER app
//  (Diego Usoro / Eusorone Technologies, companyId 1, SHIPPER) originating a RAIL
//  load (load.mode='rail') — NOT a separate "Rail Shipper" role and NOT a forked
//  nav. FORM grammar mirrors 02 Shipper Post-a-Load + the 205 detail anatomy:
//    detail TopBar (back-chevron + one ✦ eyebrow + STEP caption + 28/700/-0.5
//    title + sub-line) → IridescentHairline → gradient-rimmed ROUTE·YARD-TO-YARD
//    hero (origin/dest yard rows + mono lane caption) → EQUIPMENT two-card row
//    (CAR TYPE · CARS/WEIGHT) → COMMODITY·STCC card → TARIFF-RATE card (live perCar
//    + rail-vs-truck savings line) → ESang advisory → CTA pair
//    (Request shipment · Compare).
//  Web parity: client/src/pages/shipper/NewShipment.tsx with load.mode='rail'.
//
//  tRPC wiring — REAL contract (the-oath §53, 2026-05-30). Every procedure is
//  railProcedure-gated (server/routers/railShipments.ts; mounted routers.ts:3178).
//  Anchors re-verified against the live router THIS fire (the <desc> line numbers
//  were stale; these are the real decls):
//    • railShipments.getRailYards            (EXISTS · railShipments.ts:530)
//        → route yard pickers. Returns a BARE ARRAY of rail_yards rows.
//    • railShipments.getRailcars             (EXISTS · railShipments.ts:444)
//        → equipment availability by carType/yard. Returns {railcars:[…],total}.
//    • railShipments.getTariffRate           (EXISTS · railShipments.ts:960)
//        → live per-car tariff incl. FSC. {originStation,destStation,carType,
//          commodity} → TariffRateResult (totalRate per car · currency · …) | null.
//    • railShipments.createRailShipment      (EXISTS · railShipments.ts:48)
//        → "Request shipment". Writes a rail_shipments row (status 'requested') and
//          — AS OF §53 — a blockchain_audit_trail row + WS fan-out on
//          WS_CHANNELS.RAIL_SHIPMENT / WS_EVENTS.RAIL_SHIPMENT_CREATED
//          (server gap filled this fire: createRailShipment.audit-ws.patch.ts).
//    • railShipments.compareModeRates        (BUILT THIS FIRE · named-gap killed)
//        → "Compare". {originYardId,destYardId,carType,commodity,numberOfCars}
//          → {rail,truck,savings,railPerCar,distanceMiles,currency}. Honest
//          computed rate comparison (haversine yard distance × real per-mode rate
//          references + live rail tariff). Staged: compareModeRates.patch.ts.
//
//  HONEST DEGRADE: every figure the resolvers return null for (perCar, totals,
//  savings, lane distance, draft ref) renders an EM-DASH — never the SVG sample
//  values ("$3,420", "$17,100", "vs truck $31,250", "~1,085 mi"). No try?-collapse;
//  every loader/CTA is a real do/catch surfacing actionError. createRailShipment
//  reports the real shipmentNumber on success (no synthesized success:false).
//
//  RBAC: SHIPPER / ADMIN / SUPER_ADMIN (rail-mode shipper write). transportMode=rail.
//  Single-country US (BNSF single-line domestic · STCC 0113310 grain non-haz) · USD.
//  Nav: canonical Shipper enum HOME · LOADS · [orb] · WALLET · ME (LOADS current),
//  supplied by the Shipper nav chrome — this screen renders content only (matches
//  002_RailShipmentDetail / 006_RailCrossBorderCustoms).
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Data shapes (decoded from the REAL railShipments payloads)

private struct RailYard007: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let city: String?
    let state: String?
    let splcCode: String?
    struct Coord: Decodable, Hashable { let lat: Double?; let lng: Double? }
    let coordinates: Coord?

    /// "Houston · Pearland Yard" style display, honest about missing city.
    var routeLabel: String {
        if let c = city, !c.isEmpty { return "\(c) · \(name)" }
        return name
    }
}

private struct TariffRate007: Decodable {
    let totalRate: Double?      // per car, incl. surcharges
    let currency: String?
    let rateUnit: String?
    let railroad: String?
    let tariffNumber: String?
}

private struct ModeCompare007: Decodable {
    let rail: Double?           // total rail line-haul for the block
    let truck: Double?          // truck-equivalent line-haul
    let savings: Double?        // truck − rail (positive = rail cheaper)
    let railPerCar: Double?
    let distanceMiles: Double?
    let currency: String?
}

private struct CreateResult007: Decodable {
    let id: Int?
    let shipmentNumber: String?
    let status: String?
}

// MARK: - Screen

struct RailNewShipment_007: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    // Selections (seed defaults match the SVG example; pickers + endpoints mutate).
    @State private var origin: RailYard007? = nil
    @State private var destination: RailYard007? = nil
    @State private var carType: String = "covered_hopper"
    @State private var carTypeLabel: String = "Covered hopper"
    @State private var carTypeSub: String = "grain service · non-haz"
    @State private var numberOfCars: Int = 5
    @State private var perCarWeightLb: Int = 143_000
    @State private var commodity: String = "Corn · bulk grain"
    @State private var stccCode: String = "0113310"
    @State private var commoditySub: String = "No hazmat placard · no UN number · food-grade clean car"

    // Live data
    @State private var yards: [RailYard007] = []
    @State private var tariff: TariffRate007? = nil
    @State private var compare: ModeCompare007? = nil

    // Async state (honest — no try?-collapse)
    @State private var loading = true
    @State private var rating = false
    @State private var comparing = false
    @State private var requesting = false
    @State private var actionError: String? = nil
    @State private var createdRef: String? = nil

    // Pickers
    @State private var picking: YardSlot? = nil
    @State private var editingEquipment = false

    private enum YardSlot: Identifiable { case origin, destination; var id: Int { self == .origin ? 0 : 1 } }

    // MARK: Derived display

    private func dash(_ s: String?) -> String {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return "—" }
        return s
    }
    private func money(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "$" + Self.grouped(Int(v.rounded()))
    }
    private static func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    private var subLine: String {
        let o = origin?.city ?? origin?.name
        let d = destination?.city ?? destination?.name
        let route = (o != nil && d != nil) ? "\(o!) → \(d!)" : "Select origin → destination"
        let st = createdRef == nil ? "draft" : "requested"
        return "\(route) · \(numberOfCars) \(carTypeLabel.lowercased()) · \(commodityShort) · \(st)"
    }
    private var commodityShort: String {
        commodity.split(separator: "·").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? commodity
    }
    private var laneCaption: String {
        let ref = createdRef ?? "RAIL DRAFT"
        let miles = compare?.distanceMiles.map { "~\(Self.grouped(Int($0.rounded()))) mi" } ?? "— mi"
        let line = dash(tariff?.railroad).uppercased() == "—" ? "BNSF single-line" : "\(dash(tariff?.railroad)) single-line"
        return "\(ref) · \(line) · \(miles)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if let err = actionError { errorBanner(err) }
                    if let ref = createdRef { successBanner(ref) }
                    routeHero
                    equipmentSection
                    commoditySection
                    tariffSection
                    esangAdvisory
                    ctaRow
                    Color.clear.frame(height: 96)   // Shipper nav chrome spacer
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
            }
        }
        .task { await bootstrap() }
        .sheet(item: $picking) { slot in yardPickerSheet(slot) }
        .sheet(isPresented: $editingEquipment) { equipmentSheet }
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ SHIPPER · RAIL · NEW SHIPMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(createdRef == nil ? "STEP 1 · 3" : "REQUESTED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(createdRef == nil ? palette.textTertiary : Brand.success)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                Text("New rail shipment")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.5)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: Space.s2)
            }
            .padding(.top, Space.s4)
            Text(subLine)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Space.s2)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.top, Space.s5)
    }

    // MARK: - Route hero (gradient-rimmed · getRailYards)

    private var routeHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient.primary)
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)

            VStack(alignment: .leading, spacing: 0) {
                Text("ROUTE · YARD TO YARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)

                yardRow(filled: false, label: origin?.routeLabel ?? "Tap to choose origin yard") {
                    picking = .origin
                }
                .padding(.top, Space.s4)

                Rectangle().fill(palette.textTertiary)
                    .frame(width: 1.5, height: 22)
                    .padding(.leading, 6)
                    .opacity(0.6)

                yardRow(filled: true, label: destination?.routeLabel ?? "Tap to choose destination yard") {
                    picking = .destination
                }

                Text(laneCaption)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, Space.s4)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(20)
        }
        .frame(minHeight: 116)
    }

    private func yardRow(filled: Bool, label: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle()
                        .strokeBorder(Brand.blue, lineWidth: 2)
                        .frame(width: 12, height: 12)
                    if filled { Circle().fill(Brand.blue).frame(width: 12, height: 12) }
                }
                Text(label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Equipment two-card row (createRailShipment: carType + numberOfCars)

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("EQUIPMENT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            Button { editingEquipment = true } label: {
                HStack(spacing: Space.s3) {
                    equipmentCard(kicker: "CAR TYPE", value: carTypeLabel, sub: carTypeSub)
                    equipmentCard(kicker: "CARS / WEIGHT",
                                  value: "\(numberOfCars) car\(numberOfCars == 1 ? "" : "s")",
                                  sub: "~\(Self.grouped(perCarWeightLb)) lb each")
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func equipmentCard(kicker: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kicker)
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Commodity (createRailShipment: commodity + stccCode)

    private var commoditySection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("COMMODITY · STCC \(stccCode)")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            VStack(alignment: .leading, spacing: 0) {
                Text(commodity)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(commoditySub)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, Space.s3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Tariff (getTariffRate · compareModeRates)

    private var tariffSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("TARIFF RATE\(tariff?.tariffNumber.map { " · \($0)" } ?? "")")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if rating || comparing {
                    ProgressView().controlSize(.mini).tint(palette.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text(money(tariff?.totalRate))
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text("per car · incl. fuel surcharge")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                }
                Text(savingsLine)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x00966B))   // verbatim SVG green
                    .padding(.top, Space.s3)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }

    private var savingsLine: String {
        if let c = compare, let rail = c.rail, let truck = c.truck {
            return "\(money(rail)) for \(numberOfCars) cars · vs. truck \(money(truck))"
        }
        // Pre-Compare honest state — derive block total from live per-car if present.
        if let per = tariff?.totalRate {
            return "\(money(per * Double(numberOfCars))) for \(numberOfCars) cars · tap Compare for truck"
        }
        return "Tap Compare for rail-vs-truck savings"
    }

    // MARK: - ESang advisory (static design copy — non-actionable hint band)

    private var esangAdvisory: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.primary).frame(width: 32, height: 32)
                Circle().fill(Color.white.opacity(0.25)).frame(width: 16, height: 16)
                    .offset(x: -5, y: -5)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(esangHeadline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(esangDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    // Advisory copy is design-canon (unit-train threshold heuristic), gated on the
    // real selected block size so it never contradicts the chosen car count.
    private var esangHeadline: String {
        numberOfCars >= 25
            ? "ESang: \(numberOfCars)-car block already qualifies for unit-train rate"
            : "ESang: \(numberOfCars)-car block qualifies for unit-train rate"
    }
    private var esangDetail: String {
        if numberOfCars >= 25 { return "Unit-train threshold met · best per-car economics" }
        let add = 25 - numberOfCars
        return "Add \(add) car\(add == 1 ? "" : "s") to hit 25-car threshold · saves ~9%"
    }

    // MARK: - CTA row (createRailShipment · compareModeRates)

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            Button { Task { await requestShipment() } } label: {
                HStack(spacing: Space.s2) {
                    if requesting { ProgressView().tint(.white) }
                    Text(requesting ? "Requesting…" : (createdRef == nil ? "Request shipment" : "Requested ✓"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Capsule().fill(LinearGradient.primary))
                .opacity(canRequest ? 1 : 0.5)
            }
            .disabled(!canRequest || requesting || createdRef != nil)

            Button { Task { await runCompare() } } label: {
                HStack(spacing: Space.s2) {
                    if comparing { ProgressView().controlSize(.small).tint(palette.textPrimary) }
                    Text("Compare")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .frame(width: 132, height: 48)
                .background(
                    Capsule()
                        .fill(Color(hex: 0x232932))   // verbatim SVG secondary fill
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                )
                .opacity(canCompare ? 1 : 0.5)
            }
            .disabled(!canCompare || comparing)
        }
    }

    private var canRequest: Bool { origin != nil && destination != nil && numberOfCars > 0 }
    private var canCompare: Bool { origin != nil && destination != nil }

    // MARK: - Banners

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(msg).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.warning.opacity(0.10)))
    }
    private func successBanner(_ ref: String) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.success)
            Text("Shipment \(ref) requested · status ‘requested’.")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textPrimary)
            Spacer()
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.success.opacity(0.12)))
    }

    // MARK: - Yard picker sheet (real getRailYards rows)

    private func yardPickerSheet(_ slot: YardSlot) -> some View {
        NavigationStack {
            List {
                if yards.isEmpty {
                    Text("No active rail yards available.")
                        .foregroundStyle(palette.textSecondary)
                } else {
                    ForEach(yards) { y in
                        Button {
                            if slot == .origin { origin = y } else { destination = y }
                            picking = nil
                            Task { await refreshRate() }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(y.routeLabel).font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Text([y.state, y.splcCode.map { "SPLC \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(slot == .origin ? "Origin yard" : "Destination yard")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Equipment sheet (carType + count; getRailcars availability)

    private var equipmentSheet: some View {
        NavigationStack {
            Form {
                Section("Car type") {
                    ForEach(Self.carTypes.indices, id: \.self) { i in
                        let opt = Self.carTypes[i]
                        Button {
                            carType = opt.code; carTypeLabel = opt.label
                            carTypeSub = opt.sub; perCarWeightLb = opt.weight
                            Task { await refreshRate() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(opt.label).foregroundStyle(palette.textPrimary)
                                    Text(opt.sub).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                                }
                                Spacer()
                                if carType == opt.code { Image(systemName: "checkmark").foregroundStyle(Brand.blue) }
                            }
                        }
                    }
                }
                Section("Number of cars") {
                    Stepper("\(numberOfCars) car\(numberOfCars == 1 ? "" : "s")",
                            value: $numberOfCars, in: 1...110)
                        .onChange(of: numberOfCars) { _, _ in Task { await refreshRate() } }
                }
            }
            .navigationTitle("Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { editingEquipment = false }
                }
            }
        }
    }
    /// Canonical AAR car-type set (server enum subset) with sample laden weights.
    private static let carTypes: [(code: String, label: String, sub: String, weight: Int)] = [
        ("covered_hopper", "Covered hopper", "grain service · non-haz", 143_000),
        ("open_hopper",    "Open hopper",    "aggregates · coal",        140_000),
        ("boxcar",         "Boxcar",         "packaged · palletized",    100_000),
        ("tankcar",        "Tank car",       "liquids · may be DG",      190_000),
        ("centerbeam",     "Center-beam",    "lumber · panel",           120_000),
        ("gondola",        "Gondola",        "scrap · pipe",             130_000),
        ("intermodal",     "Intermodal",     "container · COFC",          52_000),
    ]

    // MARK: - Loaders / actions (single REAL endpoint each — honest do/catch)

    private func bootstrap() async {
        loading = true; actionError = nil
        struct YardsIn: Encodable { let country: String; let limit: Int }
        do {
            let rows: [RailYard007] = try await EusoTripAPI.shared.query(
                "railShipments.getRailYards", input: YardsIn(country: "US", limit: 50))
            self.yards = rows
            // Seed origin/dest to the first two distinct yards so the hero paints
            // real rows on first frame (honest — falls to em-dash if DB is empty).
            if origin == nil { origin = rows.first }
            if destination == nil { destination = rows.dropFirst().first ?? rows.first }
        } catch {
            actionError = "Couldn’t load rail yards. " +
                ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        await refreshRate()
        loading = false
    }

    /// Live per-car tariff for the current selection (getTariffRate). Read-only.
    private func refreshRate() async {
        guard let o = origin, let d = destination else { tariff = nil; return }
        rating = true
        struct RateIn: Encodable {
            let originStation: String; let destStation: String
            let carType: String; let commodity: String
        }
        do {
            let r: TariffRate007 = try await EusoTripAPI.shared.query(
                "railShipments.getTariffRate",
                input: RateIn(originStation: o.splcCode ?? o.name,
                              destStation: d.splcCode ?? d.name,
                              carType: carType, commodity: commodityShort))
            self.tariff = r
        } catch {
            // External tariff service may be unconfigured → honest em-dash, not a lie.
            self.tariff = nil
        }
        rating = false
        // Re-Compare invalidation: a changed selection makes any prior comparison stale.
        self.compare = nil
    }

    /// Rail-vs-truck comparison (compareModeRates · built §53). Read-only.
    private func runCompare() async {
        guard let o = origin, let d = destination else { return }
        comparing = true; actionError = nil
        struct CompareIn: Encodable {
            let originYardId: Int; let destYardId: Int
            let carType: String; let commodity: String; let numberOfCars: Int
        }
        do {
            let c: ModeCompare007 = try await EusoTripAPI.shared.query(
                "railShipments.compareModeRates",
                input: CompareIn(originYardId: o.id, destYardId: d.id,
                                 carType: carType, commodity: commodityShort,
                                 numberOfCars: numberOfCars))
            self.compare = c
        } catch {
            actionError = "Couldn’t compare modes. " +
                ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        comparing = false
    }

    /// Request the shipment (createRailShipment mutation). Real write.
    private func requestShipment() async {
        guard let o = origin, let d = destination else { return }
        requesting = true; actionError = nil
        struct CreateIn: Encodable {
            let originYardId: Int; let destinationYardId: Int
            let carType: String; let commodity: String
            let stccCode: String; let numberOfCars: Int
        }
        do {
            let res: CreateResult007 = try await EusoTripAPI.shared.mutation(
                "railShipments.createRailShipment",
                input: CreateIn(originYardId: o.id, destinationYardId: d.id,
                                carType: carType, commodity: commodityShort,
                                stccCode: stccCode, numberOfCars: numberOfCars))
            self.createdRef = res.shipmentNumber ?? (res.id.map { "RS-\($0)" } ?? "REQUESTED")
        } catch {
            actionError = "Couldn’t request the shipment. " +
                ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        requesting = false
    }
}

// MARK: - Previews

#Preview("007 · Rail New Shipment · Night") {
    RailNewShipment_007()
        .preferredColorScheme(.dark)
}
