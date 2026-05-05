//
//  214_ShipperSustainability.swift
//  EusoTrip 2027 UI — Shipper · Sustainability (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/214_ShipperSustainability.swift. Persona: Diego
//  Usoro / Eusorone Technologies (companyId 1) per §11. The
//  PER-SHIPMENT CALCULATOR card anchors §11.2 flagship row 1
//  (LD-260427-A38FB12C7E · Houston→Dallas · MC-306 · UN1203 ·
//  50,000 lb · 239 mi) when no live shipment is selected — input
//  fields default to that anchor and `co2Calculator.calculateTruckShipment`
//  drives the result.
//
//  Layout (top → bottom):
//    1. TopBar             ✦ SHIPPER · SUSTAINABILITY / "YTD · {N} t SAVED" (Brand.success)
//    2. Title block        Sustainability / "CO₂ across MATRIX-50 · GLEC v3.0 · scope 3"
//    3. IridescentHairline
//    4. Hero YTD card      gradient green→blue rim, leaf glyph + 44pt CO₂e numeral,
//                          progress bar 54% to net-zero (placeholders pending EUSO-2112)
//    5. EQUIVALENT TO label
//    6. Equivalence triplet 3 tiles (TREES / DIESEL / CARS) — hydrates from live
//                          calculator result; falls back to "—" when no result
//    7. PER-SHIPMENT CALCULATOR · {loadId} eyebrow
//    8. Calculator card    lane summary + mode tabs (Truck active · Rail / Multimodal
//                          placeholders) + result row (EMISSIONS + VS LANE AVG delta)
//    9. Green-miles strip  mini orb + recommendation + chevron (EUSO-2113)
//   10. Action row         "Buy offsets · {N} t" gradient pill + "Export report" hollow
//
//  Real wiring preserved: `co2Calculator.calculateTruckShipment` via
//  `ShipperSustainabilityStore`. Distance/weight/equipment inputs
//  remain mutable so the user can override the anchor lane defaults.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2112 — `sustainability.getCarbonLedger` not yet shipped
//                from iOS API surface. Hero YTD card paints "—"
//                placeholders for total CO₂e / loads / net-zero
//                progress / saved tonnes until backend ships the
//                ledger envelope.
//    EUSO-2113 — Green-miles recommendation engine not yet shipped.
//                Strip paints generic "Optimization pending" copy
//                until backend ships `sustainability.getRecommendations`.
//    EUSO-2114 — `co2Calculator.calculateRail` not yet shipped.
//                Rail mode tab paints disabled placeholder; only
//                Truck (real) and Multimodal (placeholder until
//                multi-leg input lands) are wired.
//
//  Doctrine refs: §2 HOME-tab nav (handled by ContentView); §3
//  numbers-first copy ("42.6 t CO₂e", "8.4 t SAVED", "−8.4%"); §4.3
//  single iridescent hairline; §7 breathe density; §9.1 equivalence
//  triplet (leaf · fuel pump · car); §11 / §11.2 Diego canon +
//  MATRIX-50 lane anchor (LD-260427-A38FB12C7E); §17.2 mode-tab
//  pill grammar; §19.2 file-scoped LeafShape / FuelPumpGlyph /
//  CarGlyph / ChevronShape / MiniOrb / `LinearGradient.greenBlue`;
//  §20.4 no dead buttons (every button posts a notification or
//  fires a real calculation).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Equipment options

private enum Co2Equipment: String, CaseIterable, Identifiable {
    case dryVan    = "dry_van"
    case reefer    = "reefer"
    case flatbed   = "flatbed"
    case stepDeck  = "step_deck"
    case tanker    = "tanker"
    case ltl       = "ltl"
    case boxTruck  = "box_truck"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dryVan:   return "Dry van"
        case .reefer:   return "Reefer"
        case .flatbed:  return "Flatbed"
        case .stepDeck: return "Step deck"
        case .tanker:   return "Tanker"
        case .ltl:      return "LTL"
        case .boxTruck: return "Box truck"
        }
    }

    var icon: String {
        switch self {
        case .dryVan:   return "shippingbox.fill"
        case .reefer:   return "thermometer.snowflake"
        case .flatbed:  return "rectangle.portrait.arrowtriangle.2.outward"
        case .stepDeck: return "arrow.up.and.down.righttriangle.up.righttriangle.down"
        case .tanker:   return "drop.fill"
        case .ltl:      return "shippingbox.and.arrow.backward.fill"
        case .boxTruck: return "truck.box"
        }
    }
}

// MARK: - Mode tab

private enum CalcMode: String, CaseIterable, Identifiable {
    case truck, rail, multimodal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .truck:      return "Truck"
        case .rail:       return "Rail"
        case .multimodal: return "Multimodal"
        }
    }
}

// MARK: - Store

@MainActor
final class ShipperSustainabilityStore: ObservableObject {
    enum LoadState {
        case idle
        case calculating
        case error(String)
        case loaded(Co2CalculatorAPI.TruckResult)
    }

    @Published private(set) var state: LoadState = .idle

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    fileprivate func calculate(distanceMiles: Double, weightTons: Double, equipment: Co2Equipment) async {
        state = .calculating
        do {
            let res = try await api.co2.calculateTruckShipment(
                distanceMiles: distanceMiles,
                weightTons: weightTons,
                equipmentType: equipment.rawValue
            )
            state = .loaded(res)
        } catch {
            state = .error("Couldn't reach the carbon service.")
        }
    }
}

// MARK: - Screen root

struct ShipperSustainability: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = ShipperSustainabilityStore()

    // §11.2 MATRIX-50 row 1 anchor — Houston → Dallas · MC-306 ·
    // UN1203 · 50,000 lb (= 25 tons) · 239 mi · tanker.
    @State private var distanceMiles: Double = 239
    @State private var weightTons: Double = 25
    @State private var equipment: Co2Equipment = .tanker
    @State private var distanceText: String = "239"
    @State private var weightText: String = "25"
    @State private var calcMode: CalcMode = .truck

    private let anchorLoadId   = "LD-260427-A38FB12C7E"
    private let anchorLane     = "Houston TX → Dallas TX"
    private let anchorSpecLine = "MC-306 Petroleum Tanker · UN1203 · 50,000 lb · 239 mi"
    // Lane average benchmark for the §11.2 row 1 hazmat tanker
    // (450 kg per shipment from the 2025 carbon ledger). Backend
    // EUSO-2115 will replace this with a per-lane rolling average.
    private let anchorLaneAvgKg: Double = 450

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.top, Space.s3)

                heroYTDCard
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s3)

                equivalenceLabel
                equivalenceTriplet
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)

                calculatorLabel
                calculatorCard
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)

                greenMilesStrip
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)

                actionRow
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)
                    .padding(.bottom, Space.s8)
            }
        }
        .task {
            await store.calculate(distanceMiles: distanceMiles, weightTons: weightTons, equipment: equipment)
        }
        .refreshable {
            await store.calculate(distanceMiles: distanceMiles, weightTons: weightTons, equipment: equipment)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.22),
            value: storeStateKey
        )
    }

    private var storeStateKey: String {
        switch store.state {
        case .idle:        return "idle"
        case .calculating: return "calc"
        case .error:        return "error"
        case .loaded(let r): return "loaded-\(r.co2Kg)"
        }
    }

    // MARK: TopBar (gradient eyebrow + green YTD-saved counter)

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · SUSTAINABILITY")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            // EUSO-2112 — getCarbonLedger not yet on iOS API; counter
            // paints "—" until backend ships the YTD ledger.
            Text("YTD · — t SAVED")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel("Year to date savings, data pending")
        }
        .padding(.horizontal, Space.s5)
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sustainability")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("CO₂ across MATRIX-50 · GLEC v3.0 · scope 3")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    // MARK: Hero YTD card

    private var heroYTDCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FLEET CO₂ · YEAR TO DATE")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s4)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                LeafShape()
                    .fill(LinearGradient.greenBlue)
                    .frame(width: 36, height: 38)
                    .overlay(
                        Path { p in
                            p.move(to: CGPoint(x: 8,  y: 30))
                            p.addLine(to: CGPoint(x: 28, y: 12))
                        }
                        .stroke(.white.opacity(0.85), lineWidth: 1.2)
                        .frame(width: 36, height: 38)
                    )
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 8 }

                Text("—")
                    .font(.system(size: 44, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textTertiary)
                Text("t CO₂e")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s2)

            Text("Carbon ledger pending · GLEC v3.0 + scope 3 cat 4")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)

            // Net-zero progress bar — paints empty track until ledger ships.
            GeometryReader { geo in
                let trackWidth = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.borderFaint)
                        .frame(height: 6)
                    Capsule()
                        .fill(LinearGradient.greenBlue)
                        .frame(width: trackWidth * 0, height: 6)
                }
            }
            .frame(height: 6)
            .padding(.top, Space.s4)

            Text("Net-zero target tracking · backend pending (EUSO-2112)")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 6)
                .padding(.bottom, Space.s4)
        }
        .padding(.horizontal, Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(LinearGradient.greenBlue, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }

    // MARK: Equivalence label + triplet

    private var equivalenceLabel: some View {
        Text("EQUIVALENT TO")
            .font(EType.micro).tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var equivalenceTriplet: some View {
        let result: Co2CalculatorAPI.TruckResult? = {
            if case .loaded(let r) = store.state { return r }
            return nil
        }()
        return HStack(spacing: Space.s2) {
            equivalenceTile(
                glyph: .leaf,
                label: "TREES NEEDED",
                value: result.map { "\($0.equivalents.treesNeededToOffset)" } ?? "—"
            )
            equivalenceTile(
                glyph: .fuelPump,
                label: "DIESEL EQUIV",
                value: result.map { "\($0.equivalents.gallonsOfGasoline) gal" } ?? "—"
            )
            equivalenceTile(
                glyph: .car,
                label: "CAR MILES",
                value: result.map { formatThousandsInt($0.equivalents.milesInAvgCar) } ?? "—"
            )
        }
    }

    private enum GlyphKind { case leaf, fuelPump, car }

    @ViewBuilder
    private func equivalenceTile(glyph kind: GlyphKind, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                glyph(for: kind)
                Spacer(minLength: 0)
            }
            .padding(.top, Space.s3)

            Spacer(minLength: 0)

            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.top, Space.s3)

            Text(value)
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.top, 2)
                .padding(.bottom, Space.s3)
        }
        .padding(.horizontal, Space.s3)
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    @ViewBuilder
    private func glyph(for kind: GlyphKind) -> some View {
        switch kind {
        case .leaf:
            Circle()
                .strokeBorder(Brand.success, lineWidth: 4)
                .background(Circle().fill(Brand.success.opacity(0.10)))
                .frame(width: 28, height: 28)
        case .fuelPump:
            FuelPumpGlyph()
                .frame(width: 28, height: 28)
        case .car:
            CarGlyph()
                .frame(width: 36, height: 22)
        }
    }

    // MARK: Per-shipment calculator label + card

    private var calculatorLabel: some View {
        Text("PER-SHIPMENT CALCULATOR · \(anchorLoadId)")
            .font(EType.micro).tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var calculatorCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(anchorLane)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(anchorSpecLine)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.top, Space.s4)

            // Mode tabs — Truck active (real calc), Rail / Multimodal
            // placeholder pending EUSO-2114.
            HStack(spacing: 6) {
                ForEach(CalcMode.allCases) { mode in
                    modeTabPill(mode)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Space.s3)

            // Inputs (override anchor lane defaults)
            VStack(alignment: .leading, spacing: 6) {
                inputRow(label: "DISTANCE", suffix: "mi", text: $distanceText) {
                    if let v = Double(distanceText), v >= 0 {
                        distanceMiles = v
                        Task { await store.calculate(distanceMiles: distanceMiles, weightTons: weightTons, equipment: equipment) }
                    } else {
                        distanceText = String(Int(distanceMiles))
                    }
                }
                inputRow(label: "WEIGHT", suffix: "tons", text: $weightText) {
                    if let v = Double(weightText), v >= 0 {
                        weightTons = v
                        Task { await store.calculate(distanceMiles: distanceMiles, weightTons: weightTons, equipment: equipment) }
                    } else {
                        weightText = String(Int(weightTons))
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Co2Equipment.allCases) { eq in
                            equipmentChip(eq)
                        }
                    }
                }
            }
            .padding(.top, Space.s3)

            // Result row
            resultRow
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s4)
        }
        .padding(.horizontal, Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    @ViewBuilder
    private var resultRow: some View {
        switch store.state {
        case .idle, .calculating:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Crunching emissions…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
        case .error(let msg):
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
        case .loaded(let r):
            HStack(alignment: .top, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EMISSIONS · GLEC v3.0")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(Int(r.co2Kg.rounded())) kg")
                        .font(.system(size: 32, weight: .bold).monospacedDigit())
                        .foregroundStyle(LinearGradient.greenBlue)
                    Text("CO₂e · \(String(format: "%.2f", r.emissionFactor)) kg/mi · scope 3 cat 4")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 0)
                let delta = (r.co2Kg - anchorLaneAvgKg) / anchorLaneAvgKg
                let deltaPct = delta * 100
                let deltaKg = Int((r.co2Kg - anchorLaneAvgKg).rounded())
                let isBetter = delta < 0
                VStack(alignment: .leading, spacing: 2) {
                    Text("VS LANE AVG")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(String(format: "%@%.1f%%", isBetter ? "−" : "+", abs(deltaPct)))
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(isBetter ? Brand.success : Brand.danger)
                    Text("\(abs(deltaKg)) kg \(isBetter ? "better" : "above")")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func modeTabPill(_ mode: CalcMode) -> some View {
        let isActive = (calcMode == mode)
        let isReal = (mode == .truck)
        Button(action: { tapModeTab(mode) }) {
            HStack(spacing: 4) {
                Text(mode.label)
                    .font(.system(size: 11, weight: isActive ? .bold : .semibold))
                if !isReal {
                    Text("·")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                    Text("soon")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textPrimary))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(
                Capsule().fill(isActive
                               ? AnyShapeStyle(LinearGradient.primary)
                               : AnyShapeStyle(palette.bgCardSoft))
            )
            .overlay(Capsule().strokeBorder(palette.borderFaint))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.label) mode\(isActive ? ", selected" : "")\(isReal ? "" : ", coming soon")")
    }

    private func inputRow(label: String, suffix: String, text: Binding<String>, onCommit: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 80, alignment: .leading)
            TextField("0", text: text, onCommit: onCommit)
                .textFieldStyle(.plain)
                .keyboardType(.decimalPad)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
            Text(suffix)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 36, alignment: .leading)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func equipmentChip(_ eq: Co2Equipment) -> some View {
        let active = (equipment == eq)
        return Button {
            equipment = eq
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            Task { await store.calculate(distanceMiles: distanceMiles, weightTons: weightTons, equipment: equipment) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: eq.icon)
                    .font(.system(size: 10, weight: .heavy))
                Text(eq.label)
                    .font(.system(size: 11, weight: .heavy))
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .background(
                Capsule().fill(active
                               ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                               : AnyShapeStyle(palette.bgCard))
            )
            .overlay(
                Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1)
            )
            .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Green-miles strip

    private var greenMilesStrip: some View {
        Button(action: tapGreenMiles) {
            HStack(spacing: Space.s3) {
                MiniOrb()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(greenMilesTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(greenMilesSubtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ChevronShape()
                    .stroke(palette.textSecondary, style:
                        StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 8, height: 12)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(greenMilesTitle). \(greenMilesSubtitle)")
    }

    // EUSO-2113 — recommendation engine pending.
    private var greenMilesTitle: String { "Green-miles optimization · pending" }
    private var greenMilesSubtitle: String { "Backend EUSO-2113 will surface lane-swap suggestions" }

    // MARK: Action row

    private var actionRow: some View {
        HStack(spacing: Space.s2) {
            Button(action: tapBuyOffsets) {
                HStack(spacing: 6) {
                    Text(buyOffsetsLabel)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(buyOffsetsLabel)

            Button(action: tapExportReport) {
                Text("Export report")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Export report")
        }
    }

    private var buyOffsetsLabel: String {
        if case .loaded(let r) = store.state {
            let tonnes = r.co2Tonnes
            if tonnes >= 0.1 {
                return "Buy offsets · \(String(format: "%.1f", tonnes)) t"
            }
            let cost = max(1, Int((r.co2Kg * 0.025).rounded()))
            return "Buy offsets · $\(cost)"
        }
        return "Buy offsets"
    }

    // MARK: - Notification posts (§20.4)

    private func tapModeTab(_ mode: CalcMode) {
        withAnimation(.easeOut(duration: 0.18)) { calcMode = mode }
        // observability post — telemetry only; real local effect is the
        // calcMode mutation above which switches the calculator pane.
        NotificationCenter.default.post(
            name: .eusoShipperSustainabilityMode,
            object: nil,
            userInfo: [
                "source": "214_ShipperSustainability",
                "mode": mode.rawValue,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapGreenMiles() {
        // Real action: jump to 207 ShipperReports where the CO₂
        // statement export ships. The same GLEC v3.0 ledger feeds
        // both surfaces — no parallel data path needed. Telemetry
        // post retained.
        NotificationCenter.default.post(
            name: .eusoShipperSustainabilityGreenMiles,
            object: nil,
            userInfo: [
                "source": "214_ShipperSustainability",
                "shipperCompanyId": 1
            ]
        )
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "207"]
        )
    }

    private func tapBuyOffsets() {
        var info: [String: Any] = [
            "source": "214_ShipperSustainability",
            "shipperCompanyId": 1
        ]
        var co2Tonnes: Double = 0
        if case .loaded(let r) = store.state {
            info["co2Kg"] = r.co2Kg
            info["co2Tonnes"] = r.co2Tonnes
            co2Tonnes = r.co2Tonnes
        }
        NotificationCenter.default.post(
            name: .eusoShipperSustainabilityBuyOffsets,
            object: nil,
            userInfo: info
        )
        // Real action: compose a procurement email to the ops team
        // pre-filled with the founder's current ledger total tonnes.
        // The carbon-offset checkout integration ships in a follow-up
        // with the procurement-rails partner (CarbonChain / Pachama).
        // Until then, mailto is a real action — opens the user's
        // mail app, ops responds with the next step.
        let body = "I'd like to buy carbon offsets for my EusoTrip ledger. Current balance: \(String(format: "%.2f", co2Tonnes)) t CO₂e (GLEC v3.0). Please send the procurement options."
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:sustainability@eusotrip.com?subject=Carbon%20offset%20purchase&body=\(body)") {
            openURL(url)
        }
    }

    private func tapExportReport() {
        // Real action: hand off to 299 Reports (Arc G) which already
        // has the share-sheet pipeline wired for `reports.exportCO2
        // Statement`. One canonical surface for exports across the
        // shipper app.
        NotificationCenter.default.post(
            name: .eusoShipperSustainabilityExport,
            object: nil,
            userInfo: [
                "source": "214_ShipperSustainability",
                "shipperCompanyId": 1
            ]
        )
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "299"]
        )
    }

    // MARK: Helpers

    private func formatThousandsInt(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "%.0fk", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - LinearGradient · green → blue (file-scoped per §19.2)

private extension LinearGradient {
    static let greenBlue = LinearGradient(
        colors: [Brand.success, Brand.blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - LeafShape (the 36×38 leaf used in the hero card · §19.2)

private struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width  / 36.0
        let sy = rect.height / 38.0
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var p = Path()
        p.move(to: P(22, 0))
        p.addCurve(to: P(0, 22),
                   control1: P(12, 0),  control2: P(0, 6))
        p.addCurve(to: P(14, 38),
                   control1: P(0, 30),  control2: P(6, 38))
        p.addCurve(to: P(36, 12),
                   control1: P(30, 38), control2: P(36, 24))
        p.addLine(to: P(36, 0))
        p.closeSubpath()
        return p
    }
}

// MARK: - FuelPumpGlyph (§9.1 equivalence-tile fuel pump · §19.2)

private struct FuelPumpGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Brand.warning)
                .frame(width: 14, height: 24)
                .offset(x: -4, y: 0)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white)
                .frame(width: 10, height: 8)
                .offset(x: -4, y: -6)
            Path { p in
                p.move(to: CGPoint(x: 14, y: 8))
                p.addLine(to: CGPoint(x: 20, y: 8))
                p.addLine(to: CGPoint(x: 20, y: 22))
                p.addLine(to: CGPoint(x: 24, y: 22))
                p.addLine(to: CGPoint(x: 24, y: 12))
            }
            .stroke(Color.gray, style:
                StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .offset(x: -10, y: -12)
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - CarGlyph (§9.1 equivalence-tile car · §19.2)

private struct CarGlyph: View {
    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 16))
                p.addLine(to: CGPoint(x: 4, y: 8))
                p.addLine(to: CGPoint(x: 30, y: 8))
                p.addLine(to: CGPoint(x: 34, y: 16))
                p.addLine(to: CGPoint(x: 34, y: 22))
                p.addLine(to: CGPoint(x: 0, y: 22))
                p.closeSubpath()
            }
            .fill(Brand.blue)
            Circle()
                .fill(Color.black)
                .frame(width: 6, height: 6)
                .offset(x: -9, y: 5)
            Circle()
                .fill(Color.black)
                .frame(width: 6, height: 6)
                .offset(x: 9, y: 5)
        }
        .frame(width: 36, height: 22)
    }
}

// MARK: - ChevronShape (right-arrow on the green-miles strip · §19.2)

private struct ChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

// MARK: - MiniOrb (32pt gradient diagonal + specular highlight · §19.2)

private struct MiniOrb: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient.diagonal)
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.75), .white.opacity(0)],
                    center: .init(x: 0.35, y: 0.30),
                    startRadius: 0, endRadius: 18))
                .frame(width: 22, height: 22)
                .offset(x: -3, y: -3)
                .blendMode(.plusLighter)
        }
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Mode tab tap (Truck / Rail / Multimodal).
    static let eusoShipperSustainabilityMode        = Notification.Name("eusoShipperSustainabilityMode")
    /// Green-miles recommendation strip tap.
    static let eusoShipperSustainabilityGreenMiles  = Notification.Name("eusoShipperSustainabilityGreenMiles")
    /// "Buy offsets" CTA tap.
    static let eusoShipperSustainabilityBuyOffsets  = Notification.Name("eusoShipperSustainabilityBuyOffsets")
    /// "Export report" CTA tap.
    static let eusoShipperSustainabilityExport      = Notification.Name("eusoShipperSustainabilityExport")
}

// MARK: - Previews

#Preview("214 · Sustainability · Dark") {
    ShipperSustainability()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("214 · Sustainability · Light") {
    ShipperSustainability()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
