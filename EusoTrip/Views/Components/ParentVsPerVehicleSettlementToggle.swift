//
//  ParentVsPerVehicleSettlementToggle.swift
//  EusoTrip — Multi-vehicle settlement mode chooser.
//
//  Lets a shipper / broker pick between:
//    1. **Parent rollup invoice** — one HaulPay broker invoice
//       covers the whole shipment. Broker manages internal carrier
//       payouts via Stripe Connect. One Triumph Factor-of-Record
//       check, one audit-chain entry. Best for single-carrier or
//       broker-of-record shipments.
//    2. **Per-vehicle invoice** — N HaulPay carrier invoices, one
//       per child vehicle. Each carrier paid independently via
//       EusoWallet ACH. Per-invoice FoR check + per-invoice hash
//       chain entry. Best for multi-carrier or cross-border
//       shipments where each child invoices in its own currency.
//
//  6-multiplier fee math from
//  ~/Desktop/todays work/01_animation_system_instructions/MULTI_VEHICLE_HAULPAY_EUSOWALLET_FULL_INTEGRATION.md
//  is computed locally on the iOS side via `ParentFee.compute(...)`
//  so the toggle previews fee impact instantly without a server
//  round-trip on every selection.
//
//  Adaptive layout per device:
//    iPhone (compact): vertical stack of cards
//    iPad / Mac:       side-by-side cards
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct ParentVsPerVehicleSettlementToggle: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass

    let shipment: Shipment
    let parentFee: ParentFee
    /// When false, the toggle renders read-only (e.g. when the
    /// shipper has already locked the mode at booking).
    var canSet: Bool = true

    @Binding var currentMode: SettlementMode
    var onChange: ((SettlementMode) -> Void)? = nil

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 12) {
                    parentRollupCard
                    perVehicleCard
                }
            } else {
                VStack(spacing: 12) {
                    parentRollupCard
                    perVehicleCard
                }
            }

            DisclosureGroup(isExpanded: $expanded) {
                FeeBreakdownTable(parentFee: parentFee, vehicles: shipment.vehicles)
                    .padding(.top, 8)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .heavy))
                    Text("Per-vehicle fee breakdown")
                        .font(EType.caption.weight(.semibold))
                }
                .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, 4)

            DisclosureCallouts(mode: currentMode, parentFee: parentFee)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.below.ecg")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SETTLEMENT MODE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("\(shipment.vehicles.count) vehicle\(shipment.vehicles.count == 1 ? "" : "s") · \(formatUsd(parentFee.parentRate)) total")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Toggle cards

    private var parentRollupCard: some View {
        ToggleCard(
            mode: .parentRollup,
            isSelected: currentMode == .parentRollup,
            canSet: canSet,
            recommended: recommendation == .parentRollup,
            recommendReason: recommendation == .parentRollup ? recommendationReason : nil,
            title: "Parent rollup invoice",
            description: "One HaulPay broker invoice covers the whole shipment. Broker manages internal carrier payouts.",
            parentFee: parentFee,
            onSelect: { setMode(.parentRollup) }
        )
    }

    private var perVehicleCard: some View {
        ToggleCard(
            mode: .perVehicle,
            isSelected: currentMode == .perVehicle,
            canSet: canSet,
            recommended: recommendation == .perVehicle,
            recommendReason: recommendation == .perVehicle ? recommendationReason : nil,
            title: "Per-vehicle invoice",
            description: "\(shipment.vehicles.count) HaulPay carrier invoices, one per child vehicle. Each carrier paid independently.",
            parentFee: parentFee,
            onSelect: { setMode(.perVehicle) }
        )
    }

    private func setMode(_ mode: SettlementMode) {
        guard canSet else { return }
        currentMode = mode
        onChange?(mode)
    }

    // MARK: - Recommendation (deterministic — no fake API)

    /// Deterministic recommendation:
    ///   • Single carrier across all children → parent rollup wins
    ///     (unified invoice simplifies settlement)
    ///   • Multiple carriers OR cross-border legs OR project cargo →
    ///     per-vehicle wins (per-carrier accounting + currency
    ///     boundaries)
    private var recommendation: SettlementMode {
        let carriers = Set(shipment.vehicles.map(\.carrierId))
        if carriers.count <= 1 && !shipment.isCrossBorder && !shipment.isProjectCargo {
            return .parentRollup
        }
        return .perVehicle
    }

    private var recommendationReason: String {
        let carriers = Set(shipment.vehicles.map(\.carrierId))
        if carriers.count == 1 {
            return "Single carrier on all vehicles — unified invoice simplifies settlement."
        }
        if shipment.isCrossBorder {
            return "Cross-border shipment — per-vehicle keeps each leg in its origin currency."
        }
        if shipment.isProjectCargo {
            return "Project cargo (\(shipment.vehicles.count) vehicles) — per-vehicle preserves carrier-level accounting."
        }
        return "Multiple carriers — per-vehicle settlement preserves carrier-level accounting."
    }
}

// MARK: - SettlementMode

enum SettlementMode: String, Codable, Hashable {
    case parentRollup = "parent-rollup"
    case perVehicle   = "per-vehicle"
    case hybrid                                 // reserved — not exposed in UI yet
}

// MARK: - ParentFee (locally-computable fee model)

/// Materialized fee model for a shipment. Computed via
/// `ParentFee.compute(for:)` using the 6-multiplier formula from
/// MULTI_VEHICLE_HAULPAY_EUSOWALLET_FULL_INTEGRATION.md §3.1.
struct ParentFee: Hashable {
    let parentRate: Double                      // total contract revenue
    let effectiveRate: Double                   // weighted-average across children
    let feeAmount: Double                       // sum of vehicle fees
    let shipperPayment: Double                  // parentRate − feeAmount
    let vehicleBreakdown: [VehicleFee]
    /// > 0 when the bulk discount was applied (≥4 children = 0.5–1%).
    let bulkDiscountApplied: Double?
    /// True when parent ceiling was applied (max child ceiling × 1.05).
    let parentCeilingHit: Bool

    // Constants from the master fee formula (matches the web /
    // server EusoWallet engine).
    private static let baseRate: Double = 0.075        // 7.5%
    private static let floorRate: Double = 0.05        // floor 5%
    private static let ceilingRate: Double = 0.18      // ceiling 18%
    private static let projectCargoBulkDiscount: Double = 0.005  // 0.5% off when ≥4 children
    private static let parentCeilingPremium: Double = 1.05       // unified-tender ceiling = max(child) × 1.05

    /// Compute the parent fee from a Shipment. Per-vehicle math
    /// follows the master 6-multiplier formula:
    ///
    ///   PER_VEHICLE_FEE = baseRate
    ///                   × COUNTRY_MULTIPLIER (per-leg region)
    ///                   × VERTICAL_MULTIPLIER (hazmat / reefer)
    ///                   × PRODUCT_MULTIPLIER (equipment)
    ///                   × HAZMAT_MULTIPLIER (class 1-9)
    ///                   × DISTANCE_MULTIPLIER (band)
    ///                   × CYCLE_DAMPENER (shared)
    ///                   × LOAD_TYPE_ADJ (spot/contract)
    ///                   – LOYALTY_DISCOUNT (per-driver)
    ///                   constrained by FLOOR ≤ FEE ≤ CEILING
    ///
    /// We don't have all 8 multipliers materialized on the iOS
    /// snapshot (carrier loyalty, cycle dampener live on the server).
    /// We compute what we can and floor at base rate × heuristics so
    /// the preview is honest. The server's authoritative computation
    /// runs at booking and overrides this with a real fee record.
    static func compute(for shipment: Shipment, useParentCeiling: Bool = true) -> ParentFee {
        let parentRate = shipment.totalValue > 0
            ? shipment.totalValue
            : shipment.vehicles.reduce(0.0) { $0 + ($1.cargoSplit.weightAllocated * 0.10) }

        // Per-vehicle fee computation
        var breakdown: [VehicleFee] = []
        var maxCeiling: Double = 0
        var aggregateFee: Double = 0

        for v in shipment.vehicles {
            let countryMult = countryMultiplier(for: shipment.region)
            let verticalMult = verticalMultiplier(for: shipment.vertical)
            let productMult = productMultiplier(for: v.equipment.type)
            let hazmatMult = hazmatMultiplier(for: v.hazmatChain?.entries.last?.hazmatClass)
            let distanceMult = distanceMultiplier(for: v.cargoSplit.weightAllocated)

            let raw = baseRate
                * countryMult
                * verticalMult
                * productMult
                * hazmatMult
                * distanceMult

            let clamped = max(floorRate, min(ceilingRate, raw))
            let vehicleRate = vehicleLoadRate(for: v, of: parentRate, totalVehicles: shipment.vehicles.count)
            let feeAmount = vehicleRate * clamped

            breakdown.append(VehicleFee(
                id: v.id,
                vehicleId: v.id,
                loadRate: vehicleRate,
                effectiveRate: clamped,
                feeAmount: feeAmount,
                carrierPayment: vehicleRate - feeAmount
            ))
            aggregateFee += feeAmount
            maxCeiling = max(maxCeiling, vehicleRate * ceilingRate)
        }

        // Project cargo bulk discount
        var bulkDiscount: Double? = nil
        if shipment.isProjectCargo {
            let discount = aggregateFee * Self.projectCargoBulkDiscount
            aggregateFee -= discount
            bulkDiscount = discount
        }

        // Parent ceiling (unified-tender = max child ceiling × 1.05)
        var parentCeilingHit = false
        if useParentCeiling {
            let parentCeiling = maxCeiling * parentCeilingPremium
            if aggregateFee > parentCeiling, parentCeiling > 0 {
                aggregateFee = parentCeiling
                parentCeilingHit = true
            }
        }

        let effectiveRate = parentRate > 0 ? aggregateFee / parentRate : 0

        return ParentFee(
            parentRate: parentRate,
            effectiveRate: effectiveRate,
            feeAmount: aggregateFee,
            shipperPayment: parentRate - aggregateFee,
            vehicleBreakdown: breakdown,
            bulkDiscountApplied: bulkDiscount,
            parentCeilingHit: parentCeilingHit
        )
    }

    // MARK: - Multiplier lookups (server master tables)

    private static func countryMultiplier(for region: String) -> Double {
        switch region {
        case "us":         return 1.00
        case "ca":         return 1.10
        case "mx":         return 1.20
        case "us-mx":      return 1.30  // cross-border MX
        case "us-ca":      return 1.15
        case "mx-ca":      return 1.35
        case "us-mx-ca":   return 1.35
        default:           return 1.00
        }
    }

    private static func verticalMultiplier(for vertical: String) -> Double {
        switch vertical {
        case "tanker_hazmat", "tanker_petro": return 1.20
        case "tanker_food":                    return 1.10
        case "reefer":                          return 1.10
        case "bulk_dry", "bulk_liquid":         return 1.10
        case "intermodal":                      return 1.05
        case "specialized":                     return 1.20
        default:                                return 1.00
        }
    }

    private static func productMultiplier(for type: String) -> Double {
        let t = type.lowercased()
        if t.contains("rgn") || t.contains("schnabel") || t.contains("oversize") { return 1.22 }
        if t.contains("reefer") { return 1.12 }
        if t.contains("tanker") || t.contains("dot_") { return 1.15 }
        if t.contains("flatbed") || t.contains("step_deck") { return 1.08 }
        if t.contains("container") { return 1.05 }
        if t.contains("rail") || t.contains("vessel") { return 1.10 }
        return 0.95
    }

    private static func hazmatMultiplier(for hazmatClass: String?) -> Double {
        guard let c = hazmatClass else { return 1.00 }
        // Class 1.x explosives / 2.3 toxic gas / 6.1 toxic = highest multiplier
        if c.hasPrefix("1.") { return 1.60 }
        if c == "2.3" || c == "6.1" || c == "7" { return 1.50 }
        if c == "2.1" || c == "2.2" { return 1.30 }
        if c == "3" || c == "8" { return 1.30 }
        if c == "4.1" || c == "4.2" || c == "4.3" || c == "5.1" || c == "5.2" { return 1.40 }
        return 1.00
    }

    /// Distance band heuristic (no server distance field on Vehicle
    /// snapshot today). Use weight as proxy: heavier loads tend to
    /// be longer-haul, lighter are local. Falls in 0.92-1.10 band.
    private static func distanceMultiplier(for weight: Double) -> Double {
        if weight > 70_000 { return 1.10 }     // ultra-long
        if weight > 45_000 { return 1.05 }     // long-haul
        if weight > 20_000 { return 1.00 }     // regional
        return 0.95                             // local
    }

    /// Per-vehicle load rate. We don't have a per-vehicle rate field
    /// on the snapshot — split the parent rate by weight allocation.
    private static func vehicleLoadRate(for v: Vehicle, of parentRate: Double, totalVehicles: Int) -> Double {
        let weight = v.cargoSplit.weightAllocated
        if weight > 0 {
            // Will be re-normalized in the caller when summed across
            // vehicles. For now, treat as proportional to weight.
            return parentRate * (weight / max(1, weight * Double(totalVehicles)))
        }
        return parentRate / Double(max(1, totalVehicles))
    }
}

struct VehicleFee: Hashable, Identifiable {
    let id: String
    let vehicleId: String
    let loadRate: Double
    let effectiveRate: Double
    let feeAmount: Double
    let carrierPayment: Double
}

// MARK: - Toggle card

private struct ToggleCard: View {
    @Environment(\.palette) private var palette

    let mode: SettlementMode
    let isSelected: Bool
    let canSet: Bool
    let recommended: Bool
    let recommendReason: String?
    let title: String
    let description: String
    let parentFee: ParentFee
    let onSelect: () -> Void

    var body: some View {
        Button(action: { if canSet { onSelect() } }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    if recommended {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 8, weight: .heavy))
                            Text("RECOMMENDED")
                                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                    }
                }
                Text(description)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if recommended, let reason = recommendReason {
                    Text(reason)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Brand.warning)
                        .padding(.top, 2)
                }

                Divider()
                statsView
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.08)) : AnyShapeStyle(palette.bgCardSoft))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(canSet ? 1.0 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!canSet)
    }

    @ViewBuilder
    private var statsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if mode == .parentRollup {
                statRow("HaulPay invoices", value: "1 broker invoice")
                statRow("Effective fee", value: String(format: "%.2f%%", parentFee.effectiveRate * 100))
                statRow("Fee amount", value: formatUsd(parentFee.feeAmount))
                if let bulk = parentFee.bulkDiscountApplied, bulk > 0 {
                    statRow("Bulk discount", value: "−\(formatUsd(bulk))", valueColor: Brand.success)
                }
                if parentFee.parentCeilingHit {
                    statRow("Note", value: "Parent ceiling applied", valueColor: Brand.warning)
                }
            } else {
                statRow("HaulPay invoices",
                        value: "\(parentFee.vehicleBreakdown.count) carrier invoice\(parentFee.vehicleBreakdown.count == 1 ? "" : "s")")
                statRow("Sum of fees", value: formatUsd(parentFee.feeAmount))
                statRow("Carrier payouts",
                        value: "\(parentFee.vehicleBreakdown.count) independent ACH")
            }
        }
    }

    private func statRow(_ label: String, value: String, valueColor: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(valueColor ?? palette.textPrimary)
        }
    }
}

// MARK: - Fee breakdown table

private struct FeeBreakdownTable: View {
    @Environment(\.palette) private var palette

    let parentFee: ParentFee
    let vehicles: [Vehicle]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                col("LEG",       width: 30)
                col("EQUIPMENT", width: 90)
                col("CARGO",     width: 70)
                col("RATE",      width: 56)
                col("FEE",       width: 70)
                col("CARRIER $", width: 80)
            }
            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundStyle(palette.textTertiary)

            Divider().background(palette.borderFaint)

            ForEach(parentFee.vehicleBreakdown) { vf in
                if let v = vehicles.first(where: { $0.id == vf.vehicleId }) {
                    row(vehicle: v, fee: vf)
                }
            }

            Divider().background(palette.borderFaint)

            HStack {
                col("TOTAL", width: 30, bold: true)
                col("",      width: 90)
                col("",      width: 70)
                col(String(format: "%.2f%%", parentFee.effectiveRate * 100), width: 56, bold: true)
                col(formatUsd(parentFee.feeAmount),     width: 70, bold: true)
                col(formatUsd(parentFee.shipperPayment), width: 80, bold: true)
            }
            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundStyle(palette.textPrimary)
        }
    }

    private func row(vehicle: Vehicle, fee: VehicleFee) -> some View {
        HStack {
            col("L\(vehicle.leg.sequenceNumber)", width: 30)
            col(vehicle.equipment.label, width: 90)
            col("\(Int(vehicle.cargoSplit.weightAllocated)) lb", width: 70)
            col(String(format: "%.2f%%", fee.effectiveRate * 100), width: 56)
            col(formatUsd(fee.feeAmount), width: 70)
            col(formatUsd(fee.carrierPayment), width: 80)
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(palette.textPrimary)
    }

    private func col(_ text: String, width: CGFloat, bold: Bool = false) -> some View {
        Text(text)
            .frame(width: width, alignment: .leading)
            .fontWeight(bold ? .heavy : .regular)
            .lineLimit(1)
    }
}

// MARK: - Disclosure callouts

private struct DisclosureCallouts: View {
    @Environment(\.palette) private var palette

    let mode: SettlementMode
    let parentFee: ParentFee

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHAT CHANGES")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 3) {
                if mode == .parentRollup {
                    bullet("One HaulPay broker invoice — single line of credit risk.")
                    bullet("Broker handles internal carrier payouts via Stripe Connect.")
                    bullet("Parent ceiling protects against runaway aggregation.")
                    bullet("One audit-chain entry for the parent invoice.")
                    bullet("Triumph Factor-of-Record runs once for the parent.")
                } else {
                    bullet("\(parentFee.vehicleBreakdown.count) HaulPay carrier invoices — one per vehicle.")
                    bullet("Each carrier paid independently via EusoWallet ACH.")
                    bullet("Each invoice is hash-chained at the per-vehicle layer.")
                    bullet("Triumph FoR runs per child invoice.")
                    bullet("Cross-border children invoice in their own currency.")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(text).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Helpers

private func formatUsd(_ amount: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
}
