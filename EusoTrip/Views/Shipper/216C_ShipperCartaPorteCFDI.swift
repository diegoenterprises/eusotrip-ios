//
//  216C_ShipperCartaPorteCFDI.swift
//  EusoTrip 2027 - Shipper Carta Porte.
//
//  This surface reads persisted Carta Porte rows and cross-border requirements.
//  It never turns a load identifier into a fabricated fiscal document.
//

import SwiftUI

private struct CartaLocation216C: Decodable {
    let city: String?
    let state: String?
}

private struct CartaLoad216C: Decodable {
    let id: String
    let loadNumber: String
    let status: String
    let cargoType: String?
    let dangerousGoodsStatus: String?
    let unNumber: String?
    let commodity: String?
    let commodityName: String?
    let weight: String?
    let weightUnit: String?
    let originCountry: String?
    let destCountry: String?
    let pickupLocation: CartaLocation216C?
    let deliveryLocation: CartaLocation216C?

    var numericId: Int { Int(id) ?? 0 }
    var lane: String {
        "\(location(pickupLocation)) → \(location(deliveryLocation))"
    }

    private func location(_ value: CartaLocation216C?) -> String {
        let parts = [value?.city, value?.state]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Location not recorded" : parts.joined(separator: ", ")
    }
}

private struct CartaPorteValidation216C: Decodable {
    let valid: Bool
    let errors: [String]
    let warnings: [String]
}

private struct CartaPorteCreated216C: Decodable {
    let id: String
    let status: String
}

private struct CartaPorteCreateResponse216C: Decodable {
    let success: Bool
    let document: CartaPorteCreated216C
    let validation: CartaPorteValidation216C
    let xml: String?
}

private struct CartaPorteDraft216C {
    var tipo = "ingreso"
    var issuerRFC = ""
    var issuerName = ""
    var fiscalRegime = "601"
    var recipientRFC = ""
    var recipientName = ""
    var cfdiUse = "S01"
    var productKey = ""
    var description = ""
    var quantity = ""
    var unitKey = "KGM"
    var weightKg = ""
    var declaredValue = ""
    var currency = "MXN"
    var isHazmat = false
    var hazmatCode = ""
    var packagingCode = ""
    var tariffCode = ""
    var vehicleConfig = ""
    var vehiclePlate = ""
    var modelYear = ""
    var insurer = ""
    var policyNumber = ""
    var permitType = ""
    var permitNumber = ""
    var driverRFC = ""
    var driverName = ""
    var driverLicense = ""
    var driverLicenseType = ""
    var originStreet = ""
    var originExteriorNumber = ""
    var originColonia = ""
    var originMunicipio = ""
    var originState = ""
    var originPostalCode = ""
    var destinationStreet = ""
    var destinationExteriorNumber = ""
    var destinationColonia = ""
    var destinationMunicipio = ""
    var destinationState = ""
    var destinationPostalCode = ""
    var distanceKm = ""
    var departure = Date()
    var arrival = Date().addingTimeInterval(86_400)

    init(load: CartaLoad216C) {
        description = load.commodityName ?? load.commodity ?? ""
        isHazmat = load.dangerousGoodsStatus == "dangerous_goods" || load.cargoType == "hazmat"
        hazmatCode = load.unNumber ?? ""
        originMunicipio = load.pickupLocation?.city ?? ""
        originState = load.pickupLocation?.state ?? ""
        destinationMunicipio = load.deliveryLocation?.city ?? ""
        destinationState = load.deliveryLocation?.state ?? ""
        weightKg = Self.weightInKilograms(load)
    }

    private static func weightInKilograms(_ load: CartaLoad216C) -> String {
        guard let raw = load.weight, let value = Double(raw), value > 0 else { return "" }
        switch load.weightUnit?.lowercased() {
        case "kg", "kgs", "kilogram", "kilograms": return String(format: "%.2f", value)
        case "lb", "lbs", "pound", "pounds", nil: return String(format: "%.2f", value * 0.45359237)
        case "mt", "t", "tonne", "tonnes", "metric_ton", "metric_tons": return String(format: "%.2f", value * 1_000)
        default: return ""
        }
    }
}

private struct CartaPorteRecord216C: Decodable, Identifiable {
    let id: Int
    let documentId: String
    let version: String
    let tipo: String
    let status: String
    let rfcEmisor: String
    let nombreEmisor: String
    let rfcReceptor: String
    let nombreReceptor: String
    let transpInternac: String
    let entradaSalidaMerc: String?
    let paisOrigenDestino: String?
    let pesoTotalKg: String
    let numTotalMercancias: Int
    let uuid: String?
    let xmlContent: String?
    let loadId: Int?
}

private struct BorderRequirement216C: Decodable, Identifiable {
    var id: String { "\(category)-\(requirement)" }
    let category: String
    let requirement: String
    let status: String
    let critical: Bool
}

private struct BorderCompliance216C: Decodable {
    let route: String
    let shipmentType: String
    let checklist: [BorderRequirement216C]
}

@MainActor
private final class CartaPorteStore216C: ObservableObject {
    @Published private(set) var load: CartaLoad216C?
    @Published private(set) var record: CartaPorteRecord216C?
    @Published private(set) var compliance: BorderCompliance216C?
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
            errorMessage = "Open Carta Porte from a cross-border load to see its fiscal records."
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            struct LoadInput: Encodable { let id: String }
            let result: CartaLoad216C? = try await api.query(
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
                        "crossBorderShipping.getCartaPorteForLoad",
                        input: RecordInput(loadId: resolved.numericId)
                    )
                } catch {
                    record = nil
                    failures.append(error.eusoUserCopy)
                }
            } else {
                record = nil
                failures.append("This load has no numeric record identifier, so its Carta Porte cannot be matched.")
            }

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

            errorMessage = failures.isEmpty ? nil : failures.joined(separator: " ")
        } catch {
            load = nil
            record = nil
            compliance = nil
            errorMessage = error.eusoUserCopy
        }
    }

    func createDraft(_ draft: CartaPorteDraft216C) async -> Bool {
        guard let load, load.numericId > 0 else {
            errorMessage = "This load does not have the record ID required to create a Carta Porte draft. Refresh the load and try again."
            return false
        }
        guard let countries = supportedCountries(load),
              countries.origin == "MX" || countries.destination == "MX" else {
            errorMessage = "Carta Porte draft creation requires a recorded Mexico route."
            return false
        }
        guard let quantity = Double(draft.quantity), quantity > 0,
              let weightKg = Double(draft.weightKg), weightKg > 0,
              let declaredValue = Double(draft.declaredValue), declaredValue > 0,
              let modelYear = Int(draft.modelYear), modelYear > 0,
              let distanceKm = Double(draft.distanceKm), distanceKm > 0 else {
            errorMessage = "Quantity, weight, declared value, model year, and route distance must be positive numbers."
            return false
        }
        guard draft.arrival > draft.departure else {
            errorMessage = "Arrival must be later than departure."
            return false
        }

        let required = [
            draft.issuerRFC, draft.issuerName, draft.fiscalRegime,
            draft.recipientRFC, draft.recipientName, draft.cfdiUse,
            draft.productKey, draft.description, draft.unitKey,
            draft.vehicleConfig, draft.vehiclePlate, draft.insurer,
            draft.policyNumber, draft.permitType, draft.permitNumber,
            draft.driverRFC, draft.driverName, draft.driverLicense,
            draft.driverLicenseType, draft.originStreet,
            draft.originExteriorNumber, draft.originColonia,
            draft.originMunicipio, draft.originState, draft.originPostalCode,
            draft.destinationStreet, draft.destinationExteriorNumber,
            draft.destinationColonia, draft.destinationMunicipio,
            draft.destinationState, draft.destinationPostalCode,
        ]
        guard required.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            errorMessage = "Complete every required tax, cargo, vehicle, operator, and route field."
            return false
        }
        guard !draft.isHazmat || !draft.hazmatCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "A dangerous-goods Carta Porte requires its material code or UN number."
            return false
        }

        struct Address: Encodable {
            let street: String
            let exteriorNumber: String
            let colonia: String
            let municipio: String
            let estado: String
            let codigoPostal: String
            let pais: String
        }
        struct Sender: Encodable {
            let rfcRemitente: String
            let nombreRemitente: String
            let domicilio: Address
            let fechaSalida: String
        }
        struct Receiver: Encodable {
            let rfcRemitente: String
            let nombreRemitente: String
            let domicilio: Address
            let fechaLlegada: String
        }
        struct Route: Encodable {
            let origen: Sender
            let destino: Receiver
            let distanciaKm: Double
        }
        struct Issuer: Encodable {
            let rfc: String
            let nombre: String
            let regimenFiscal: String
        }
        struct Recipient: Encodable {
            let rfc: String
            let nombre: String
            let usoCFDI: String
        }
        struct Cargo: Encodable {
            let claveProducto: String
            let descripcion: String
            let cantidad: Double
            let claveUnidad: String
            let pesoKg: Double
            let valorMercancia: Double
            let moneda: String
            let materialPeligroso: Bool
            let cveMaterialPeligroso: String?
            let embalaje: String?
            let fraccionArancelaria: String?
        }
        struct Vehicle: Encodable {
            let configVehicular: String
            let placaVM: String
            let anioModelo: Int
            let aseguradora: String
            let polizaSeguro: String
            let permisoSCT: String
            let numPermisoSCT: String
        }
        struct Driver: Encodable {
            let rfcFigura: String
            let nombreFigura: String
            let numLicencia: String
            let tipoLicencia: String
        }
        struct Input: Encodable {
            let tipo: String
            let emisor: Issuer
            let receptor: Recipient
            let mercancias: [Cargo]
            let vehiculo: Vehicle
            let conductores: [Driver]
            let ruta: Route
            let isInternational: Bool
            let entradaSalida: String
            let paisOrigenDestino: String
            let loadId: Int
        }

        let formatter = ISO8601DateFormatter()
        let originCountry = satCountry(countries.origin)
        let destinationCountry = satCountry(countries.destination)
        let input = Input(
            tipo: draft.tipo,
            emisor: Issuer(rfc: draft.issuerRFC, nombre: draft.issuerName, regimenFiscal: draft.fiscalRegime),
            receptor: Recipient(rfc: draft.recipientRFC, nombre: draft.recipientName, usoCFDI: draft.cfdiUse),
            mercancias: [Cargo(
                claveProducto: draft.productKey,
                descripcion: draft.description,
                cantidad: quantity,
                claveUnidad: draft.unitKey,
                pesoKg: weightKg,
                valorMercancia: declaredValue,
                moneda: draft.currency,
                materialPeligroso: draft.isHazmat,
                cveMaterialPeligroso: nonEmpty(draft.hazmatCode),
                embalaje: nonEmpty(draft.packagingCode),
                fraccionArancelaria: nonEmpty(draft.tariffCode)
            )],
            vehiculo: Vehicle(
                configVehicular: draft.vehicleConfig,
                placaVM: draft.vehiclePlate,
                anioModelo: modelYear,
                aseguradora: draft.insurer,
                polizaSeguro: draft.policyNumber,
                permisoSCT: draft.permitType,
                numPermisoSCT: draft.permitNumber
            ),
            conductores: [Driver(
                rfcFigura: draft.driverRFC,
                nombreFigura: draft.driverName,
                numLicencia: draft.driverLicense,
                tipoLicencia: draft.driverLicenseType
            )],
            ruta: Route(
                origen: Sender(
                    rfcRemitente: draft.issuerRFC,
                    nombreRemitente: draft.issuerName,
                    domicilio: Address(
                        street: draft.originStreet,
                        exteriorNumber: draft.originExteriorNumber,
                        colonia: draft.originColonia,
                        municipio: draft.originMunicipio,
                        estado: draft.originState,
                        codigoPostal: draft.originPostalCode,
                        pais: originCountry
                    ),
                    fechaSalida: formatter.string(from: draft.departure)
                ),
                destino: Receiver(
                    rfcRemitente: draft.recipientRFC,
                    nombreRemitente: draft.recipientName,
                    domicilio: Address(
                        street: draft.destinationStreet,
                        exteriorNumber: draft.destinationExteriorNumber,
                        colonia: draft.destinationColonia,
                        municipio: draft.destinationMunicipio,
                        estado: draft.destinationState,
                        codigoPostal: draft.destinationPostalCode,
                        pais: destinationCountry
                    ),
                    fechaLlegada: formatter.string(from: draft.arrival)
                ),
                distanciaKm: distanceKm
            ),
            isInternational: countries.origin != countries.destination,
            entradaSalida: countries.destination == "MX" ? "Entrada" : "Salida",
            paisOrigenDestino: countries.destination == "MX" ? originCountry : destinationCountry,
            loadId: load.numericId
        )

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            let response: CartaPorteCreateResponse216C = try await api.mutation(
                "crossBorderShipping.createCartaPorte",
                input: input
            )
            guard response.success, response.validation.valid else {
                errorMessage = response.validation.errors.joined(separator: " ")
                return false
            }
            await refresh()
            return record?.documentId == response.document.id
        } catch {
            errorMessage = error.eusoUserCopy
            return false
        }
    }

    private func supportedCountries(_ load: CartaLoad216C) -> (origin: String, destination: String)? {
        guard let origin = load.originCountry?.uppercased(),
              let destination = load.destCountry?.uppercased(),
              ["US", "CA", "MX"].contains(origin),
              ["US", "CA", "MX"].contains(destination) else { return nil }
        return (origin, destination)
    }

    private func shipmentType(_ load: CartaLoad216C) -> String {
        if load.dangerousGoodsStatus == "dangerous_goods" || load.cargoType == "hazmat" { return "hazmat" }
        switch load.cargoType {
        case "refrigerated", "food_grade": return "perishable"
        case "oversized": return "oversize"
        case "livestock": return "livestock"
        default: return "general"
        }
    }

    private func satCountry(_ value: String) -> String {
        switch value {
        case "US": return "USA"
        case "CA": return "CAN"
        default: return "MEX"
        }
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ShipperCartaPorteCFDI: View {
    let loadId: String
    @StateObject private var store: CartaPorteStore216C
    @State private var showingCreateDraft = false
    @Environment(\.palette) private var palette

    init(loadId: String = "") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: CartaPorteStore216C(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(
                    eyebrow: "SHIPPER · CARTA PORTE · CFDI",
                    idText: store.load?.loadNumber ?? loadId,
                    title: "Carta Porte"
                )

                if let errorMessage = store.errorMessage {
                    DegradedNote(text: errorMessage)
                        .padding(.top, Space.s3)
                }

                if store.isLoading, store.load == nil {
                    ProgressView("Loading fiscal records")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s6)
                }

                if let load = store.load {
                    loadCard(load)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)

                    SectionLabel("PERSISTED FISCAL DOCUMENT")
                        .padding(.top, Space.s5)
                    documentCard
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)
                }

                if let compliance = store.compliance {
                    SectionLabel("CROSS-BORDER REQUIREMENTS · \(compliance.route)")
                        .padding(.top, Space.s5)
                    requirementList(compliance.checklist)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)
                } else if let load = store.load {
                    unsupportedRoute(load)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)
                }

                if store.errorMessage != nil, !loadId.isEmpty {
                    CTAButton(title: "Retry", action: { Task { await store.refresh() } }, isLoading: store.isLoading)
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
                CartaPorteDraftSheet216C(load: load) { draft in
                    await store.createDraft(draft)
                }
            }
        }
    }

    private func loadCard(_ load: CartaLoad216C) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                AddendaIconChip(systemImage: "doc.text.fill", tint: Brand.info)
                VStack(alignment: .leading, spacing: 4) {
                    Text(load.commodityName ?? load.commodity ?? "Cargo not recorded")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text(load.lane)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                AddendaChip(text: load.status.replacingOccurrences(of: "_", with: " ").uppercased(), color: Brand.info)
            }
            Divider().overlay(palette.borderFaint)
            factRow("COUNTRIES", countryLane(load))
            factRow("CARGO", (load.cargoType ?? "Not recorded").replacingOccurrences(of: "_", with: " ").uppercased())
            factRow("WEIGHT", weightText(load))
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    @ViewBuilder
    private var documentCard: some View {
        if let record = store.record {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s3) {
                    AddendaIconChip(systemImage: "checkmark.seal.fill", tint: statusColor(record.status))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.documentId)
                            .font(EType.title)
                            .foregroundStyle(palette.textPrimary)
                        Text("Carta Porte \(record.version) · \(record.tipo.capitalized)")
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    AddendaChip(text: record.status.replacingOccurrences(of: "_", with: " ").uppercased(), color: statusColor(record.status))
                }
                Divider().overlay(palette.borderFaint)
                factRow("EMISOR", "\(record.nombreEmisor) · \(record.rfcEmisor)")
                factRow("RECEPTOR", "\(record.nombreReceptor) · \(record.rfcReceptor)")
                factRow("INTERNATIONAL", record.transpInternac)
                factRow("DIRECTION", record.entradaSalidaMerc ?? "Not recorded")
                factRow("COUNTRY", record.paisOrigenDestino ?? "Not recorded")
                factRow("MERCHANDISE", "\(record.numTotalMercancias)")
                factRow("TOTAL WEIGHT", "\(record.pesoTotalKg) kg")
                factRow("FISCAL UUID", nonEmpty(record.uuid) ?? "Not assigned")

                if let xml = nonEmpty(record.xmlContent) {
                    ShareLink(item: xml, subject: Text("Carta Porte \(record.documentId) XML")) {
                        Label("Share recorded XML", systemImage: "square.and.arrow.up")
                            .font(EType.title)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(LinearGradient.primary)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Space.s2)
                } else {
                    Text("No XML content is stored on this Carta Porte record.")
                        .font(EType.caption)
                        .foregroundStyle(Brand.warning)
                }
            }
            .padding(Space.s4)
            .addendaPanel(palette)
        } else {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "doc.badge.ellipsis")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No Carta Porte is linked to this load")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text("Create a persisted draft with the issuer, recipient, merchandise, vehicle, operator, and route data required by Carta Porte 3.1. PAC signing and timbrado remain unavailable until a real PAC issues the folio fiscal.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if canCreateDraft {
                        Button {
                            showingCreateDraft = true
                        } label: {
                            Label("Create Carta Porte draft", systemImage: "plus.circle.fill")
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
                        Text("Draft creation becomes available when this load has a numeric record ID and a recorded route entering or leaving Mexico.")
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

    private func requirementList(_ requirements: [BorderRequirement216C]) -> some View {
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

    private func unsupportedRoute(_ load: CartaLoad216C) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("Route requirements unavailable")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text("Cross-border requirement lookup accepts recorded US, Canada, and Mexico country codes. This load currently reports \(countryLane(load)).")
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
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func countryLane(_ load: CartaLoad216C) -> String {
        "\(load.originCountry?.uppercased() ?? "Not recorded") → \(load.destCountry?.uppercased() ?? "Not recorded")"
    }

    private func weightText(_ load: CartaLoad216C) -> String {
        guard let weight = nonEmpty(load.weight) else { return "Not recorded" }
        return "\(weight) \(load.weightUnit ?? "")".trimmingCharacters(in: .whitespaces)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "stamped", "signed": return Brand.success
        case "cancelled", "error": return Brand.warning
        default: return Brand.info
        }
    }

    private var canCreateDraft: Bool {
        guard let load = store.load, load.numericId > 0 else { return false }
        let origin = load.originCountry?.uppercased()
        let destination = load.destCountry?.uppercased()
        return origin == "MX" || destination == "MX"
    }
}

private struct CartaPorteDraftSheet216C: View {
    let load: CartaLoad216C
    let onCreate: (CartaPorteDraft216C) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CartaPorteDraft216C
    @State private var isSubmitting = false

    init(load: CartaLoad216C, onCreate: @escaping (CartaPorteDraft216C) async -> Bool) {
        self.load = load
        self.onCreate = onCreate
        _draft = State(initialValue: CartaPorteDraft216C(load: load))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fiscal parties") {
                    Picker("Document type", selection: $draft.tipo) {
                        Text("Ingreso").tag("ingreso")
                        Text("Traslado").tag("traslado")
                    }
                    field("Issuer RFC", text: $draft.issuerRFC, capitals: true)
                    field("Issuer legal name", text: $draft.issuerName)
                    field("Issuer fiscal regime", text: $draft.fiscalRegime, capitals: true)
                    field("Recipient RFC", text: $draft.recipientRFC, capitals: true)
                    field("Recipient legal name", text: $draft.recipientName)
                    field("CFDI use", text: $draft.cfdiUse, capitals: true)
                }

                Section("Merchandise") {
                    field("SAT product key (8 digits)", text: $draft.productKey, capitals: true)
                    field("Description", text: $draft.description)
                    numberField("Quantity", text: $draft.quantity)
                    field("SAT unit key", text: $draft.unitKey, capitals: true)
                    numberField("Weight (kg)", text: $draft.weightKg)
                    numberField("Declared value", text: $draft.declaredValue)
                    Picker("Currency", selection: $draft.currency) {
                        ForEach(["MXN", "USD", "CAD"], id: \.self) { currency in
                            Text(currency).tag(currency)
                        }
                    }
                    Toggle("Dangerous goods", isOn: $draft.isHazmat)
                    if draft.isHazmat {
                        field("Material code / UN number", text: $draft.hazmatCode, capitals: true)
                        field("Packaging code", text: $draft.packagingCode, capitals: true)
                    }
                    field("Tariff classification (optional)", text: $draft.tariffCode, capitals: true)
                }

                Section("Vehicle and operator") {
                    field("Vehicle configuration", text: $draft.vehicleConfig, capitals: true)
                    field("Vehicle plate", text: $draft.vehiclePlate, capitals: true)
                    numberField("Model year", text: $draft.modelYear)
                    field("Insurer", text: $draft.insurer)
                    field("Policy number", text: $draft.policyNumber, capitals: true)
                    field("SICT permit type", text: $draft.permitType, capitals: true)
                    field("SICT permit number", text: $draft.permitNumber, capitals: true)
                    field("Operator RFC", text: $draft.driverRFC, capitals: true)
                    field("Operator name", text: $draft.driverName)
                    field("Operator license", text: $draft.driverLicense, capitals: true)
                    field("License type", text: $draft.driverLicenseType, capitals: true)
                }

                Section("Origin · \(load.originCountry?.uppercased() ?? "country not recorded")") {
                    field("Street", text: $draft.originStreet)
                    field("Exterior number", text: $draft.originExteriorNumber)
                    field("Colonia", text: $draft.originColonia)
                    field("Municipio", text: $draft.originMunicipio)
                    field("State code", text: $draft.originState, capitals: true)
                    numberField("Postal code", text: $draft.originPostalCode)
                    DatePicker("Departure", selection: $draft.departure)
                }

                Section("Destination · \(load.destCountry?.uppercased() ?? "country not recorded")") {
                    field("Street", text: $draft.destinationStreet)
                    field("Exterior number", text: $draft.destinationExteriorNumber)
                    field("Colonia", text: $draft.destinationColonia)
                    field("Municipio", text: $draft.destinationMunicipio)
                    field("State code", text: $draft.destinationState, capitals: true)
                    numberField("Postal code", text: $draft.destinationPostalCode)
                    DatePicker("Arrival", selection: $draft.arrival)
                    numberField("Route distance (km)", text: $draft.distanceKm)
                }

                Section {
                    Text("This creates a tenant-scoped draft and recorded XML. It does not sign, stamp, or assign a PAC folio fiscal.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Carta Porte draft")
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

#Preview("216C · Carta Porte · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperCartaPorteCFDI()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("216C · Carta Porte · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperCartaPorteCFDI()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
