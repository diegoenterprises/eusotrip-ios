//
//  596_RailDutyHTSEstimate.swift
//  EusoTrip — Rail Engineer · Duty / HTS Estimate (cross-border duty money ledger).
//
//  ARCHETYPE = DUTY MONEY LEDGER. For a cross-border rail import (MX→US),
//  the carrier/forwarder sees the duty + fees owed per HTS line and the
//  exact dollars USMCA (T-MEC) certification would save. The USMCA saving
//  is surfaced as the hero opportunity so certifying origin is one tap.
//
//  Wired to crossBorder.calculateDutiesAndTaxes (deterministic per-line
//  duty/tax/MPF + usmcaSavings + grandTotal; logs CROSS_BORDER_DUTY_CALCULATED).
//  HTS classification rates come from crossBorder.getHtsClassification.
//  transportMode=rail · MX→US import · HTS 8708 auto parts · MPF 19 CFR 24.23
//  · FX USD static (no live feed, per router comment 2025-01-01).
//

import SwiftUI

struct RailDutyHTSEstimateScreen: View {
    let theme: Theme.Palette
    /// Commodities to classify + cost. Defaults to the canonical MX→US
    /// HTS 8708 auto-parts manifest the wireframe is reconstructed from.
    var commodities: [RailDutyCommodityInput] = RailDutyCommodityInput.defaultManifest
    var origin: String = "MX"
    var destination: String = "US"
    var currency: String = "USD"

    var body: some View {
        Shell(theme: theme) {
            RailDutyHTSEstimateBody(
                commodities: commodities,
                origin: origin,
                destination: destination,
                currency: currency
            )
        } nav: {
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

// MARK: - Inputs

/// One declared commodity line for the duty calculator. Mirrors the
/// crossBorder.calculateDutiesAndTaxes `commodities[]` z.object exactly.
struct RailDutyCommodityInput: Encodable {
    var htsCode: String = ""
    var description: String = ""
    var value: Double = 0
    var weight: Double = 0
    var quantity: Int = 0

    /// Canonical MX→US rail import manifest — HTS 8708 auto parts.
    /// (Body stampings & bumpers · Other motor-vehicle parts.)
    static let defaultManifest: [RailDutyCommodityInput] = [
        RailDutyCommodityInput(htsCode: "8708.29", description: "Body stampings & bumpers",
                               value: 48_200, weight: 12_400, quantity: 1),
        RailDutyCommodityInput(htsCode: "8708.99", description: "Other motor-vehicle parts",
                               value: 12_400, weight: 3_100, quantity: 1)
    ]
}

// MARK: - Wire shapes (crossBorder.calculateDutiesAndTaxes return)

private struct DutyCalcInput: Encodable {
    let origin: String
    let destination: String
    let commodities: [RailDutyCommodityInput]
    let usmcaCertified: Bool
    let currency: String
}

private struct DutyCalcResult: Decodable {
    let route: String?
    let currency: String?
    let lineItems: [DutyLineItem]
    let summary: DutySummary
    let disclaimer: String?
}

private struct DutyLineItem: Decodable, Identifiable {
    let lineNumber: Int
    let htsCode: String
    let description: String
    let declaredValue: Double
    let dutyRate: Double
    let dutyAmount: Double
    let taxRate: Double
    let taxName: String
    let taxAmount: Double
    let totalCharges: Double
    let usmcaSavings: Double

    var id: Int { lineNumber }
}

private struct DutySummary: Decodable {
    let totalDeclaredValue: Double
    let totalDuty: Double
    let totalTax: Double
    let merchandiseProcessingFee: Double
    let harborMaintenanceFee: Double
    let brokerageFee: Double
    let grandTotal: Double
    let usmcaSavings: Double
    let usmcaCertified: Bool
}

// MARK: - Body

private struct RailDutyHTSEstimateBody: View {
    let commodities: [RailDutyCommodityInput]
    let origin: String
    let destination: String
    let currency: String

    @Environment(\.palette) private var palette

    /// The "as-shipped" calc (NOT certified) — what's owed today.
    @State private var asShipped: DutyCalcResult? = nil
    /// The certified calc — drives the "USMCA saves" opportunity number.
    @State private var certified: DutyCalcResult? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Money formatting --------------------------------------------------

    private let money: (Double) -> String = { v in
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
    private let moneyWhole: (Double) -> String = { v in
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    /// Dollars USMCA certification would save (duty that drops to 0%).
    /// The router only populates `usmcaSavings` on the *certified* run,
    /// so read it from there; fall back to the as-shipped duty total.
    private var usmcaSaves: Double {
        certified?.summary.usmcaSavings ?? asShipped?.summary.totalDuty ?? 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                IridescentHairline()
                titleRow

                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if let calc = asShipped {
                    heroCard(calc)
                    metricRow(calc)
                    ledgerCard(calc)
                    opportunityCard(calc)
                    ctaRow
                } else {
                    EusoEmptyState(systemImage: "dollarsign.circle",
                                   title: "No duty estimate",
                                   subtitle: "Duty & tax line items will appear here.")
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow + reference id)

    private var topBar: some View {
        HStack(alignment: .top) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("RAIL ENGINEER · DUTY ESTIMATE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text("RAIL-260523-7C3A0B12D4")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title row (back chevron · "Duty estimate" · overflow)

    private var titleRow: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Text("Duty estimate")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 128)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 72)
            }
        }
    }

    // MARK: - Hero card (landed total + USMCA savings)

    private func heroCard(_ calc: DutyCalcResult) -> some View {
        let landed = calc.summary.grandTotal
        let lineCount = calc.lineItems.filter { $0.htsCode.hasPrefix("8708") || $0.dutyAmount > 0 || $0.taxAmount > 0 }.count
        return VStack(alignment: .leading, spacing: Space.s4) {
            // Badge row
            HStack(spacing: Space.s2) {
                Text("MX→US IMPORT")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(Brand.info)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.info.opacity(0.18)))
                Text("USMCA eligible")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                Spacer(minLength: 0)
            }
            // Landed total + USMCA saves
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(money(landed))
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text("landed duty + fees")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text("\(commodities.count) line items · \(calc.currency ?? currency)")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("USMCA SAVES")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(moneyWhole(usmcaSaves))
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Brand.success)
                    Text("if certified")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Landed duty and fees \(money(landed)), \(lineCount) lines, USMCA saves \(moneyWhole(usmcaSaves)) if certified")
    }

    // MARK: - Metric row (DUTY · TAX · MPF)

    private func metricRow(_ calc: DutyCalcResult) -> some View {
        HStack(spacing: Space.s2) {
            miniTile(label: "DUTY", value: money(calc.summary.totalDuty), gradientNumeral: true)
            miniTile(label: "TAX (US)", value: money(calc.summary.totalTax))
            miniTile(label: "MPF", value: money(calc.summary.merchandiseProcessingFee))
        }
    }

    private func miniTile(label: String, value: String, gradientNumeral: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Group {
                if gradientNumeral {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(value).foregroundStyle(palette.textPrimary)
                }
            }
            .font(.system(size: 18, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Ledger card (per-HTS-line duty & tax · USD)

    private func ledgerCard(_ calc: DutyCalcResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section eyebrow
            HStack {
                Text("DUTY & TAX · USD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("HTS 8708 · auto parts")
                    .font(.system(size: 11, weight: .bold)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s2)

            VStack(spacing: 0) {
                // Per-line duty rows
                ForEach(Array(calc.lineItems.enumerated()), id: \.element.id) { idx, line in
                    ledgerRow(
                        title: "\(line.htsCode) · \(line.description)",
                        meta: String(format: "val %@ · %@%%",
                                     moneyWhole(line.declaredValue),
                                     trimRate(line.dutyRate)),
                        amount: money(line.dutyAmount)
                    )
                    Divider().overlay(palette.borderFaint)
                }
                // MPF row
                ledgerRow(
                    title: "MPF · Merchandise processing fee",
                    meta: "19 CFR 24.23 · min",
                    amount: money(calc.summary.merchandiseProcessingFee)
                )
                Divider().overlay(palette.borderFaint)
                // Tax row (no federal tax on US imports)
                ledgerRow(
                    title: federalTaxTitle(calc),
                    meta: calc.summary.totalTax == 0 ? "None" : taxNames(calc),
                    amount: money(calc.summary.totalTax)
                )
                Divider().overlay(palette.borderFaint)
                    .padding(.bottom, Space.s4)
                // Grand total
                HStack {
                    Text("GRAND TOTAL")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(money(calc.summary.grandTotal))
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.vertical, Space.s2)
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func ledgerRow(title: String, meta: String, amount: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            // Money glyph chip (dollar sign in a success-tinted square)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.success.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "dollarsign")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Brand.success)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta)
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s2)
            Text(amount)
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.vertical, Space.s3)
    }

    // MARK: - USMCA / T-MEC opportunity card

    private func opportunityCard(_ calc: DutyCalcResult) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("USMCA / T-MEC OPPORTUNITY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("saves \(money(usmcaSaves))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.success)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Certify origin (T-MEC) → duty drops to 0% on both lines.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                Text("MPF \(money(calc.summary.merchandiseProcessingFee)) still applies · FX USD 1.00 (static 2025-01-01).")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA row (Certify USMCA · Breakdown)

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            Button(action: {}) {
                Text("Certify USMCA")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .background(LinearGradient.primary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .buttonStyle(.plain)

            Button(action: {}) {
                Text("Breakdown")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 140, height: 48)
            }
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .buttonStyle(.plain)
        }
    }

    // MARK: - Formatting helpers

    private func trimRate(_ r: Double) -> String {
        if r == r.rounded() { return String(format: "%.1f", r) }
        return String(r)
    }

    private func federalTaxTitle(_ calc: DutyCalcResult) -> String {
        if calc.summary.totalTax == 0 { return "TAX · No federal tax · US import" }
        return "TAX · Federal"
    }

    private func taxNames(_ calc: DutyCalcResult) -> String {
        let names = Set(calc.lineItems.map { $0.taxName }.filter { $0 != "None" })
        return names.isEmpty ? "None" : names.sorted().joined(separator: ", ")
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        // Two deterministic runs: as-shipped (origin not certified → duty
        // owed today) and certified (→ usmcaSavings populated). The server
        // logs CROSS_BORDER_DUTY_CALCULATED on each. FX static per router.
        do {
            async let shipped: DutyCalcResult = EusoTripAPI.shared.query(
                "crossBorder.calculateDutiesAndTaxes",
                input: DutyCalcInput(origin: origin, destination: destination,
                                     commodities: commodities,
                                     usmcaCertified: false, currency: currency))
            async let cert: DutyCalcResult = EusoTripAPI.shared.query(
                "crossBorder.calculateDutiesAndTaxes",
                input: DutyCalcInput(origin: origin, destination: destination,
                                     commodities: commodities,
                                     usmcaCertified: true, currency: currency))
            let (s, c) = try await (shipped, cert)
            self.asShipped = s
            self.certified = c
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("596 · Rail Duty HTS Estimate · Night") { RailDutyHTSEstimateScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("596 · Rail Duty HTS Estimate · Light") { RailDutyHTSEstimateScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
