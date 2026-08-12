//
//  425_PortIntelligence.swift
//  EusoTrip
//
//  Evidence-backed cargo, facility, and route compatibility assessment.
//

import SwiftUI

struct PortIntelligenceScreen: View {
    let theme: Theme.Palette
    var product: String? = nil

    var body: some View {
        Shell(theme: theme) {
            PortIntelligenceBody(initialProduct: product)
        } nav: {
            shipperLifecycleNav()
        }
    }
}

private enum PortIntelMode: String, CaseIterable, Identifiable {
    case truck
    case rail
    case vessel
    case barge

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private enum PortIntelUnit: String, CaseIterable, Identifiable {
    case metricTons = "mt"
    case barrels = "bbl"
    case gallons = "gal"
    case kilograms = "kg"
    case pounds = "lb"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metricTons: "Metric tons"
        case .barrels: "Barrels"
        case .gallons: "Gallons"
        case .kilograms: "Kilograms"
        case .pounds: "Pounds"
        }
    }
}

private enum PortIntelPhysicalState: String, CaseIterable, Identifiable {
    case unspecified = ""
    case liquid
    case gas
    case solid

    var id: String { rawValue }
    var title: String { rawValue.isEmpty ? "Not specified" : rawValue.capitalized }
}

struct PortIntelAssessmentInput: Encodable {
    let requestKey: String
    let title: String
    let draft: Draft

    struct Draft: Encodable {
        let productName: String
        let category: String?
        let physicalState: String?
        let unNumber: String?
        let hazmatClass: String?
        let transportMode: String
        let quantity: Double
        let quantityUnit: String
        let origin: String
        let destination: String
        let originCountry: String
        let destinationCountry: String
        let equipment: String?
        let vesselClass: String?
        let multiVehicleCount: Int?
        let pickupDate: String?
        let specialPermit: String?
    }
}

struct PortIntelAssessment: Decodable {
    let publicId: String
    let engineVersion: String
    let preflight: Preflight
    let strategies: [Strategy]
    let evidence: [Evidence]

    struct Preflight: Decodable {
        let gate: String
        let counts: Counts
    }

    struct Counts: Decodable {
        let viable: Int
        let conditional: Int
        let insufficientEvidence: Int
        let blocked: Int

        enum CodingKeys: String, CodingKey {
            case viable
            case conditional
            case insufficientEvidence = "insufficient_evidence"
            case blocked
        }
    }

    struct DecisionReason: Decodable, Hashable {
        let code: String
        let message: String
        let subjectType: String
        let subjectId: Int?
        let evidenceId: Int?
    }

    struct Leg: Decodable, Hashable {
        let edgeId: Int
        let fromNodeId: Int
        let toNodeId: Int
        let mode: String
        let edgeType: String
        let parcelCount: Int?
        let status: String
        let hardFailures: [DecisionReason]
        let unknowns: [DecisionReason]
        let warnings: [DecisionReason]
        let evidenceIds: [Int]
    }

    struct Strategy: Decodable, Identifiable, Hashable {
        let id: Int
        let rank: Int
        let strategyType: String
        let status: String
        let destinationNodeId: Int
        let destinationName: String?
        let destinationCity: String?
        let destinationCountryCode: String?
        let destinationSubdivisionCode: String?
        let destinationLatitude: Double?
        let destinationLongitude: Double?
        let legs: [Leg]
        let hardFailures: [DecisionReason]
        let unknowns: [DecisionReason]
        let warnings: [DecisionReason]
        let confirmations: [DecisionReason]
        let knownCostAmount: Double?
        let knownCostCurrency: String?
        let missingCostElements: [String]
        let evidenceIds: [Int]
    }

    struct Evidence: Decodable, Identifiable, Hashable {
        let id: Int
        let sourceKey: String
        let sourceName: String
        let evidenceKind: String
        let sourceUrl: String?
        let verificationStatus: String
        let confidence: Double?
    }
}

private struct PortIntelligenceBody: View {
    @Environment(\.palette) private var palette

    @State private var product: String
    @State private var category = ""
    @State private var physicalState: PortIntelPhysicalState = .unspecified
    @State private var origin = ""
    @State private var originCountry = ""
    @State private var destination = ""
    @State private var destinationCountry = ""
    @State private var mode: PortIntelMode = .vessel
    @State private var quantity = ""
    @State private var unit: PortIntelUnit = .metricTons
    @State private var equipment = ""
    @State private var assessment: PortIntelAssessment?
    @State private var loading = false
    @State private var loadError: String?

    init(initialProduct: String?) {
        _product = State(initialValue: initialProduct?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: Space.s4) {
                header
                assessmentForm
                assessButton
                resultContent
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 10, weight: .heavy))
                Text("SHIPPER · PORT INTELLIGENCE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
            }
            .foregroundStyle(LinearGradient.diagonal)

            Text("Cargo route intelligence")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
        }
    }

    private var assessmentForm: some View {
        LifecycleCard {
            LifecycleSection(label: "CARGO", icon: "shippingbox")
            field("Product or grade", text: $product)

            HStack(spacing: 10) {
                field("Category", text: $category)
                menuField("State", value: physicalState.title) {
                    ForEach(PortIntelPhysicalState.allCases) { state in
                        Button(state.title) { physicalState = state }
                    }
                }
            }

            LifecycleSection(label: "MOVEMENT", icon: "arrow.triangle.swap")
            Picker("Mode", selection: $mode) {
                ForEach(PortIntelMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                field("Quantity", text: $quantity, keyboard: .decimalPad)
                menuField("Unit", value: unit.title) {
                    ForEach(PortIntelUnit.allCases) { item in
                        Button(item.title) { unit = item }
                    }
                }
            }

            field("Equipment or vessel class", text: $equipment)

            LifecycleSection(label: "ROUTE", icon: "map")
            routeRow(label: "Origin", location: $origin, country: $originCountry)
            routeRow(label: "Destination", location: $destination, country: $destinationCountry)
        }
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.textTertiary)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(palette.bgElev)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func menuField<MenuContent: View>(
        _ title: String,
        value: String,
        @ViewBuilder content: () -> MenuContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.textTertiary)
            Menu(content: content) {
                HStack {
                    Text(value)
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(palette.bgElev)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func routeRow(
        label: String,
        location: Binding<String>,
        country: Binding<String>
    ) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            field(label, text: location)
            VStack(alignment: .leading, spacing: 5) {
                Text("ISO")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                TextField("US", text: country)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(EType.bodyStrong)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 6)
                    .frame(width: 58, height: 40)
                    .background(palette.bgElev)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .onChange(of: country.wrappedValue) { _, value in
                        country.wrappedValue = String(value.uppercased().prefix(2))
                    }
            }
        }
    }

    private var assessButton: some View {
        Button {
            Task { await assess() }
        } label: {
            HStack(spacing: 7) {
                if loading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "sparkle.magnifyingglass")
                }
                Text(loading ? "Assessing" : "Assess route")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(0.4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .accessibilityLabel("Assess cargo route compatibility")
    }

    @ViewBuilder
    private var resultContent: some View {
        if let loadError {
            LifecycleCard(accentDanger: true) {
                LifecycleSection(label: "ASSESSMENT FAILED", icon: "exclamationmark.triangle")
                Text(loadError)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let assessment {
            gateCard(assessment)
            if assessment.strategies.isEmpty {
                LifecycleCard(accentWarning: true) {
                    LifecycleSection(label: "NO EVIDENCED STRATEGY", icon: "questionmark.diamond")
                    Text("No compatible destination strategy is present in the current evidence set.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            } else {
                LifecycleSection(label: "RANKED STRATEGIES", icon: "list.number")
                ForEach(assessment.strategies.prefix(25)) { strategy in
                    strategyCard(strategy)
                }
            }

            if !assessment.evidence.isEmpty {
                LifecycleSection(label: "EVIDENCE", icon: "checkmark.seal")
                ForEach(assessment.evidence.prefix(10)) { evidence in
                    evidenceRow(evidence)
                }
            }
        }
    }

    private func gateCard(_ assessment: PortIntelAssessment) -> some View {
        let gate = assessment.preflight.gate
        let icon = gate == "ready"
            ? "checkmark.seal.fill"
            : gate == "blocked"
                ? "xmark.octagon.fill"
                : "exclamationmark.triangle.fill"
        let color = gate == "ready"
            ? Brand.success
            : gate == "blocked"
                ? Brand.danger
                : Brand.warning

        return LifecycleCard(accentDanger: gate == "blocked", accentWarning: gate == "acknowledgement_required") {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 5) {
                    Text(gate.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(assessment.preflight.counts.viable) viable · \(assessment.preflight.counts.conditional) conditional · \(assessment.preflight.counts.insufficientEvidence) unresolved · \(assessment.preflight.counts.blocked) blocked")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Text("Engine \(assessment.engineVersion) · \(assessment.evidence.count) evidence records")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private func strategyCard(_ strategy: PortIntelAssessment.Strategy) -> some View {
        LifecycleCard(accentDanger: strategy.status == "blocked", accentWarning: strategy.status == "conditional" || strategy.status == "insufficient_evidence") {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(strategy.destinationName ?? "Facility \(strategy.destinationNodeId)")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(strategyLocation(strategy))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                statusBadge(strategy.status)
            }

            LifecycleRow(
                label: "Strategy",
                value: strategy.strategyType.replacingOccurrences(of: "_", with: " ").capitalized
            )
            LifecycleRow(label: "Modes", value: strategyModes(strategy))
            if let amount = strategy.knownCostAmount, let currency = strategy.knownCostCurrency {
                LifecycleRow(label: "Known cost", value: "\(currency) \(amount.formatted(.number.precision(.fractionLength(2))))")
            }
            if let reason = primaryReason(strategy) {
                LifecycleRow(label: reason.0, value: reason.1)
            }
            LifecycleRow(label: "Evidence", value: "\(strategy.evidenceIds.count) records")
        }
    }

    private func evidenceRow(_ evidence: PortIntelAssessment.Evidence) -> some View {
        LifecycleCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: evidence.verificationStatus == "verified" ? "checkmark.seal.fill" : "doc.text.magnifyingglass")
                    .foregroundStyle(evidence.verificationStatus == "verified" ? Brand.success : Brand.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(evidence.sourceName)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(evidence.evidenceKind.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    if let confidence = evidence.confidence {
                        Text("Confidence \(Int((confidence * 100).rounded()))%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
                Text(evidence.verificationStatus.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let color = status == "viable"
            ? Brand.success
            : status == "blocked"
                ? Brand.danger
                : Brand.warning
        return Text(status.replacingOccurrences(of: "_", with: " ").uppercased())
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .overlay {
                Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1)
            }
    }

    private func strategyLocation(_ strategy: PortIntelAssessment.Strategy) -> String {
        let values = [
            strategy.destinationCity,
            strategy.destinationSubdivisionCode,
            strategy.destinationCountryCode,
        ].compactMap { $0 }.filter { !$0.isEmpty }
        return values.isEmpty ? "Location not evidenced" : values.joined(separator: ", ")
    }

    private func strategyModes(_ strategy: PortIntelAssessment.Strategy) -> String {
        let values = strategy.legs.map(\.mode)
        return values.isEmpty ? "Facility match" : values.joined(separator: " → ")
    }

    private func primaryReason(_ strategy: PortIntelAssessment.Strategy) -> (String, String)? {
        if let reason = strategy.hardFailures.first { return ("Blocker", reason.message) }
        if let reason = strategy.unknowns.first { return ("Unknown", reason.message) }
        if let reason = strategy.warnings.first { return ("Warning", reason.message) }
        if let reason = strategy.confirmations.first { return ("Confirmed", reason.message) }
        return nil
    }

    @MainActor
    private func assess() async {
        loadError = nil
        assessment = nil

        let normalizedProduct = product.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOriginCountry = originCountry.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedDestinationCountry = destinationCountry.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let parsedQuantity = Double(quantity.replacingOccurrences(of: ",", with: ""))

        guard !normalizedProduct.isEmpty else {
            loadError = "Product or grade is required."
            return
        }
        guard normalizedOrigin.count >= 2, normalizedDestination.count >= 2 else {
            loadError = "Origin and destination are required."
            return
        }
        guard normalizedOriginCountry.count == 2, normalizedDestinationCountry.count == 2 else {
            loadError = "Origin and destination require two-letter country codes."
            return
        }
        if mode == .truck || mode == .rail {
            let supported = Set(["US", "CA", "MX"])
            guard supported.contains(normalizedOriginCountry), supported.contains(normalizedDestinationCountry) else {
                loadError = "Truck and rail assessments are limited to the United States, Canada, and Mexico."
                return
            }
        }
        guard let parsedQuantity, parsedQuantity > 0 else {
            loadError = "A positive quantity is required."
            return
        }

        loading = true
        defer { loading = false }

        let request = PortIntelAssessmentInput(
            requestKey: UUID().uuidString,
            title: "\(normalizedProduct) · \(normalizedOrigin) to \(normalizedDestination)",
            draft: .init(
                productName: normalizedProduct,
                category: category.nilIfBlank,
                physicalState: physicalState.rawValue.nilIfBlank,
                unNumber: nil,
                hazmatClass: nil,
                transportMode: mode.rawValue,
                quantity: parsedQuantity,
                quantityUnit: unit.rawValue,
                origin: normalizedOrigin,
                destination: normalizedDestination,
                originCountry: normalizedOriginCountry,
                destinationCountry: normalizedDestinationCountry,
                equipment: equipment.nilIfBlank,
                vesselClass: nil,
                multiVehicleCount: nil,
                pickupDate: nil,
                specialPermit: nil
            )
        )

        do {
            let result: PortIntelAssessment = try await EusoTripAPI.shared.mutation(
                "portIntelligence.assessLoadDraft",
                input: request
            )
            assessment = result
        } catch {
            loadError = assessmentFailureCopy_425(error)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

#Preview("425 · Port intelligence") {
    PortIntelligenceScreen(theme: Theme.dark, product: "LPG 30/70 C3/C4")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

// MARK: - Operator-facing failure copy

/// Operator-language reason a cargo route-compatibility assessment failed.
///
/// The caught error is still available for logging; the shipper sees a
/// sentence they can act on rather than a raw `NSError` description. No
/// branch implies the route cleared — a failed assessment is never a pass.
fileprivate func assessmentFailureCopy_425(_ error: Error) -> String {
    if let api = error as? EusoTripAPIError {
        switch api {
        case .unauthenticated:
            return "Your session expired, so nothing was assessed. Sign in again and rerun the assessment."
        case .forbidden(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "This account isn't cleared to assess this lane. Nothing was assessed."
                : trimmed
        case .trpcError(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "The assessment was rejected. Check the product, lane, and quantity, then rerun it."
                : trimmed
        case .httpStatus(let code, _):
            return "The assessment didn't complete (code \(code)). Nothing was assessed — rerun it in a moment."
        case .decodingFailed:
            return "The assessment came back in a form this build can't read, so none of it is verified. Update the app, then rerun it."
        case .empty:
            return "No assessment came back for this lane. Rerun it in a moment."
        case .notConfigured, .badURL:
            return "This device isn't set up for live port assessments yet. Restart the app and rerun it."
        case .queuedForOfflineReplay:
            return "You're offline, so nothing was assessed. Rerun this once you reconnect."
        }
    }
    if (error as NSError).domain == NSURLErrorDomain {
        return "No connection, so nothing was assessed. Rerun this once you're back online."
    }
    return "The assessment didn't complete. Nothing was assessed — rerun it in a moment."
}
