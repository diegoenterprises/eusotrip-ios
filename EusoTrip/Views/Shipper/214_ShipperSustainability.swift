//
//  214_ShipperSustainability.swift
//  EusoTrip 2027 UI — brick 214 (shipper · sustainability + CO2)
//
//  Per-shipment carbon-footprint calculator + equivalence helpers
//  (trees-to-offset, gallons-of-gasoline equivalent, car-miles
//  equivalent) + offset-cost surface. Mirrors the web `/co2-calculator`
//  route (`CO2Calculator.tsx`). Backed verbatim by
//  `co2Calculator.calculateTruckShipment`.
//
//  Shipper-side intent: a shipper picks a representative load shape
//  (or accepts the defaults from their typical lane), gets a real
//  emissions number, sees what it costs to offset, and pulls the
//  trigger on a carbon-neutral commitment for that lane. Mirrors
//  Uber Freight's "Sustainability" product surface.
//
//  Design doctrine (per Driver Figma 010-103):
//    §1   Gradient-green hero card for the headline CO2 number,
//         3 equivalence tiles below it, gradient-blue→magenta CTAs.
//    §2   `.easeOut(0.12)` press scale on the calculate CTA, success
//         haptic on a non-zero result.
//    §4   Tokenized Space/Radius/EType.
//    §5   Palette semantic. Brand.success on the green hero.
//    §10  Dark + Light previews.
//
//  Powered by ESANG AI™.
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

    func calculate(distanceMiles: Double, weightTons: Double, equipment: Co2Equipment) async {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = ShipperSustainabilityStore()

    @State private var distanceMiles: Double = 500
    @State private var weightTons: Double = 20
    @State private var equipment: Co2Equipment = .dryVan
    @State private var distanceText: String = "500"
    @State private var weightText: String = "20"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                inputCard
                resultSection
                methodologyCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.calculate(distanceMiles: distanceMiles, weightTons: weightTons, equipment: equipment) }
        .refreshable { await store.calculate(distanceMiles: distanceMiles, weightTons: weightTons, equipment: equipment) }
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

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · SUSTAINABILITY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Carbon footprint")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("CO2 emissions per shipment, equivalence helpers, and offset pricing — your green-miles ledger.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: Input card

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("LANE INPUT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)

            // Distance
            inputRow(
                label: "DISTANCE",
                suffix: "mi",
                text: $distanceText,
                onCommit: {
                    if let v = Double(distanceText), v >= 0 { distanceMiles = v }
                    else { distanceText = String(Int(distanceMiles)) }
                }
            )
            // Weight
            inputRow(
                label: "WEIGHT",
                suffix: "tons",
                text: $weightText,
                onCommit: {
                    if let v = Double(weightText), v >= 0 { weightTons = v }
                    else { weightText = String(Int(weightTons)) }
                }
            )
            // Equipment picker
            VStack(alignment: .leading, spacing: 6) {
                Text("EQUIPMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Co2Equipment.allCases) { eq in
                            equipmentChip(eq)
                        }
                    }
                }
            }
            // Calculate CTA
            Button {
                Task {
                    if let v = Double(distanceText), v > 0 { distanceMiles = v }
                    if let w = Double(weightText), w > 0 { weightTons = w }
                    #if canImport(UIKit)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                    await store.calculate(distanceMiles: distanceMiles, weightTons: weightTons, equipment: equipment)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .heavy))
                    Text("Calculate footprint")
                        .font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(SustainabilityCTAStyle())
            .disabled(isCalculating)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var isCalculating: Bool {
        if case .calculating = store.state { return true }
        return false
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
                .font(.system(size: 18, weight: .heavy, design: .rounded))
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

    // MARK: Result section (state machine)

    @ViewBuilder
    private var resultSection: some View {
        switch store.state {
        case .idle:
            EmptyView()
        case .calculating:
            HStack(spacing: 8) {
                ProgressView().controlSize(.regular)
                Text("Crunching emissions…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let msg):
            errorBanner(msg)
        case .loaded(let r):
            heroResultCard(r)
            equivalencesGrid(r.equivalents)
            offsetCostCard(r)
        }
    }

    private func heroResultCard(_ r: Co2CalculatorAPI.TruckResult) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CO2 EMISSIONS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("FACTOR \(String(format: "%.3f", r.emissionFactor))")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Brand.success.opacity(0.18)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatKg(r.co2Kg))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("kg CO2")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.success)
                Text("\(formatTonnes(r.co2Tonnes)) tonnes")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Brand.success.opacity(0.18), Brand.blue.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func equivalencesGrid(_ e: Co2CalculatorAPI.Equivalents) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("EQUIVALENT TO")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                equivTile(icon: "leaf.fill",        label: "TREES NEEDED",   value: "\(e.treesNeededToOffset)",  sub: "to offset")
                equivTile(icon: "fuelpump.fill",    label: "GAS GALLONS",    value: "\(e.gallonsOfGasoline)", sub: "burned")
                equivTile(icon: "car.fill",         label: "CAR MILES",     value: formatThousandsInt(e.milesInAvgCar), sub: "driven")
            }
        }
    }

    private func equivTile(icon: String, label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func offsetCostCard(_ r: Co2CalculatorAPI.TruckResult) -> some View {
        // Server's web peer uses the heuristic `co2Kg * 0.025` USD per
        // kg as a market-aligned offset price. Mirror that locally so
        // the iOS surface reads the same number as the web.
        let cost = max(1, Int((r.co2Kg * 0.025).rounded()))
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("OFFSET THIS LOAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("$\(cost)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Text("for full offset")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
            Text("Reforestation + verified-credits market price · ~$0.025 per kg CO2.")
                .font(EType.micro).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                MeAction.fire("sustainability.offset-load", userInfo: ["co2Kg": r.co2Kg, "costUsd": cost])
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.arrow.triangle.circlepath")
                        .font(.system(size: 12, weight: .heavy))
                    Text("Offset $\(cost)")
                        .font(.system(size: 13, weight: .heavy))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(SustainabilityCTAStyle())
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Methodology disclosure

    private var methodologyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text("How this is calculated")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("CO2 = distance × weight × emission factor. Emission factors come from EPA SmartWay / GHG Protocol, calibrated by equipment type. The trees-to-offset metric uses the IPCC standard of 21.77 kg CO2 absorbed per tree-year. Car-mile equivalence uses 0.404 kg CO2 per mile (US passenger fleet average).")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Helpers

    private func errorBanner(_ msg: String) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Calculator offline")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.calculate(distanceMiles: distanceMiles, weightTons: weightTons, equipment: equipment) }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func formatKg(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 10_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        if n >= 1_000  { return String(format: "%.2fk", Double(n) / 1_000) }
        return "\(n)"
    }

    private func formatTonnes(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10  { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    private func formatThousandsInt(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "%.0fk", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - CTA press feedback

private struct SustainabilityCTAStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("214 · Sustainability · Night") {
    ShipperSustainability()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("214 · Sustainability · Afternoon") {
    ShipperSustainability()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
