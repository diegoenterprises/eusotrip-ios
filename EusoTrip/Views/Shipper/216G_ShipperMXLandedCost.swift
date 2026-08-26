//
//  216G_ShipperMXLandedCost.swift
//  EusoTrip 2027 - Shipper Mexico landed cost.
//
//  Calculates a transparent Mexico import estimate from user-entered customs
//  and logistics inputs plus a live/cached exchange rate and server tax engine.
//

import SwiftUI

private struct LandedLocation216G: Decodable {
    let city: String?
    let state: String?
}

private struct LandedLoad216G: Decodable {
    let id: String
    let loadNumber: String
    let status: String
    let cargoType: String?
    let dangerousGoodsStatus: String?
    let commodity: String?
    let commodityName: String?
    let originCountry: String?
    let destCountry: String?
    let pickupLocation: LandedLocation216G?
    let deliveryLocation: LandedLocation216G?

    var lane: String {
        "\(location(pickupLocation)) -> \(location(deliveryLocation))"
    }

    private func location(_ value: LandedLocation216G?) -> String {
        let parts = [value?.city, value?.state]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Location not recorded" : parts.joined(separator: ", ")
    }
}

private struct LandedRequirement216G: Decodable, Identifiable {
    var id: String { "\(category)-\(requirement)" }
    let category: String
    let requirement: String
    let status: String
    let critical: Bool
}

private struct LandedCompliance216G: Decodable {
    let route: String
    let shipmentType: String
    let checklist: [LandedRequirement216G]
}

private struct ExchangeRates216G: Decodable {
    struct Rates: Decodable {
        let USD: Double?
        let CAD: Double?
        let MXN: Double?
    }

    let base: String
    let rates: Rates
    let updatedAt: String?
    let source: String

    var isTrustedForDisplay: Bool {
        source == "live" || source == "cached"
    }
}

private struct PedimentoTaxes216G: Decodable {
    let arancelImporte: Double
    let iva: Double
    let dta: Double
    let cuotaCompensatoria: Double
    let prevalidacion: Double
    let total: Double
}

private struct LandedCostDraft216G {
    var pedimentoType = "A1"
    var customsValueUSD = ""
    var tariffPercent = "0"
    var compensatoryPercent = ""
    var internationalFreightUSD = ""
    var insuranceUSD = ""
    var brokerFeeMXN = ""
    var handlingMXN = ""
    var domesticTransportMXN = ""
    var otherCostsMXN = ""
}

private struct LandedCostEstimate216G {
    let taxes: PedimentoTaxes216G
    let customsValueUSD: Double
    let customsValueMXN: Double
    let logisticsAndOtherMXN: Double
    let exchangeRate: Double
    let rateSource: String
    let totalMXN: Double
}

@MainActor
private final class LandedCostStore216G: ObservableObject {
    @Published private(set) var load: LandedLoad216G?
    @Published private(set) var compliance: LandedCompliance216G?
    @Published private(set) var exchangeRates: ExchangeRates216G?
    @Published private(set) var estimate: LandedCostEstimate216G?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isCalculating = false

    let loadId: String
    private let api: EusoTripAPI

    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    func refresh() async {
        guard !loadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            load = nil
            compliance = nil
            exchangeRates = nil
            estimate = nil
            errorMessage = "Open Landed Cost from a cross-border load to inspect its calculation inputs."
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        estimate = nil

        do {
            struct LoadInput: Encodable { let id: String }
            let result: LandedLoad216G? = try await api.query(
                "loads.getById",
                input: LoadInput(id: loadId)
            )
            guard let resolved = result else {
                load = nil
                compliance = nil
                exchangeRates = nil
                estimate = nil
                errorMessage = "This load is no longer available. Return to Loads and choose another one."
                return
            }
            load = resolved

            var failures: [String] = []
            if let countries = supportedCountries(resolved) {
                struct ComplianceInput: Encodable {
                    let origin: String
                    let destination: String
                    let shipmentType: String
                }
                do {
                    compliance = try await api.query(
                        "crossBorderShipping.getCrossBorderCompliance",
                        input: ComplianceInput(
                            origin: countries.origin,
                            destination: countries.destination,
                            shipmentType: shipmentType(resolved)
                        )
                    )
                } catch {
                    compliance = nil
                    failures.append(error.eusoUserCopy)
                }
            } else {
                compliance = nil
            }

            struct ExchangeInput: Encodable { let base: String }
            do {
                exchangeRates = try await api.query(
                    "crossBorderShipping.getExchangeRates",
                    input: ExchangeInput(base: "USD")
                )
            } catch {
                exchangeRates = nil
                failures.append(error.eusoUserCopy)
            }

            errorMessage = failures.isEmpty ? nil : failures.joined(separator: " ")
        } catch {
            load = nil
            compliance = nil
            exchangeRates = nil
            estimate = nil
            errorMessage = error.eusoUserCopy
        }
    }

    func calculate(_ draft: LandedCostDraft216G) async -> Bool {
        guard load?.destCountry?.uppercased() == "MX" else {
            errorMessage = "Mexico landed-cost calculation requires a recorded Mexico destination."
            return false
        }
        guard let rates = exchangeRates,
              rates.isTrustedForDisplay,
              rates.base == "USD",
              let mxnPerUSD = rates.rates.MXN,
              mxnPerUSD > 0 else {
            errorMessage = "A live or cached USD/MXN rate is required before calculating landed cost."
            return false
        }
        guard let customsValue = positive(draft.customsValueUSD),
              let tariffPercent = percentage(draft.tariffPercent) else {
            errorMessage = "Enter a positive customs value and an ad-valorem tariff from 0–100%."
            return false
        }
        let compensatoryRate: Double?
        if draft.compensatoryPercent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            compensatoryRate = nil
        } else if let value = percentage(draft.compensatoryPercent) {
            compensatoryRate = value / 100
        } else {
            errorMessage = "Compensatory quota must be empty or a percentage from 0–100."
            return false
        }

        guard let freightUSD = nonnegative(draft.internationalFreightUSD),
              let insuranceUSD = nonnegative(draft.insuranceUSD),
              let brokerMXN = nonnegative(draft.brokerFeeMXN),
              let handlingMXN = nonnegative(draft.handlingMXN),
              let domesticMXN = nonnegative(draft.domesticTransportMXN),
              let otherMXN = nonnegative(draft.otherCostsMXN) else {
            errorMessage = "Optional cost fields must be empty or nonnegative numbers."
            return false
        }

        struct Merchandise: Encodable {
            let valorAduana: Double
            let arancelAdValorem: Double
            let cuotaCompensatoria: Double?
        }
        struct Input: Encodable {
            let mercancias: [Merchandise]
            let tipoCambio: Double
            let tipo: String
        }

        isCalculating = true
        defer { isCalculating = false }
        errorMessage = nil
        do {
            let taxes: PedimentoTaxes216G = try await api.query(
                "crossBorderShipping.calculatePedimentoTaxes",
                input: Input(
                    mercancias: [Merchandise(
                        valorAduana: customsValue,
                        arancelAdValorem: tariffPercent / 100,
                        cuotaCompensatoria: compensatoryRate
                    )],
                    tipoCambio: mxnPerUSD,
                    tipo: draft.pedimentoType
                )
            )
            let customsValueMXN = customsValue * mxnPerUSD
            let outsideCustomsValue = ((freightUSD + insuranceUSD) * mxnPerUSD)
                + brokerMXN + handlingMXN + domesticMXN + otherMXN
            estimate = LandedCostEstimate216G(
                taxes: taxes,
                customsValueUSD: customsValue,
                customsValueMXN: customsValueMXN,
                logisticsAndOtherMXN: outsideCustomsValue,
                exchangeRate: mxnPerUSD,
                rateSource: rates.source,
                totalMXN: customsValueMXN + outsideCustomsValue + taxes.total
            )
            return true
        } catch {
            estimate = nil
            errorMessage = error.eusoUserCopy
            return false
        }
    }

    private func supportedCountries(_ load: LandedLoad216G) -> (origin: String, destination: String)? {
        guard let origin = load.originCountry?.uppercased(),
              let destination = load.destCountry?.uppercased(),
              ["US", "CA", "MX"].contains(origin),
              ["US", "CA", "MX"].contains(destination) else { return nil }
        return (origin, destination)
    }

    private func shipmentType(_ load: LandedLoad216G) -> String {
        if load.dangerousGoodsStatus == "dangerous_goods" || load.cargoType == "hazmat" { return "hazmat" }
        switch load.cargoType {
        case "refrigerated", "food_grade": return "perishable"
        case "oversized": return "oversize"
        case "livestock": return "livestock"
        default: return "general"
        }
    }

    private func positive(_ text: String) -> Double? {
        guard let value = Double(text), value > 0 else { return nil }
        return value
    }

    private func nonnegative(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        guard let value = Double(trimmed), value >= 0 else { return nil }
        return value
    }

    private func percentage(_ text: String) -> Double? {
        guard let value = Double(text), value >= 0, value <= 100 else { return nil }
        return value
    }
}

struct ShipperMXLandedCost: View {
    let loadId: String
    @StateObject private var store: LandedCostStore216G
    @State private var showingCalculator = false
    @State private var calculatorDraft = LandedCostDraft216G()
    @Environment(\.palette) private var palette

    init(loadId: String = "") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: LandedCostStore216G(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(
                    eyebrow: "SHIPPER · LANDED COST · MX IMPORT",
                    idText: store.load?.loadNumber ?? loadId,
                    title: "Landed cost"
                )

                if let errorMessage = store.errorMessage {
                    DegradedNote(text: errorMessage)
                        .padding(.top, Space.s3)
                }

                if store.isLoading, store.load == nil {
                    ProgressView("Loading landed-cost inputs")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s6)
                }

                if let load = store.load {
                    loadCard(load)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)

                    SectionLabel("EXCHANGE RATE")
                        .padding(.top, Space.s5)
                    exchangeRateCard
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    SectionLabel("LANDED-COST ESTIMATE")
                        .padding(.top, Space.s5)
                    calculationCard
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    if let compliance = store.compliance {
                        SectionLabel("CROSS-BORDER REQUIREMENTS · \(compliance.route)")
                            .padding(.top, Space.s5)
                        requirementList(compliance.checklist)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)
                    } else {
                        unsupportedRoute(load)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s4)
                    }
                }

                if store.errorMessage != nil, !loadId.isEmpty {
                    CTAButton(
                        title: "Retry",
                        action: { Task { await store.refresh() } },
                        isLoading: store.isLoading
                    )
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)
                }

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .eusoRefreshable { await store.refresh() }
        .sheet(isPresented: $showingCalculator) {
            LandedCostCalculatorSheet216G(draft: $calculatorDraft) { draft in
                await store.calculate(draft)
            }
        }
    }

    private func loadCard(_ load: LandedLoad216G) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                AddendaIconChip(systemImage: "shippingbox.fill", tint: Brand.info)
                VStack(alignment: .leading, spacing: 4) {
                    Text(load.commodityName ?? load.commodity ?? "Cargo not recorded")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text(load.lane)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                AddendaChip(
                    text: load.status.replacingOccurrences(of: "_", with: " ").uppercased(),
                    color: Brand.info
                )
            }
            Divider().overlay(palette.borderFaint)
            factRow("COUNTRIES", countryLane(load))
            factRow("CARGO", (load.cargoType ?? "Not recorded").replacingOccurrences(of: "_", with: " ").uppercased())
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private var exchangeRateCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            AddendaIconChip(systemImage: "arrow.left.arrow.right", tint: fxAvailable ? Brand.success : Brand.warning)
            VStack(alignment: .leading, spacing: 5) {
                if let rates = store.exchangeRates,
                   rates.isTrustedForDisplay,
                   let mxn = rates.rates.MXN {
                    Text("1 \(rates.base) = \(String(format: "%.4f", mxn)) MXN")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text("\(rates.source.uppercased()) source\(updatedSuffix(rates.updatedAt))")
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                } else {
                    Text("Live exchange rate unavailable")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text("Fallback rates are intentionally not shown as a current financial quote.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private var calculationCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let estimate = store.estimate {
                HStack(alignment: .top, spacing: Space.s3) {
                    AddendaIconChip(systemImage: "sum", tint: Brand.success)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(moneyMXN(estimate.totalMXN))
                            .font(EType.display)
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                        Text("ESTIMATED LANDED TOTAL · MXN")
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                Divider().overlay(palette.borderFaint)
                factRow("CUSTOMS VALUE", moneyUSD(estimate.customsValueUSD))
                factRow("CUSTOMS VALUE · MXN", moneyMXN(estimate.customsValueMXN))
                factRow("DUTY", moneyMXN(estimate.taxes.arancelImporte))
                factRow("IVA", moneyMXN(estimate.taxes.iva))
                factRow("DTA", moneyMXN(estimate.taxes.dta))
                factRow("COMPENSATORY", moneyMXN(estimate.taxes.cuotaCompensatoria))
                factRow("PREVALIDATION", moneyMXN(estimate.taxes.prevalidacion))
                factRow("LOGISTICS + OTHER", moneyMXN(estimate.logisticsAndOtherMXN))
                factRow("FX BASIS", "1 USD = \(String(format: "%.4f", estimate.exchangeRate)) MXN · \(estimate.rateSource.uppercased())")
                Text("Estimate only. It uses the entered customs value and costs; it is not a customs ruling, broker approval, VUCEM filing, payment, or persisted quote.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: Space.s3) {
                    Image(systemName: "sum")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(fxAvailable ? Brand.info : Brand.warning)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(fxAvailable ? "Enter the actual customs and logistics inputs" : "Waiting for a trusted exchange rate")
                            .font(EType.title)
                            .foregroundStyle(palette.textPrimary)
                        Text("The load's freight rate is never substituted for customs value. EusoTrip calculates the declared value, tariffs, Pedimento type, and trusted USD/MXN rate, then adds only the costs you enter.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            Button {
                showingCalculator = true
            } label: {
                Label(store.estimate == nil ? "Calculate landed cost" : "Recalculate", systemImage: "function")
                    .font(EType.title)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(LinearGradient.primary)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canCalculate || store.isCalculating)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private func requirementList(_ requirements: [LandedRequirement216G]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(requirements.enumerated()), id: \.element.id) { index, requirement in
                HStack(alignment: .top, spacing: Space.s3) {
                    AddendaIconChip(
                        systemImage: requirement.critical ? "exclamationmark.shield.fill" : "doc.text.magnifyingglass",
                        tint: requirement.critical ? Brand.warning : Brand.info
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(requirement.requirement)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(requirement.category.uppercased()) · \(requirement.status.uppercased())")
                            .font(EType.mono(.micro))
                            .foregroundStyle(requirement.critical ? Brand.warning : palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.s4)
                if index < requirements.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, 56)
                }
            }
        }
        .addendaPanel(palette)
    }

    private func unsupportedRoute(_ load: LandedLoad216G) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(load.destCountry?.uppercased() == "MX" ? "Route country data is incomplete" : "This is not a recorded Mexico import")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text("The compliance lookup accepts recorded US, Canada, and Mexico country codes. This load currently reports \(countryLane(load)).")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private var fxAvailable: Bool {
        store.exchangeRates?.isTrustedForDisplay == true && store.exchangeRates?.rates.MXN != nil
    }

    private var canCalculate: Bool {
        fxAvailable && store.load?.destCountry?.uppercased() == "MX"
    }

    private func updatedSuffix(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return " · updated \(value)"
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(EType.micro).foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s3)
            Text(value)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func countryLane(_ load: LandedLoad216G) -> String {
        "\(load.originCountry?.uppercased() ?? "Not recorded") -> \(load.destCountry?.uppercased() ?? "Not recorded")"
    }

    private func moneyMXN(_ value: Double) -> String {
        value.formatted(.currency(code: "MXN"))
    }

    private func moneyUSD(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }
}

private struct LandedCostCalculatorSheet216G: View {
    @Binding var draft: LandedCostDraft216G
    let onCalculate: (LandedCostDraft216G) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var isCalculating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Customs basis") {
                    Picker("Pedimento type", selection: $draft.pedimentoType) {
                        ForEach(["A1", "A4", "G1", "IN", "K1", "V1", "RT"], id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    numberField("Declared customs value (USD)", text: $draft.customsValueUSD)
                    numberField("Ad-valorem tariff (%)", text: $draft.tariffPercent)
                    numberField("Compensatory quota (%)", text: $draft.compensatoryPercent)
                }

                Section("Costs outside customs value") {
                    numberField("International freight (USD)", text: $draft.internationalFreightUSD)
                    numberField("Insurance (USD)", text: $draft.insuranceUSD)
                    numberField("Customs broker (MXN)", text: $draft.brokerFeeMXN)
                    numberField("Terminal / handling (MXN)", text: $draft.handlingMXN)
                    numberField("Domestic transport (MXN)", text: $draft.domesticTransportMXN)
                    numberField("Other costs (MXN)", text: $draft.otherCostsMXN)
                }

                Section {
                    Text("Do not re-enter freight or insurance already included in the declared customs value. Empty optional fields are treated as zero and are shown transparently in the result.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Landed cost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCalculating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCalculating ? "Calculating…" : "Calculate") {
                        Task {
                            isCalculating = true
                            let calculated = await onCalculate(draft)
                            isCalculating = false
                            if calculated { dismiss() }
                        }
                    }
                    .disabled(isCalculating)
                }
            }
        }
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
    }
}

#Preview("216G · MX Landed Cost · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperMXLandedCost()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("216G · MX Landed Cost · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperMXLandedCost()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
