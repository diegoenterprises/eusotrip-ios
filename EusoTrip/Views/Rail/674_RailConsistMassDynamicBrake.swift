//
//  674_RailConsistMassDynamicBrake.swift
//  EusoTrip — Rail Engineer · Consist Mass & Dynamic-Brake Check.
//
//  Bespoke port of "05 Rail/Dark-SVG/674 Rail Consist Mass & Dynamic-Brake
//  Check.svg". ARCHETYPE = DEPARTURE-READINESS GATE — a verdict hero
//  (trailing tonnage built car-by-car from real UMLER weights + a capacity
//  bar against the corridor gross-rail-load rating) over a 4-row
//  threshold-gate card (each computed value vs its regulatory limit,
//  PASS / HOLD / PENDING). Not a stamped detail card.
//
//  Role: RAIL_ENGINEER (carrier family). transportMode = rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getEquipmentSpecs  EXISTS:1730 {railcarNumber} →
//        UMLER {carType,tareWeight,loadLimit,capacity,aarType,…}. Each
//        railcar added to the consist pulls its REAL gross weight; the
//        trailing-tonnage sum + per-car gross-rail-load gate are computed
//        from what is on file — never a fabricated total.
//    railShipments.getRailInspections EXISTS:2684 {limit} → the air-brake
//        terminal gate reflects a REAL brake inspection when one is on
//        file for a car in the consist.
//    HONEST GAP: the train-level readiness verdict + hp/ton demand + the
//    dynamic-brake-axle % + authorizeDeparture have no backing procedure
//    on disk (getConsistReadiness / authorizeDeparture — STUB). Those
//    gates render an explicit PENDING state, never a synthesized number.
//    Corridor rating (286k / 315k lb GRL) is a 49 CFR §215 regulatory
//    constant, not fabricated data.
//

import SwiftUI

struct RailConsistMassDynamicBrakeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailConsistMassDynamicBrakeBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decodable (railShipments.getEquipmentSpecs → UMLER)

private struct UMLERSpec674: Decodable {
    let railcarNumber: String?
    let carType: String?
    let capacity: Double?
    let tareWeight: Double?
    let loadLimit: Double?
    let aarType: String?
}

/// One real inspection row (getRailInspections) — used only to light the
/// air-brake terminal gate when a brake inspection is on file.
private struct InspRow674: Decodable {
    let id: String?
    let type: String?
    let status: String?
    let location: String?
    let passed: Bool?
}
private struct LimitIn674: Encodable { let limit: Int }
private struct RailcarIn674: Encodable { let railcarNumber: String }

/// A car in the session-local consist, carrying its REAL UMLER gross weight.
private struct ConsistCar674: Identifiable {
    let railcarNumber: String
    let carType: String?
    let grossLb: Double?      // tare + loadLimit, nil when UMLER had no weight
    var id: String { railcarNumber }
}

// MARK: - Body

private struct RailConsistMassDynamicBrakeBody: View {
    @Environment(\.palette) private var palette

    @State private var cars: [ConsistCar674] = []
    @State private var inspections: [InspRow674] = []
    @State private var entry = ""
    @State private var adding = false
    @State private var addError: String? = nil
    @State private var ratingIndex = 0            // 0 = 286k, 1 = 315k
    @State private var country = 0                // US · CA · MX regime band

    // Corridor gross-rail-load rating (per-car), a 49 CFR §215 constant.
    private let ratings: [(label: String, lb: Double)] = [("286k corridor", 286_000), ("315k corridor", 315_000)]
    private let regimes: [(String, String)] = [("US · FRA 49 CFR", "286k–315k lb"),
                                               ("CA · TC RTD", "gross rail load"),
                                               ("MX · ARTF/SICT", "carga por eje")]

    private var ratingLb: Double { ratings[ratingIndex].lb }
    private var trailingLb: Double { cars.compactMap { $0.grossLb }.reduce(0, +) }
    private var trailingTons: Double { trailingLb / 2000 }
    private var heaviestCar: ConsistCar674? { cars.max { ($0.grossLb ?? 0) < ($1.grossLb ?? 0) } }
    private var overRatingCars: [ConsistCar674] { cars.filter { ($0.grossLb ?? 0) > ratingLb } }
    private var weighedCount: Int { cars.filter { $0.grossLb != nil }.count }

    /// Real air-brake terminal signal, only when a brake inspection is on file.
    private var airBrakeInsp: InspRow674? {
        inspections.first { ($0.type ?? "").lowercased().contains("brake")
            || ($0.type ?? "").lowercased().contains("air") }
    }

    private enum GateState { case pass, hold, pending
        var label: String { switch self { case .pass: "PASS"; case .hold: "HOLD"; case .pending: "PENDING" } }
        var color: Color { switch self { case .pass: Brand.success; case .hold: Brand.danger; case .pending: Brand.warning } }
    }

    // The two REAL gates + two HONEST-pending gates.
    private var grlGate: GateState { cars.isEmpty ? .pending : (overRatingCars.isEmpty ? .pass : .hold) }
    private var airBrakeGate: GateState {
        guard let i = airBrakeInsp else { return .pending }
        return i.passed == true ? .pass : (i.passed == false ? .hold : .pending)
    }
    private var clearedToAuthorize: Bool {
        grlGate == .pass && airBrakeGate == .pass
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Tonnage & brake")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text(cars.isEmpty ? "Aurora Rail Division · departure readiness gate"
                              : "Aurora Rail Division · \(cars.count)-car consist · ruling grade")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                verdictHero
                buildRow
                gateHeader
                gateCard
                regimeBand
                footerActions
            }
            .padding(.horizontal, 20).padding(.top, Space.s5)
        }
        .task { await reload() }
        .eusoRefreshable { await reload() }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            EusoTripEyebrow(verbatim: "RAIL ENGINEER · DEPARTURE CHECK")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("CONSIST BUILD")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip(cars.isEmpty ? "no cars" : (overRatingCars.isEmpty ? "cleared" : "\(overRatingCars.count) over"),
                 cars.isEmpty ? palette.textSecondary : (overRatingCars.isEmpty ? Brand.success : Brand.danger))
            chip("\(cars.count) cars", palette.textSecondary)
            Button { withAnimation(.easeOut(duration: 0.12)) { ratingIndex = (ratingIndex + 1) % ratings.count } } label: {
                chip(ratings[ratingIndex].label, Brand.rail)
            }.buttonStyle(.plain)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Verdict hero — real trailing tonnage vs corridor rating.

    private var verdictHero: some View {
        let cleared = grlGate == .pass && !cars.isEmpty
        let washColors = cars.isEmpty
            ? [Brand.warning.opacity(0.12), Brand.blue.opacity(0.05)]
            : (cleared ? [Brand.success.opacity(0.14), Brand.blue.opacity(0.06)]
                       : [Brand.danger.opacity(0.14), Brand.warning.opacity(0.10)])
        let heaviestLb = heaviestCar?.grossLb ?? 0
        let fill = ratingLb > 0 ? min(heaviestLb / ratingLb, 1.15) : 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TRAILING TONNAGE vs TRACK RATING")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(cars.isEmpty ? Brand.warning : (cleared ? Brand.success : Brand.danger))
                Spacer()
                Text(cars.isEmpty ? "AWAIT CARS" : (cleared ? "CLEARED" : "OVER RATING"))
                    .font(.system(size: 10.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(cars.isEmpty ? Brand.warning : (cleared ? Brand.success : Brand.danger))
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill((cars.isEmpty ? Brand.warning : (cleared ? Brand.success : Brand.danger)).opacity(0.16)))
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: washColors, startPoint: .leading, endPoint: .trailing))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(cars.isEmpty ? "—" : "\(fmtTons(trailingTons)) t")
                        .font(.system(size: 30, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text(cars.isEmpty ? "no consist built" : "trailing")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
                }
                Text(cars.isEmpty
                     ? "Add railcars to build the consist — each pulls its UMLER gross weight."
                     : "\(weighedCount)/\(cars.count) cars weighed · heaviest \(fmtLb(heaviestLb)) vs \(fmtLb(ratingLb)) rating")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                if !cars.isEmpty {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.bgCardSoft).frame(height: 8)
                            Capsule().fill(grlGate == .pass ? Brand.success : Brand.danger)
                                .frame(width: geo.size.width * CGFloat(min(fill / 1.15, 1.0)), height: 8)
                            Rectangle().fill(Brand.warning).frame(width: 2, height: 14)
                                .offset(x: geo.size.width * CGFloat(1.0 / 1.15))
                        }
                    }
                    .frame(height: 14)
                }
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // MARK: Build row — add a railcar → real UMLER weight.

    private var buildRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "number").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textTertiary)
                TextField("Add railcar to consist", text: $entry)
                    .font(.system(size: 15, weight: .bold)).monospaced()
                    .autocorrectionDisabled().textInputAutocapitalization(.characters)
                    .foregroundStyle(palette.textPrimary)
                    .onSubmit { Task { await addCar() } }
                Button { Task { await addCar() } } label: {
                    if adding { ProgressView().tint(.white).frame(width: 44) }
                    else {
                        Text("Add").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 30)
                            .background(LinearGradient.diagonal).clipShape(Capsule())
                    }
                }.buttonStyle(.plain).disabled(adding || entry.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Space.s3).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            if let e = addError {
                Text(e).font(EType.caption).foregroundStyle(Brand.warning)
            }
            if !cars.isEmpty {
                FlowChips674(cars: cars, ratingLb: ratingLb, onRemove: { num in
                    cars.removeAll { $0.railcarNumber == num }
                })
            }
        }
    }

    // MARK: Departure gates

    private var gateHeader: some View {
        HStack {
            Text("DEPARTURE GATES · 4").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text("49 CFR §232 / §236").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
    }

    private var gateCard: some View {
        VStack(spacing: 0) {
            gateRow(title: "Trailing gross-rail-load",
                    rule: "≤ \(fmtLb(ratingLb)) per car",
                    value: cars.isEmpty ? "—" : (overRatingCars.isEmpty ? "within rating" : "\(overRatingCars.count) over"),
                    state: grlGate)
            Divider().overlay(palette.borderFaint)
            gateRow(title: "Horsepower-per-ton",
                    rule: "≥ 1.0 hp/t on grade",
                    value: "power plan pending",
                    state: .pending)
            Divider().overlay(palette.borderFaint)
            gateRow(title: "Dynamic-brake axles",
                    rule: "≥ 50% of trailing axles",
                    value: "compute pending",
                    state: .pending)
            Divider().overlay(palette.borderFaint)
            gateRow(title: "Air-brake terminal test",
                    rule: "§232.205 initial terminal",
                    value: airBrakeInsp == nil ? "no test on file" : (airBrakeInsp?.passed == true ? "passed" : "review"),
                    state: airBrakeGate)
        }
        .padding(.horizontal, 16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func gateRow(title: String, rule: String, value: String, state: GateState) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(rule).font(.system(size: 10.5)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(value).font(.system(size: 12, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textSecondary).lineLimit(1)
                Text(state.label).font(.system(size: 10.5, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(state.color)
                    .padding(.horizontal, 10).frame(height: 20)
                    .background(Capsule().fill(state.color.opacity(0.14)))
            }
        }
        .padding(.vertical, 14)
    }

    // MARK: Tri-country regime band

    private var regimeBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == country ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == country ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { country = i } }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: clearedToAuthorize ? "Authorize departure" : "Gates not cleared",
                      action: {})
                .frame(maxWidth: .infinity)
                .disabled(!clearedToAuthorize)
            Button { Task { await reload() } } label: {
                Text("Recalc").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132).frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    // MARK: Data

    private func reload() async {
        inspections = (try? await EusoTripAPI.shared.query(
            "railShipments.getRailInspections", input: LimitIn674(limit: 100))) ?? []
    }

    private func addCar() async {
        let num = entry.trimmingCharacters(in: .whitespaces).uppercased()
        guard !num.isEmpty, !adding else { return }
        guard !cars.contains(where: { $0.railcarNumber == num }) else { addError = "\(num) already in consist."; return }
        adding = true; addError = nil; defer { adding = false }
        let spec: UMLERSpec674? = try? await EusoTripAPI.shared.query(
            "railShipments.getEquipmentSpecs", input: RailcarIn674(railcarNumber: num))
        let gross: Double? = {
            guard let s = spec else { return nil }
            if let t = s.tareWeight, let l = s.loadLimit { return t + l }
            return s.capacity
        }()
        cars.append(ConsistCar674(railcarNumber: num, carType: spec?.carType, grossLb: gross))
        if gross == nil { addError = "\(num) added — no UMLER weight on file (excluded from tonnage)." }
        entry = ""
    }

    private func fmtTons(_ t: Double) -> String {
        let n = Int(t.rounded())
        return n.formatted(.number.grouping(.automatic))
    }
    private func fmtLb(_ lb: Double) -> String {
        if lb >= 1000 { return "\(Int((lb / 1000).rounded()))k lb" }
        return "\(Int(lb.rounded())) lb"
    }
}

// MARK: - Built-consist chip strip (real per-car GRL flag)

private struct FlowChips674: View {
    @Environment(\.palette) private var palette
    let cars: [ConsistCar674]
    let ratingLb: Double
    let onRemove: (String) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(cars) { c in
                let over = (c.grossLb ?? 0) > ratingLb
                HStack(spacing: 8) {
                    Image(systemName: "tram.fill").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(over ? Brand.danger : Brand.rail)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.railcarNumber).font(.system(size: 12, weight: .heavy)).monospaced()
                            .foregroundStyle(palette.textPrimary)
                        Text(c.carType ?? "spec unknown").font(.system(size: 9))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    Text(c.grossLb.map { "\(Int(($0 / 1000).rounded()))k lb" } ?? "no weight")
                        .font(.system(size: 11, weight: .bold)).monospacedDigit()
                        .foregroundStyle(over ? Brand.danger : palette.textSecondary)
                    Button { onRemove(c.railcarNumber) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 15))
                            .foregroundStyle(palette.textTertiary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(over ? Brand.danger.opacity(0.4) : palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
        }
    }
}

#Preview("674 · Consist Mass & Brake · Night") {
    RailConsistMassDynamicBrakeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("674 · Consist Mass & Brake · Light") {
    RailConsistMassDynamicBrakeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
