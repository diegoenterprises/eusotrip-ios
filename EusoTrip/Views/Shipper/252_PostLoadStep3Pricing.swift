//
//  252_PostLoadStep3Pricing.swift
//  EusoTrip — Shipper · Post-a-Load · Step 3 PRICING.
//

import SwiftUI

/// Editable commercial terms for the post/bid flow. Every field begins
/// unknown; this type never supplies a market rate, grace period, currency,
/// billing increment, rounding rule, or suspension policy on the user's behalf.
struct TruckDetentionTermsDraft: Codable, Equatable, Sendable {
    var currency: TruckDetentionNegotiatedTerms.Currency?
    var freeTimeMinutes = ""
    var rateAmount = ""
    var billingIncrementMinutes = ""
    var roundingRule: TruckDetentionNegotiatedTerms.RoundingRule?
    var suspensionRule: TruckDetentionNegotiatedTerms.SuspensionRule?
    var excludedSharePercent = ""

    init() {}

    init(terms: TruckDetentionNegotiatedTerms) {
        currency = terms.currency
        freeTimeMinutes = String(terms.freeTimeMinutes)
        rateAmount = terms.rateAmount
        billingIncrementMinutes = String(terms.billingIncrementMinutes)
        roundingRule = terms.roundingRule
        suspensionRule = terms.suspensionRule
        if let basisPoints = terms.excludedShareBasisPoints {
            excludedSharePercent = Self.percentString(from: basisPoints)
        }
    }

    var negotiatedTerms: TruckDetentionNegotiatedTerms? {
        guard let currency,
              let freeTime = Int(freeTimeMinutes.trimmingCharacters(in: .whitespacesAndNewlines)),
              let increment = Int(billingIncrementMinutes.trimmingCharacters(in: .whitespacesAndNewlines)),
              let roundingRule,
              let suspensionRule else { return nil }

        let share: Int?
        if suspensionRule == .sharedPercentage {
            guard let parsed = Self.basisPoints(from: excludedSharePercent) else { return nil }
            share = parsed
        } else {
            share = nil
        }

        let terms = TruckDetentionNegotiatedTerms(
            currency: currency,
            freeTimeMinutes: freeTime,
            rateAmount: rateAmount.trimmingCharacters(in: .whitespacesAndNewlines),
            billingIncrementMinutes: increment,
            roundingRule: roundingRule,
            suspensionRule: suspensionRule,
            excludedShareBasisPoints: share
        )
        return terms.validationMessage == nil ? terms : nil
    }

    var validationMessage: String? {
        guard currency != nil else { return "Choose the settlement currency." }
        guard !freeTimeMinutes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter the negotiated free-time minutes."
        }
        guard !rateAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter the negotiated detention rate per hour."
        }
        guard !billingIncrementMinutes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter the billing increment in minutes."
        }
        guard roundingRule != nil else { return "Choose the negotiated rounding rule." }
        guard let suspensionRule else { return "Choose how confirmed suspensions are allocated." }
        if suspensionRule == .sharedPercentage,
           excludedSharePercent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter the excluded suspension share percentage."
        }
        if let terms = unvalidatedTerms, let message = terms.validationMessage { return message }
        return negotiatedTerms == nil ? "Review the detention terms for invalid values." : nil
    }

    private var unvalidatedTerms: TruckDetentionNegotiatedTerms? {
        guard let currency,
              let freeTime = Int(freeTimeMinutes.trimmingCharacters(in: .whitespacesAndNewlines)),
              let increment = Int(billingIncrementMinutes.trimmingCharacters(in: .whitespacesAndNewlines)),
              let roundingRule,
              let suspensionRule else { return nil }
        let share = suspensionRule == .sharedPercentage
            ? Self.basisPoints(from: excludedSharePercent)
            : nil
        return TruckDetentionNegotiatedTerms(
            currency: currency,
            freeTimeMinutes: freeTime,
            rateAmount: rateAmount.trimmingCharacters(in: .whitespacesAndNewlines),
            billingIncrementMinutes: increment,
            roundingRule: roundingRule,
            suspensionRule: suspensionRule,
            excludedShareBasisPoints: share
        )
    }

    private static func basisPoints(from percent: String) -> Int? {
        let normalized = percent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: #"^(?:0|[1-9]\d?)(?:\.\d{1,2})?$|^100(?:\.0{1,2})?$"#,
                               options: .regularExpression) != nil,
              let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        let basisPoints = NSDecimalNumber(decimal: value * 100).intValue
        return (1...9_999).contains(basisPoints) ? basisPoints : nil
    }

    private static func percentString(from basisPoints: Int) -> String {
        let whole = basisPoints / 100
        let fraction = basisPoints % 100
        return fraction == 0 ? String(whole) : String(format: "%d.%02d", whole, fraction)
    }
}

extension TruckDetentionNegotiatedTerms {
    var freeTimeDisplay: String { "\(freeTimeMinutes) min" }
    var rateDisplay: String { "\(currency.rawValue) \(rateAmount) / hour" }
    var billingDisplay: String {
        roundingRule == .exact
            ? "Exact elapsed time"
            : "\(billingIncrementMinutes)-minute increments · \(roundingRule.displayName)"
    }
    var suspensionDisplay: String {
        switch suspensionRule {
        case .included: return "Confirmed suspension remains billable"
        case .excluded: return "Confirmed suspension is excluded"
        case .eventAdjudicated: return "Excluded time is adjudicated per event"
        case .sharedPercentage:
            guard let basisPoints = excludedShareBasisPoints else { return "Shared percentage unavailable" }
            return "\(TruckDetentionTermsDraft.percentDisplay(basisPoints)) excluded"
        }
    }
}

extension TruckDetentionNegotiatedTerms.RoundingRule {
    var displayName: String {
        switch self {
        case .ceiling: return "Round up"
        case .floor: return "Round down"
        case .nearest: return "Nearest increment"
        case .exact: return "Exact"
        }
    }
}

extension TruckDetentionNegotiatedTerms.SuspensionRule {
    var displayName: String {
        switch self {
        case .included: return "Included"
        case .excluded: return "Excluded"
        case .sharedPercentage: return "Shared percentage"
        case .eventAdjudicated: return "Event adjudicated"
        }
    }
}

extension TruckDetentionTermsDraft {
    fileprivate static func percentDisplay(_ basisPoints: Int) -> String {
        let value = Double(basisPoints) / 100
        return value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 2))) + "%"
    }
}

struct TruckDetentionTermsSummary: View {
    @Environment(\.palette) private var palette
    let terms: TruckDetentionNegotiatedTerms
    var context: String = "SIGNED LOAD TERMS"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context)
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.textTertiary)
            summaryRow("Free time", terms.freeTimeDisplay)
            summaryRow("Rate", terms.rateDisplay)
            summaryRow("Billing", terms.billingDisplay)
            summaryRow("Suspension", terms.suspensionDisplay)
        }
        .accessibilityElement(children: .combine)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(palette.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(palette.textPrimary)
        }
        .font(.subheadline)
    }
}

struct TruckDetentionTermsEditor: View {
    @Environment(\.palette) private var palette
    @Binding var draft: TruckDetentionTermsDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            labeled("Settlement currency") {
                HStack(spacing: 8) {
                    ForEach(TruckDetentionNegotiatedTerms.Currency.allCases) { currency in
                        selectionButton(currency.rawValue, selected: draft.currency == currency) {
                            draft.currency = currency
                        }
                    }
                }
            }
            labeled("Free time (minutes)") {
                numericField("Negotiated minutes", text: $draft.freeTimeMinutes, decimal: false)
            }
            labeled("Rate per hour") {
                numericField("Negotiated amount", text: $draft.rateAmount, decimal: true)
            }
            labeled("Billing increment (minutes)") {
                numericField("Increment minutes", text: $draft.billingIncrementMinutes, decimal: false)
            }
            termsMenu(
                label: "Rounding",
                selection: draft.roundingRule?.displayName ?? "Choose rule"
            ) {
                ForEach(TruckDetentionNegotiatedTerms.RoundingRule.allCases) { rule in
                    Button(rule.displayName) { draft.roundingRule = rule }
                }
            }
            termsMenu(
                label: "Confirmed suspension",
                selection: draft.suspensionRule?.displayName ?? "Choose allocation"
            ) {
                ForEach(TruckDetentionNegotiatedTerms.SuspensionRule.allCases) { rule in
                    Button(rule.displayName) { draft.suspensionRule = rule }
                }
            }
            if draft.suspensionRule == .sharedPercentage {
                labeled("Excluded share (%)") {
                    numericField("0.01 to 99.99", text: $draft.excludedSharePercent, decimal: true)
                }
            }
            if let message = draft.validationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Detention terms incomplete. \(message)")
            }
        }
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(palette.textSecondary)
            content()
        }
    }

    private func numericField(_ prompt: String, text: Binding<String>, decimal: Bool) -> some View {
        TextField(prompt, text: text)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .textFieldStyle(.plain)
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .background(palette.bgCard.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.borderFaint))
    }

    private func selectionButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? Color.white : palette.textPrimary)
                .background(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func termsMenu<Content: View>(
        label: String,
        selection: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu(content: content) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.caption).foregroundStyle(palette.textSecondary)
                    Text(selection).font(.subheadline.weight(.semibold)).foregroundStyle(palette.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(palette.textSecondary)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .background(palette.bgCard.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.borderFaint))
        }
    }
}

struct PostLoadStep3PricingScreen: View {
    let theme: Theme.Palette
    @ObservedObject var draft: PostLoadDraft
    var body: some View {
        Shell(theme: theme) { PostLoadStep3Body(draft: draft) } nav: { shipperLifecycleNav() }
    }
}

private struct PostLoadStep3Body: View {
    @Environment(\.palette) private var palette
    @ObservedObject var draft: PostLoadDraft

    private let accessorialOptions = ["detention", "lumper", "layover", "TONU", "stop_charge", "wait_time"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                rateSheetCard      // T-008 · 2026-05-20
                rateCard
                if draft.mode == .truck { detentionTermsCard }
                fuelCard
                accessorialsCard
                notesCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
        }
    }

    // ── T-008 (canonical fee engine, 2026-05-20) ────────────────────
    // Renders the canonical FeeMultiplierEngine breakdown above the
    // rate field so the shipper sees BASE × COUNTRY × VERTICAL × PRODUCT
    // × HAZMAT × DISTANCE × CYCLE before they commit a number. Reads
    // `draft.feeBreakdown` which clamps unknown countries to US and
    // computes great-circle distance from the lane coordinates. When
    // trailer + vertical aren't both ready the card shows an empty
    // state pointing back to Step 2.
    private var rateSheetCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ESANG · CANONICAL RATE SHEET", icon: "sparkles")
            if let breakdown = draft.feeBreakdown {
                // Effective fee header line
                let effPct = decimalToPct(breakdown.effective - 1)
                let baseRateUsd = draft.rate ?? 0
                let feeAmount = baseRateUsd * (NSDecimalNumber(decimal: breakdown.effective).doubleValue - 1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("EusoTrip platform fee")
                        .font(.system(size: 12, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Text(effPct)
                        .font(.system(size: 16, weight: .heavy, design: .monospaced))
                        .foregroundStyle(LinearGradient.diagonal)
                    if baseRateUsd > 0 {
                        Text(String(format: "≈ $%.2f", feeAmount))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                // Multiplier chips — one per dimension. Color-coded:
                // gradient = > 1.0 surcharge · neutral = exactly 1.0
                // (no impact) · green = < 1.0 discount.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        multiplierChip(label: "BASE",     value: breakdown.base)
                        multiplierChip(label: "COUNTRY",  value: breakdown.country)
                        multiplierChip(label: "VERTICAL", value: breakdown.vertical)
                        multiplierChip(label: "PRODUCT",  value: breakdown.product)
                        multiplierChip(label: "HAZMAT",   value: breakdown.hazmat)
                        multiplierChip(label: "DISTANCE", value: breakdown.distance)
                        multiplierChip(label: "CYCLE",    value: breakdown.cycleDampener)
                    }
                }
                // Live lane summary so the user sees what the engine
                // resolved (helps debug "why is the fee so high?").
                Text(laneSummary(breakdown: breakdown))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Empty state — trailer or vertical not set yet.
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                    Text("Pick a trailer + vertical on Step 2 to see the canonical fee breakdown.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func multiplierChip(label: String, value: Decimal) -> some View {
        let n = NSDecimalNumber(decimal: value).doubleValue
        let isSurcharge = n > 1.0001
        let isDiscount  = n < 0.9999
        let bg: AnyShapeStyle = {
            if isSurcharge { return AnyShapeStyle(LinearGradient.diagonal) }
            if isDiscount  { return AnyShapeStyle(Brand.success.opacity(0.85)) }
            return AnyShapeStyle(palette.tintNeutral)
        }()
        let fg: Color = isSurcharge || isDiscount ? .white : palette.textPrimary
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(fg.opacity(0.85))
            Text(decimalToPct(value - 1))
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(fg)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func decimalToPct(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d).doubleValue
        if abs(n) < 0.0001 { return "0%" }
        let sign = n >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", n * 100))%"
    }

    private func laneSummary(breakdown: FeeBreakdown) -> String {
        let i = breakdown.inputs
        var parts: [String] = []
        parts.append("\(i.originCountry.rawValue)→\(i.destinationCountry.rawValue)")
        parts.append(i.mode.rawValue.uppercased())
        parts.append(i.vertical.displayName)
        parts.append(i.trailer.displayName)
        if i.isHazmat { parts.append("HAZMAT") }
        let miles = NSDecimalNumber(decimal: i.distanceMiles).doubleValue
        if miles > 0 { parts.append("\(Int(miles)) mi") }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("POST A LOAD · STEP 3 · PRICING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text("Set the rate.")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.75)
        }
    }

    private var rateCard: some View {
        LifecycleCard {
            LifecycleSection(label: targetRateLabel, icon: "tag")
            TextField("e.g. 1900", value: $draft.rate, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var targetRateLabel: String {
        guard draft.mode == .truck else { return "TARGET RATE" }
        return "TARGET RATE (\(draft.truckDetentionTermsDraft.currency?.rawValue ?? "CURRENCY NOT SET"))"
    }

    private var detentionTermsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "TRUCK DETENTION TERMS", icon: "clock.badge.checkmark")
            Text("These commercial terms are signed with the load and inherited by bids unless a counterparty explicitly proposes an override.")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TruckDetentionTermsEditor(draft: $draft.truckDetentionTermsDraft)
        }
    }

    private var fuelCard: some View {
        LifecycleCard {
            LifecycleSection(label: "FUEL SURCHARGE %", icon: "fuelpump")
            TextField("e.g. 18.5", value: $draft.fuelSurchargeRate, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var accessorialsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ACCESSORIALS ALLOWED", icon: "checklist")
            FlowList(items: accessorialOptions, selected: draft.accessorialsAllowed) { item in
                if let i = draft.accessorialsAllowed.firstIndex(of: item) {
                    draft.accessorialsAllowed.remove(at: i)
                } else {
                    draft.accessorialsAllowed.append(item)
                }
            }
        }
    }

    private var notesCard: some View {
        LifecycleCard {
            LifecycleSection(label: "NOTES TO CARRIER", icon: "text.alignleft")
            TextField("Special instructions, gate codes, etc.", text: $draft.notes, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "251"])
            } label: {
                Text("Back").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(palette.tintNeutral).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "253"])
            } label: {
                Text("Review").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
                .disabled(draft.mode == .truck && draft.truckDetentionTermsDraft.negotiatedTerms == nil)
                .opacity(draft.mode == .truck && draft.truckDetentionTermsDraft.negotiatedTerms == nil ? 0.55 : 1)
        }
    }
}

private struct FlowList: View {
    @Environment(\.palette) private var palette
    let items: [String]
    let selected: [String]
    let onTap: (String) -> Void
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 96), spacing: 8)]
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button { onTap(item) } label: {
                    Text(item.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(on ? .white : palette.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }
}

#Preview("252 · Pricing · Night") {
    PostLoadStep3PricingScreen(theme: Theme.dark, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("252 · Pricing · Afternoon") {
    PostLoadStep3PricingScreen(theme: Theme.light, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
