//
//  216E_ShipperVUCEMPedimento.swift
//  EusoTrip 2027 - Shipper VUCEM Pedimento.
//
//  Creates and reads tenant-scoped Pedimento drafts. Official submission and
//  numbering remain with a licensed customs broker through VUCEM/SAT.
//

import SwiftUI

private struct PedimentoLocation216E: Decodable {
    let city: String?
    let state: String?
}

private struct PedimentoLoad216E: Decodable {
    let id: String
    let loadNumber: String
    let status: String
    let cargoType: String?
    let dangerousGoodsStatus: String?
    let commodity: String?
    let commodityName: String?
    let weight: String?
    let weightUnit: String?
    let originCountry: String?
    let destCountry: String?
    let pickupLocation: PedimentoLocation216E?
    let deliveryLocation: PedimentoLocation216E?

    var numericId: Int { Int(id) ?? 0 }
    var lane: String {
        "\(location(pickupLocation)) -> \(location(deliveryLocation))"
    }

    private func location(_ value: PedimentoLocation216E?) -> String {
        let parts = [value?.city, value?.state]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Location not recorded" : parts.joined(separator: ", ")
    }
}

private struct PedimentoTaxes216E: Decodable {
    let arancelImporte: Double
    let iva: Double
    let dta: Double
    let cuotaCompensatoria: Double
    let prevalidacion: Double
    let total: Double
}

private struct PedimentoRecord216E: Decodable {
    let id: Int
    let pedimentoId: String
    let numeroPedimento: String?
    let numeroPedimentoPending: Bool
    let tipo: String
    let status: String
    let aduanaEntrada: String
    let aduanaSalida: String?
    let patente: String
    let pesoTotalKg: String
    let numBultos: Int
    let medioTransporte: String
    let valorDolares: String
    let tipoCambio: String
    let impuestos: PedimentoTaxes216E
    let loadId: Int?
    let vucemStatus: String
}

private struct PedimentoValidation216E: Decodable {
    let valid: Bool
    let errors: [String]
    let warnings: [String]
}

private struct PedimentoCreateResponse216E: Decodable {
    let pedimentoId: String
    let numeroPedimento: String?
    let numeroPedimentoReason: String
    let taxes: PedimentoTaxes216E
    let validation: PedimentoValidation216E
    let status: String
    let vucemStatus: String
}

private struct PedimentoDraft216E {
    var tipo = "A1"
    var importerRFC = ""
    var importerName = ""
    var importerAddress = ""
    var brokerRFC = ""
    var brokerName = ""
    var brokerAddress = ""
    var brokerPatent = ""
    var entryCustoms = ""
    var exitCustoms = ""
    var section = "0"
    var packageCount = ""
    var transportMode = "carretero"
    var vehiclePlate = ""
    var exchangeRate = ""
    var cartaPorteId = ""
    var commercialInvoice = ""
    var originCertificate = ""
    var tariffCode = ""
    var description = ""
    var quantity = ""
    var unit = "KGM"
    var customsValueUSD = ""
    var commercialValueMXN = ""
    var weightKg = ""
    var originCountry = ""
    var tariffPercent = "0"
    var compensatoryPercent = ""
    var relatedParty = false
    var valuationMethod = "1"

    init(load: PedimentoLoad216E) {
        description = load.commodityName ?? load.commodity ?? ""
        originCountry = load.originCountry?.uppercased() ?? ""
        weightKg = Self.weightInKilograms(load)
    }

    private static func weightInKilograms(_ load: PedimentoLoad216E) -> String {
        guard let raw = load.weight, let value = Double(raw), value > 0 else { return "" }
        switch load.weightUnit?.lowercased() {
        case "kg", "kgs", "kilogram", "kilograms": return String(format: "%.2f", value)
        case "lb", "lbs", "pound", "pounds", nil: return String(format: "%.2f", value * 0.45359237)
        case "mt", "t", "tonne", "tonnes", "metric_ton", "metric_tons": return String(format: "%.2f", value * 1_000)
        default: return ""
        }
    }
}

private struct PedimentoRequirement216E: Decodable, Identifiable {
    var id: String { "\(category)-\(requirement)" }
    let category: String
    let requirement: String
    let status: String
    let critical: Bool
}

private struct PedimentoCompliance216E: Decodable {
    let route: String
    let shipmentType: String
    let checklist: [PedimentoRequirement216E]
}

@MainActor
private final class PedimentoStore216E: ObservableObject {
    @Published private(set) var load: PedimentoLoad216E?
    @Published private(set) var record: PedimentoRecord216E?
    @Published private(set) var compliance: PedimentoCompliance216E?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false

    let loadId: String
    private let api: EusoTripAPI

    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    func refresh() async {
        guard !loadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            load = nil
            record = nil
            compliance = nil
            errorMessage = "Open Pedimento from a cross-border load to inspect its filing requirements."
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            struct LoadInput: Encodable { let id: String }
            let result: PedimentoLoad216E? = try await api.query(
                "loads.getById",
                input: LoadInput(id: loadId)
            )
            guard let resolved = result else {
                load = nil
                record = nil
                compliance = nil
                errorMessage = "This load is no longer available. Return to Loads and choose another one."
                return
            }
            load = resolved

            var failures: [String] = []
            if resolved.numericId > 0 {
                do {
                    struct RecordInput: Encodable { let loadId: Int }
                    record = try await api.query(
                        "crossBorderShipping.getPedimentoForLoad",
                        input: RecordInput(loadId: resolved.numericId)
                    )
                } catch {
                    record = nil
                    failures.append(error.eusoUserCopy)
                }
            } else {
                record = nil
                failures.append("This load has no numeric record identifier, so its Pedimento cannot be matched.")
            }

            guard let countries = supportedCountries(resolved) else {
                compliance = nil
                errorMessage = failures.isEmpty ? nil : failures.joined(separator: " ")
                return
            }

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
            errorMessage = failures.isEmpty ? nil : failures.joined(separator: " ")
        } catch {
            load = nil
            record = nil
            compliance = nil
            errorMessage = error.eusoUserCopy
        }
    }

    func createDraft(_ draft: PedimentoDraft216E) async -> Bool {
        guard let load, load.numericId > 0 else {
            errorMessage = "This load does not have the record ID required to create a Pedimento draft. Refresh the load and try again."
            return false
        }
        guard let countries = supportedCountries(load), countries.destination == "MX" else {
            errorMessage = "Pedimento import draft creation requires a recorded Mexico destination."
            return false
        }
        guard let packages = Int(draft.packageCount), packages > 0,
              let exchangeRate = Double(draft.exchangeRate), exchangeRate > 0,
              let quantity = Double(draft.quantity), quantity > 0,
              let customsValue = Double(draft.customsValueUSD), customsValue > 0,
              let commercialValue = Double(draft.commercialValueMXN), commercialValue > 0,
              let weight = Double(draft.weightKg), weight > 0,
              let tariffPercent = Double(draft.tariffPercent), tariffPercent >= 0,
              tariffPercent <= 100 else {
            errorMessage = "Packages, exchange rate, quantity, customs value, commercial value, and weight must be positive; tariff must be 0–100%."
            return false
        }
        let compensatoryRate: Double?
        if draft.compensatoryPercent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            compensatoryRate = nil
        } else if let percent = Double(draft.compensatoryPercent), percent >= 0, percent <= 100 {
            compensatoryRate = percent / 100
        } else {
            errorMessage = "Compensatory quota must be empty or a percentage from 0–100."
            return false
        }

        let required = [
            draft.importerRFC, draft.importerName, draft.importerAddress,
            draft.brokerRFC, draft.brokerName, draft.brokerAddress,
            draft.brokerPatent, draft.entryCustoms, draft.section,
            draft.description, draft.tariffCode, draft.unit,
            draft.originCountry,
        ]
        guard required.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            errorMessage = "Complete every required importer, customs broker, customs office, and merchandise field."
            return false
        }
        guard draft.tariffCode.range(of: "^[0-9]{8}$", options: .regularExpression) != nil else {
            errorMessage = "The tariff classification must contain exactly 8 digits."
            return false
        }
        guard draft.originCountry.count == 2 else {
            errorMessage = "Origin country must be a two-letter ISO country code."
            return false
        }
        guard draft.transportMode != "carretero" || !draft.vehiclePlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Road transport requires the vehicle plate."
            return false
        }

        struct Merchandise: Encodable {
            let fraccionArancelaria: String
            let descripcion: String
            let cantidad: Double
            let unidadMedida: String
            let valorAduana: Double
            let valorComercial: Double
            let pesoKg: Double
            let paisOrigen: String
            let arancelAdValorem: Double
            let cuotaCompensatoria: Double?
            let vinculacion: Bool
            let metodoValoracion: String
        }
        struct Input: Encodable {
            let tipo: String
            let loadId: Int
            let importadorRfc: String
            let importadorNombre: String
            let importadorDomicilio: String
            let agenteAduanalRfc: String
            let agenteAduanalNombre: String
            let agenteAduanalDomicilio: String
            let agenteAduanalPatente: String
            let aduanaEntrada: String
            let aduanaSalida: String?
            let seccion: String
            let numBultos: Int
            let medioTransporte: String
            let placaVehiculo: String?
            let tipoCambio: Double
            let cartaPorteId: String?
            let facturaComercial: String?
            let certificadoOrigen: String?
            let mercancias: [Merchandise]
        }

        let input = Input(
            tipo: draft.tipo,
            loadId: load.numericId,
            importadorRfc: draft.importerRFC,
            importadorNombre: draft.importerName,
            importadorDomicilio: draft.importerAddress,
            agenteAduanalRfc: draft.brokerRFC,
            agenteAduanalNombre: draft.brokerName,
            agenteAduanalDomicilio: draft.brokerAddress,
            agenteAduanalPatente: draft.brokerPatent,
            aduanaEntrada: draft.entryCustoms,
            aduanaSalida: nonEmpty(draft.exitCustoms),
            seccion: draft.section,
            numBultos: packages,
            medioTransporte: draft.transportMode,
            placaVehiculo: nonEmpty(draft.vehiclePlate),
            tipoCambio: exchangeRate,
            cartaPorteId: nonEmpty(draft.cartaPorteId),
            facturaComercial: nonEmpty(draft.commercialInvoice),
            certificadoOrigen: nonEmpty(draft.originCertificate),
            mercancias: [Merchandise(
                fraccionArancelaria: draft.tariffCode,
                descripcion: draft.description,
                cantidad: quantity,
                unidadMedida: draft.unit,
                valorAduana: customsValue,
                valorComercial: commercialValue,
                pesoKg: weight,
                paisOrigen: draft.originCountry.uppercased(),
                arancelAdValorem: tariffPercent / 100,
                cuotaCompensatoria: compensatoryRate,
                vinculacion: draft.relatedParty,
                metodoValoracion: draft.valuationMethod
            )]
        )

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            let response: PedimentoCreateResponse216E = try await api.mutation(
                "crossBorderShipping.createPedimento",
                input: input
            )
            guard response.validation.valid, response.status == "draft", response.vucemStatus == "not_submitted" else {
                errorMessage = response.validation.errors.joined(separator: " ")
                return false
            }
            await refresh()
            return record?.pedimentoId == response.pedimentoId
        } catch {
            errorMessage = error.eusoUserCopy
            return false
        }
    }

    private func supportedCountries(_ load: PedimentoLoad216E) -> (origin: String, destination: String)? {
        guard let origin = load.originCountry?.uppercased(),
              let destination = load.destCountry?.uppercased(),
              ["US", "CA", "MX"].contains(origin),
              ["US", "CA", "MX"].contains(destination) else { return nil }
        return (origin, destination)
    }

    private func shipmentType(_ load: PedimentoLoad216E) -> String {
        if load.dangerousGoodsStatus == "dangerous_goods" || load.cargoType == "hazmat" { return "hazmat" }
        switch load.cargoType {
        case "refrigerated", "food_grade": return "perishable"
        case "oversized": return "oversize"
        case "livestock": return "livestock"
        default: return "general"
        }
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ShipperVUCEMPedimento: View {
    let loadId: String
    @StateObject private var store: PedimentoStore216E
    @State private var showingCreateDraft = false
    @Environment(\.palette) private var palette

    init(loadId: String = "") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: PedimentoStore216E(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(
                    eyebrow: "SHIPPER · VUCEM · PEDIMENTO",
                    idText: store.load?.loadNumber ?? loadId,
                    title: "Pedimento"
                )

                if let errorMessage = store.errorMessage {
                    DegradedNote(text: errorMessage)
                        .padding(.top, Space.s3)
                }

                if store.isLoading, store.load == nil {
                    ProgressView("Loading import requirements")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s6)
                }

                if let load = store.load {
                    loadCard(load)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)

                    SectionLabel("FILING RECORD")
                        .padding(.top, Space.s5)
                    filingCard
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
        .sheet(isPresented: $showingCreateDraft) {
            if let load = store.load {
                PedimentoDraftSheet216E(load: load) { draft in
                    await store.createDraft(draft)
                }
            }
        }
    }

    private func loadCard(_ load: PedimentoLoad216E) -> some View {
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

    @ViewBuilder
    private var filingCard: some View {
        if let record = store.record {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s3) {
                    AddendaIconChip(systemImage: "doc.text.fill", tint: Brand.info)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.numeroPedimento ?? record.pedimentoId)
                            .font(EType.title)
                            .foregroundStyle(palette.textPrimary)
                        Text(record.numeroPedimentoPending ? "Official number pending VUCEM/SAT" : "Official Pedimento number")
                            .font(EType.mono(.caption))
                            .foregroundStyle(record.numeroPedimentoPending ? Brand.warning : Brand.success)
                    }
                    Spacer(minLength: 0)
                    AddendaChip(text: record.status.uppercased(), color: record.status == "draft" ? Brand.info : Brand.success)
                }
                Divider().overlay(palette.borderFaint)
                factRow("TYPE", record.tipo)
                factRow("VUCEM", record.vucemStatus.replacingOccurrences(of: "_", with: " ").uppercased())
                factRow("CUSTOMS OFFICE", record.aduanaEntrada)
                factRow("BROKER PATENT", record.patente)
                factRow("TRANSPORT", record.medioTransporte.uppercased())
                factRow("PACKAGES", "\(record.numBultos)")
                factRow("WEIGHT", "\(record.pesoTotalKg) kg")
                factRow("CUSTOMS VALUE", "$\(record.valorDolares) USD")
                factRow("FX", "\(record.tipoCambio) MXN/USD")
                Divider().overlay(palette.borderFaint)
                factRow("DUTY", moneyMXN(record.impuestos.arancelImporte))
                factRow("IVA", moneyMXN(record.impuestos.iva))
                factRow("DTA", moneyMXN(record.impuestos.dta))
                factRow("PREVALIDATION", moneyMXN(record.impuestos.prevalidacion))
                factRow("ESTIMATED TOTAL", moneyMXN(record.impuestos.total))
                Text("This is a persisted draft and tax estimate. It is not submitted, paid, pre-validated, or cleared until a licensed customs broker completes the real VUCEM workflow.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s4)
            .addendaPanel(palette)
        } else {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                VStack(alignment: .leading, spacing: 5) {
                    Text("No Pedimento draft is linked to this load")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text("Create a tenant-scoped draft with the importer, licensed customs broker, customs office, classified merchandise, transport, and current exchange-rate inputs. VUCEM submission and the official number remain pending until the broker files it.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if canCreateDraft {
                        Button {
                            showingCreateDraft = true
                        } label: {
                            Label("Create Pedimento draft", systemImage: "plus.circle.fill")
                                .font(EType.title)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .fill(LinearGradient.primary)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isSaving)
                        .padding(.top, Space.s3)
                    } else {
                        Text("Draft creation becomes available when this load has a numeric record ID and a recorded Mexico destination.")
                            .font(EType.caption)
                            .foregroundStyle(Brand.warning)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .addendaPanel(palette)
        }
    }

    private func requirementList(_ requirements: [PedimentoRequirement216E]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("These are route requirements from the compliance service, not proof that a filing has cleared them.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(Space.s4)

            Divider().overlay(palette.borderFaint)

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

    private func unsupportedRoute(_ load: PedimentoLoad216E) -> some View {
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

    private func countryLane(_ load: PedimentoLoad216E) -> String {
        "\(load.originCountry?.uppercased() ?? "Not recorded") -> \(load.destCountry?.uppercased() ?? "Not recorded")"
    }

    private func moneyMXN(_ value: Double) -> String {
        value.formatted(.currency(code: "MXN"))
    }

    private var canCreateDraft: Bool {
        guard let load = store.load, load.numericId > 0 else { return false }
        return load.destCountry?.uppercased() == "MX"
    }
}

private struct PedimentoDraftSheet216E: View {
    let load: PedimentoLoad216E
    let onCreate: (PedimentoDraft216E) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PedimentoDraft216E
    @State private var isSubmitting = false

    init(load: PedimentoLoad216E, onCreate: @escaping (PedimentoDraft216E) async -> Bool) {
        self.load = load
        self.onCreate = onCreate
        _draft = State(initialValue: PedimentoDraft216E(load: load))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Filing") {
                    Picker("Pedimento type", selection: $draft.tipo) {
                        ForEach(["A1", "A4", "G1", "IN", "K1", "V1", "RT"], id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    field("Entry customs office code", text: $draft.entryCustoms, capitals: true)
                    field("Exit customs office code (optional)", text: $draft.exitCustoms, capitals: true)
                    field("Customs section", text: $draft.section, capitals: true)
                    numberField("Package count", text: $draft.packageCount)
                    numberField("Current MXN per USD rate", text: $draft.exchangeRate)
                }

                Section("Importer") {
                    field("RFC", text: $draft.importerRFC, capitals: true)
                    field("Legal name", text: $draft.importerName)
                    field("Fiscal address", text: $draft.importerAddress)
                }

                Section("Licensed customs broker") {
                    field("Broker RFC", text: $draft.brokerRFC, capitals: true)
                    field("Broker legal name", text: $draft.brokerName)
                    field("Broker fiscal address", text: $draft.brokerAddress)
                    field("Patente aduanal", text: $draft.brokerPatent, capitals: true)
                }

                Section("Transport") {
                    Picker("Mode", selection: $draft.transportMode) {
                        Text("Road").tag("carretero")
                        Text("Rail").tag("ferroviario")
                        Text("Vessel").tag("maritimo")
                        Text("Air").tag("aereo")
                    }
                    if draft.transportMode == "carretero" {
                        field("Vehicle plate", text: $draft.vehiclePlate, capitals: true)
                    }
                    field("Carta Porte document ID (optional)", text: $draft.cartaPorteId, capitals: true)
                    field("Commercial invoice (optional)", text: $draft.commercialInvoice, capitals: true)
                    field("Origin certificate (optional)", text: $draft.originCertificate, capitals: true)
                }

                Section("Merchandise") {
                    field("Tariff classification (8 digits)", text: $draft.tariffCode, capitals: true)
                    field("Description", text: $draft.description)
                    numberField("Quantity", text: $draft.quantity)
                    field("SAT unit code", text: $draft.unit, capitals: true)
                    numberField("Customs value (USD)", text: $draft.customsValueUSD)
                    numberField("Commercial value (MXN)", text: $draft.commercialValueMXN)
                    numberField("Weight (kg)", text: $draft.weightKg)
                    field("Origin country (ISO-2)", text: $draft.originCountry, capitals: true)
                    numberField("Ad-valorem tariff (%)", text: $draft.tariffPercent)
                    numberField("Compensatory quota (%)", text: $draft.compensatoryPercent)
                    Toggle("Related-party transaction", isOn: $draft.relatedParty)
                    Picker("WTO valuation method", selection: $draft.valuationMethod) {
                        ForEach(["1", "2", "3", "4", "5", "6"], id: \.self) { method in
                            Text(method).tag(method)
                        }
                    }
                }

                Section {
                    Text("This creates a persisted draft and tax estimate. It does not submit to VUCEM, obtain pre-validation, pay duties, or assign an official Pedimento number.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Pedimento draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Creating…" : "Create") {
                        Task {
                            isSubmitting = true
                            let created = await onCreate(draft)
                            isSubmitting = false
                            if created { dismiss() }
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, capitals: Bool = false) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(capitals ? .characters : .words)
            .autocorrectionDisabled(capitals)
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
    }
}

#Preview("216E · VUCEM Pedimento · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperVUCEMPedimento()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("216E · VUCEM Pedimento · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperVUCEMPedimento()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
