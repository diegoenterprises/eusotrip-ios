//
//  822_VesselWriteCenter.swift
//  EusoTrip
//
//  Role-scoped native entry point for the five persisted vessel/intermodal
//  writer procedures. Every selector is populated from live scoped readers;
//  a positive server record ID is the only success state.
//

import SwiftUI

enum VesselWriteAction: String, CaseIterable, Identifiable {
    case publishFreightRate
    case createVoyage
    case createCargoManifest
    case recordBunkerDelivery
    case registerContainer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publishFreightRate: return "Publish freight rate"
        case .createVoyage: return "Create voyage"
        case .createCargoManifest: return "Create cargo manifest"
        case .recordBunkerDelivery: return "Record bunker delivery"
        case .registerContainer: return "Register container"
        }
    }

    var subtitle: String {
        switch self {
        case .publishFreightRate: return "Persist a priced port pair and effective service window"
        case .createVoyage: return "Schedule a scoped vessel between active ports"
        case .createCargoManifest: return "Bind real shipment cargo to a compatible voyage"
        case .recordBunkerDelivery: return "Record supplier evidence and the verified delivery total"
        case .registerContainer: return "Add intermodal equipment to company inventory"
        }
    }

    var icon: String {
        switch self {
        case .publishFreightRate: return "dollarsign.arrow.circlepath"
        case .createVoyage: return "ferry.fill"
        case .createCargoManifest: return "doc.text.fill"
        case .recordBunkerDelivery: return "fuelpump.fill"
        case .registerContainer: return "shippingbox.fill"
        }
    }
}

enum VesselWriteRolePolicy {
    static func allowedActions(for role: EusoRole) -> [VesselWriteAction] {
        switch role {
        case .vesselOperator, .admin, .superAdmin:
            return VesselWriteAction.allCases
        case .shipCaptain:
            return [.recordBunkerDelivery]
        case .portMaster, .terminal:
            return [.registerContainer]
        default:
            return []
        }
    }
}

struct VesselWriteCenterScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VesselWriteCenterBody()
        } nav: {
            EmptyView()
        }
    }
}

@MainActor
private struct VesselWriteCenterBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = VesselWritePrerequisiteStore()
    @State private var selectedAction: VesselWriteAction?
    @State private var receipt: VesselWriteReceipt?

    private var role: EusoRole? { session.user?.roleEnum }
    private var actions: [VesselWriteAction] {
        guard let role else { return [] }
        return VesselWriteRolePolicy.allowedActions(for: role)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header

            if let receipt {
                receiptCard(receipt)
            }

            if store.loading {
                LifecycleCard {
                    HStack(spacing: Space.s3) {
                        ProgressView()
                        Text("Loading scoped vessel records")
                            .font(EType.body)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }

            if !store.errors.isEmpty {
                LifecycleCard(accentDanger: true) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("Some live records could not be loaded")
                            .font(EType.title)
                            .foregroundStyle(Brand.danger)
                        ForEach(store.errors, id: \.self) { message in
                            Text(message)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                        Button("Retry") { Task { await reload() } }
                            .buttonStyle(.bordered)
                    }
                }
            }

            if actions.isEmpty, !store.loading {
                LifecycleCard(accentDanger: true) {
                    Text("This account role is not permitted to create vessel or intermodal records.")
                        .font(EType.body)
                        .foregroundStyle(palette.textSecondary)
                }
            } else {
                ForEach(actions) { action in
                    actionCard(action)
                }
            }

            if let inventory = store.containerInventory,
               actions.contains(.registerContainer) {
                inventoryCard(inventory)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s4)
        .task(id: role) { await reload() }
        .eusoRefreshable { await reload() }
        .sheet(item: $selectedAction) { action in
            writeForm(for: action)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            EusoTripEyebrow(verbatim: "VESSEL · CREATE & REGISTER")
            Text("Operations ledger")
                .font(EType.h1)
                .foregroundStyle(palette.textPrimary)
            Text("Authenticated writes for \(role?.displayName ?? "your role")")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func actionCard(_ action: VesselWriteAction) -> some View {
        let readiness = store.readiness(for: action)
        return LifecycleCard(accentGradient: readiness == nil) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s3) {
                    Image(systemName: action.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.title)
                            .font(EType.title)
                            .foregroundStyle(palette.textPrimary)
                        Text(action.subtitle)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                if let readiness {
                    Text(readiness)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }

                Button {
                    selectedAction = action
                } label: {
                    Label(action.title, systemImage: "plus.circle.fill")
                        .font(EType.title)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.blue)
                .disabled(store.loading || readiness != nil)
            }
        }
    }

    private func receiptCard(_ receipt: VesselWriteReceipt) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Label("Persisted", systemImage: "checkmark.seal.fill")
                    .font(EType.title)
                    .foregroundStyle(Brand.success)
                Text("\(receipt.action.title) · record ID \(receipt.id)")
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                if receipt.idempotent {
                    Text("The original request is already recorded.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                if let totalCost = receipt.totalCost, let currency = receipt.currency {
                    Text("Verified total · \(currency) \(totalCost)")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func inventoryCard(
        _ inventory: EusoTripAPI.VesselContainerInventorySummary
    ) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("LIVE CONTAINER INVENTORY")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                HStack {
                    inventoryValue("Total", inventory.total)
                    Spacer()
                    inventoryValue("Loaded", inventory.loaded)
                    Spacer()
                    inventoryValue("Empty", inventory.empty)
                    Spacer()
                    inventoryValue("Damaged", inventory.damaged)
                }
            }
        }
    }

    private func inventoryValue(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(value))
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(label)
                .font(EType.micro)
                .foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private func writeForm(for action: VesselWriteAction) -> some View {
        switch action {
        case .publishFreightRate:
            VesselFreightRateForm(
                ports: store.ports,
                onPersisted: persisted
            )
        case .createVoyage:
            VesselVoyageForm(
                ports: store.ports,
                vessels: store.vessels,
                onPersisted: persisted
            )
        case .createCargoManifest:
            VesselCargoManifestForm(
                ports: store.ports,
                voyages: store.voyages,
                shipments: store.shipments,
                onPersisted: persisted
            )
        case .recordBunkerDelivery:
            VesselBunkerDeliveryForm(
                role: role,
                ports: store.ports,
                vessels: store.vessels,
                voyages: store.voyages,
                onPersisted: persisted
            )
        case .registerContainer:
            IntermodalContainerRegistrationForm(onPersisted: persisted)
        }
    }

    private func persisted(_ value: VesselWriteReceipt) {
        receipt = value
        selectedAction = nil
        Task { await reload() }
    }

    private func reload() async {
        guard let role else { return }
        await store.load(for: role)
    }
}

@MainActor
private final class VesselWritePrerequisiteStore: ObservableObject {
    @Published private(set) var ports: [EusoTripAPI.VesselWritePort] = []
    @Published private(set) var vessels: [EusoTripAPI.VesselWriteFleetRow] = []
    @Published private(set) var voyages: [EusoTripAPI.VesselWriteVoyageRow] = []
    @Published private(set) var shipments: [EusoTripAPI.VesselWriteShipmentRow] = []
    @Published private(set) var containerInventory: EusoTripAPI.VesselContainerInventorySummary?
    @Published private(set) var errors: [String] = []
    @Published private(set) var loading = false

    func load(for role: EusoRole) async {
        let actions = VesselWriteRolePolicy.allowedActions(for: role)
        errors = []
        loading = true

        let needsPorts = actions.contains { action in
            [.publishFreightRate, .createVoyage, .createCargoManifest, .recordBunkerDelivery].contains(action)
        }
        let needsFleet = actions.contains { action in
            [.createVoyage, .recordBunkerDelivery].contains(action)
        }
        let needsVoyages = actions.contains { action in
            [.createCargoManifest, .recordBunkerDelivery].contains(action)
        }
        let needsShipments = actions.contains(.createCargoManifest)

        if needsPorts {
            do {
                ports = try await EusoTripAPI.shared.getVesselWritePorts()
            } catch {
                ports = []
                errors.append("Ports: \(error.localizedDescription)")
            }
        } else {
            ports = []
        }

        if needsFleet {
            do {
                vessels = try await EusoTripAPI.shared.getVesselWriteFleet().vessels
            } catch {
                vessels = []
                errors.append("Fleet: \(error.localizedDescription)")
            }
        } else {
            vessels = []
        }

        if needsVoyages {
            do {
                voyages = try await EusoTripAPI.shared.getVesselWriteVoyages()
            } catch {
                voyages = []
                errors.append("Voyages: \(error.localizedDescription)")
            }
        } else {
            voyages = []
        }

        if needsShipments {
            do {
                shipments = try await EusoTripAPI.shared.getVesselWriteShipments().shipments
            } catch {
                shipments = []
                errors.append("Shipments: \(error.localizedDescription)")
            }
        } else {
            shipments = []
        }

        if actions.contains(.registerContainer),
           [.vesselOperator, .portMaster, .terminal].contains(role) {
            do {
                containerInventory = try await EusoTripAPI.shared.getVesselContainerInventorySummary()
            } catch {
                containerInventory = nil
                errors.append("Container inventory: \(error.localizedDescription)")
            }
        } else {
            containerInventory = nil
        }

        loading = false
    }

    func readiness(for action: VesselWriteAction) -> String? {
        switch action {
        case .publishFreightRate:
            return ports.count >= 2 ? nil : "Two active ports are required."
        case .createVoyage:
            if vessels.isEmpty { return "A scoped vessel is required." }
            return ports.count >= 2 ? nil : "Two active ports are required."
        case .createCargoManifest:
            if voyages.isEmpty { return "A scoped voyage is required." }
            if shipments.isEmpty { return "A scoped vessel shipment is required." }
            return ports.count >= 2 ? nil : "Two active ports are required."
        case .recordBunkerDelivery:
            if vessels.isEmpty { return "A scoped vessel is required." }
            return ports.isEmpty ? "An active delivery port is required." : nil
        case .registerContainer:
            return nil
        }
    }
}

private struct VesselWriteReceipt {
    let action: VesselWriteAction
    let id: Int
    let idempotent: Bool
    let totalCost: String?
    let currency: String?
}

private struct VesselWriteAttempt {
    private var requestKey = Self.makeRequestKey()
    private var fingerprint: Data?

    mutating func key<Input: Encodable>(for input: Input) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let nextFingerprint = try encoder.encode(input)
        if let fingerprint, fingerprint != nextFingerprint {
            requestKey = Self.makeRequestKey()
        }
        fingerprint = nextFingerprint
        return requestKey
    }

    mutating func completed() {
        requestKey = Self.makeRequestKey()
        fingerprint = nil
    }

    private static func makeRequestKey() -> String {
        "ios-vessel-\(UUID().uuidString)"
    }
}

private enum VesselWriteFormError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        }
    }
}

private enum VesselWriteValidation {
    static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func instantString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func required(_ value: String, label: String, min: Int, max: Int) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= min, normalized.count <= max else {
            throw VesselWriteFormError.invalid("\(label) must contain \(min)–\(max) characters.")
        }
        return normalized
    }

    static func optional(_ value: String, label: String, max: Int, min: Int = 1) throws -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard normalized.count >= min, normalized.count <= max else {
            throw VesselWriteFormError.invalid("\(label) must contain \(min)–\(max) characters when supplied.")
        }
        return normalized
    }

    static func currency(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
            throw VesselWriteFormError.invalid("Currency must be a three-letter ISO 4217 code.")
        }
        return normalized
    }

    static func decimal(
        _ value: String,
        label: String,
        integerDigits: Int,
        positive: Bool
    ) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^\\d{1,\(integerDigits)}(\\.\\d{1,2})?$"
        guard normalized.range(of: pattern, options: .regularExpression) != nil,
              let number = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              positive ? number > 0 : number >= 0 else {
            let relation = positive ? "greater than zero" : "zero or greater"
            throw VesselWriteFormError.invalid("\(label) must be \(relation) with no more than two decimal places.")
        }
        return normalized
    }

    static func optionalDecimal(
        _ value: String,
        label: String,
        integerDigits: Int,
        positive: Bool = false
    ) throws -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return try decimal(normalized, label: label, integerDigits: integerDigits, positive: positive)
    }

    static func optionalPositiveInteger(
        _ value: String,
        label: String,
        maximum: Int? = nil
    ) throws -> Int? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard let number = Int(normalized), number > 0,
              maximum.map({ number <= $0 }) ?? true else {
            throw VesselWriteFormError.invalid("\(label) must be a positive whole number.")
        }
        return number
    }

    static func optionalNonNegativeInteger(_ value: String, label: String) throws -> Int? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard let number = Int(normalized), number >= 0, number <= Int(Int32.max) else {
            throw VesselWriteFormError.invalid("\(label) must be a non-negative whole number.")
        }
        return number
    }
}

private struct VesselFreightRateForm: View {
    let ports: [EusoTripAPI.VesselWritePort]
    let onPersisted: (VesselWriteReceipt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var originPortId: Int?
    @State private var destinationPortId: Int?
    @State private var containerSize = EusoTripAPI.VesselFreightContainerSize.fortyFoot
    @State private var ratePerUnit = ""
    @State private var currency = "USD"
    @State private var bafSurcharge = ""
    @State private var thcOrigin = ""
    @State private var thcDestination = ""
    @State private var peakSeasonSurcharge = ""
    @State private var effectiveDate = Date()
    @State private var hasExpiration = false
    @State private var expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var transitDays = ""
    @State private var serviceRoute = ""
    @State private var attempt = VesselWriteAttempt()
    @State private var submitting = false
    @State private var errorMessage: String?

    init(
        ports: [EusoTripAPI.VesselWritePort],
        onPersisted: @escaping (VesselWriteReceipt) -> Void
    ) {
        self.ports = ports
        self.onPersisted = onPersisted
        _originPortId = State(initialValue: ports.first?.id)
        _destinationPortId = State(initialValue: ports.dropFirst().first?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Lane") {
                    portPicker("Origin port", selection: $originPortId)
                    portPicker("Destination port", selection: $destinationPortId)
                    Picker("Container size", selection: $containerSize) {
                        ForEach(EusoTripAPI.VesselFreightContainerSize.allCases) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                    TextField("Service route", text: $serviceRoute)
                }
                Section("Rate") {
                    TextField("Rate per unit", text: $ratePerUnit).keyboardType(.decimalPad)
                    TextField("Currency", text: $currency).textInputAutocapitalization(.characters)
                    TextField("BAF surcharge", text: $bafSurcharge).keyboardType(.decimalPad)
                    TextField("Origin THC", text: $thcOrigin).keyboardType(.decimalPad)
                    TextField("Destination THC", text: $thcDestination).keyboardType(.decimalPad)
                    TextField("Peak-season surcharge", text: $peakSeasonSurcharge).keyboardType(.decimalPad)
                }
                Section("Validity") {
                    DatePicker("Effective date", selection: $effectiveDate, displayedComponents: .date)
                    Toggle("Set expiration date", isOn: $hasExpiration)
                    if hasExpiration {
                        DatePicker("Expiration date", selection: $expirationDate, displayedComponents: .date)
                    }
                    TextField("Transit days", text: $transitDays).keyboardType(.numberPad)
                }
                submitSection("Publish rate", submit: submit)
            }
            .navigationTitle("Publish freight rate")
            .toolbar { cancelToolbar }
        }
    }

    private func portPicker(_ title: String, selection: Binding<Int?>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ports) { port in
                Text(port.displayLabel).tag(Optional(port.id))
            }
        }
    }

    private func submit() async {
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        do {
            guard let originPortId, let destinationPortId, originPortId != destinationPortId else {
                throw VesselWriteFormError.invalid("Choose two different active ports.")
            }
            guard let transit = Int(transitDays), (1...365).contains(transit) else {
                throw VesselWriteFormError.invalid("Transit days must be between 1 and 365.")
            }
            if hasExpiration, expirationDate <= effectiveDate {
                throw VesselWriteFormError.invalid("Expiration date must follow the effective date.")
            }
            var input = EusoTripAPI.PublishVesselFreightRateInput(
                requestKey: "",
                originPortId: originPortId,
                destinationPortId: destinationPortId,
                containerSize: containerSize,
                ratePerUnit: try VesselWriteValidation.decimal(ratePerUnit, label: "Rate per unit", integerDigits: 8, positive: true),
                currency: try VesselWriteValidation.currency(currency),
                bafSurcharge: try VesselWriteValidation.optionalDecimal(bafSurcharge, label: "BAF surcharge", integerDigits: 6),
                thcOrigin: try VesselWriteValidation.optionalDecimal(thcOrigin, label: "Origin THC", integerDigits: 6),
                thcDestination: try VesselWriteValidation.optionalDecimal(thcDestination, label: "Destination THC", integerDigits: 6),
                peakSeasonSurcharge: try VesselWriteValidation.optionalDecimal(peakSeasonSurcharge, label: "Peak-season surcharge", integerDigits: 6),
                effectiveDate: VesselWriteValidation.dateString(from: effectiveDate),
                expirationDate: hasExpiration ? VesselWriteValidation.dateString(from: expirationDate) : nil,
                transitDays: transit,
                serviceRoute: try VesselWriteValidation.optional(serviceRoute, label: "Service route", max: 100)
            )
            input.requestKey = try attempt.key(for: input)
            let result = try await EusoTripAPI.shared.publishVesselFreightRate(input)
            attempt.completed()
            onPersisted(.init(action: .publishFreightRate, id: result.id, idempotent: result.idempotent, totalCost: nil, currency: nil))
        } catch {
            errorMessage = vesselWriteFailureMessage(error)
        }
    }

    @ToolbarContentBuilder
    private var cancelToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
    }

    @ViewBuilder
    private func submitSection(_ title: String, submit: @escaping () async -> Void) -> some View {
        Section {
            if let errorMessage { Text(errorMessage).foregroundStyle(Brand.danger) }
            Button { Task { await submit() } } label: {
                if submitting { ProgressView().frame(maxWidth: .infinity) }
                else { Text(title).frame(maxWidth: .infinity) }
            }
            .disabled(submitting)
        }
    }
}

private struct VesselVoyageForm: View {
    let ports: [EusoTripAPI.VesselWritePort]
    let vessels: [EusoTripAPI.VesselWriteFleetRow]
    let onPersisted: (VesselWriteReceipt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vesselId: Int?
    @State private var voyageNumber = ""
    @State private var serviceRoute = ""
    @State private var departurePortId: Int?
    @State private var arrivalPortId: Int?
    @State private var scheduledDeparture = Date()
    @State private var scheduledArrival = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    @State private var captainId = ""
    @State private var attempt = VesselWriteAttempt()
    @State private var submitting = false
    @State private var errorMessage: String?

    init(
        ports: [EusoTripAPI.VesselWritePort],
        vessels: [EusoTripAPI.VesselWriteFleetRow],
        onPersisted: @escaping (VesselWriteReceipt) -> Void
    ) {
        self.ports = ports
        self.vessels = vessels
        self.onPersisted = onPersisted
        _vesselId = State(initialValue: vessels.first?.id)
        _departurePortId = State(initialValue: ports.first?.id)
        _arrivalPortId = State(initialValue: ports.dropFirst().first?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Voyage") {
                    Picker("Vessel", selection: $vesselId) {
                        ForEach(vessels) { vessel in Text(vessel.displayLabel).tag(Optional(vessel.id)) }
                    }
                    TextField("Voyage number", text: $voyageNumber)
                    TextField("Service route", text: $serviceRoute)
                    TextField("Captain user ID", text: $captainId).keyboardType(.numberPad)
                }
                Section("Route") {
                    portPicker("Departure port", selection: $departurePortId)
                    portPicker("Arrival port", selection: $arrivalPortId)
                    DatePicker("Scheduled departure", selection: $scheduledDeparture)
                    DatePicker("Scheduled arrival", selection: $scheduledArrival)
                }
                formSubmitSection(title: "Create voyage", submitting: submitting, errorMessage: errorMessage, submit: submit)
            }
            .navigationTitle("Create voyage")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func portPicker(_ title: String, selection: Binding<Int?>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ports) { port in Text(port.displayLabel).tag(Optional(port.id)) }
        }
    }

    private func submit() async {
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        do {
            guard let vesselId else { throw VesselWriteFormError.invalid("Choose a scoped vessel.") }
            guard let departurePortId, let arrivalPortId, departurePortId != arrivalPortId else {
                throw VesselWriteFormError.invalid("Choose two different active ports.")
            }
            guard scheduledArrival > scheduledDeparture else {
                throw VesselWriteFormError.invalid("Scheduled arrival must follow departure.")
            }
            var input = EusoTripAPI.CreateVesselVoyageInput(
                requestKey: "",
                vesselId: vesselId,
                voyageNumber: try VesselWriteValidation.required(voyageNumber, label: "Voyage number", min: 1, max: 50),
                serviceRoute: try VesselWriteValidation.optional(serviceRoute, label: "Service route", max: 100),
                departurePortId: departurePortId,
                arrivalPortId: arrivalPortId,
                scheduledDeparture: VesselWriteValidation.instantString(from: scheduledDeparture),
                scheduledArrival: VesselWriteValidation.instantString(from: scheduledArrival),
                captainId: try VesselWriteValidation.optionalPositiveInteger(captainId, label: "Captain user ID")
            )
            input.requestKey = try attempt.key(for: input)
            let result = try await EusoTripAPI.shared.createVesselVoyage(input)
            attempt.completed()
            onPersisted(.init(action: .createVoyage, id: result.id, idempotent: result.idempotent, totalCost: nil, currency: nil))
        } catch {
            errorMessage = vesselWriteFailureMessage(error)
        }
    }
}

private struct VesselCargoManifestForm: View {
    let ports: [EusoTripAPI.VesselWritePort]
    let voyages: [EusoTripAPI.VesselWriteVoyageRow]
    let shipments: [EusoTripAPI.VesselWriteShipmentRow]
    let onPersisted: (VesselWriteReceipt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var voyageId: Int?
    @State private var shipmentId: Int?
    @State private var containerNumber = ""
    @State private var sealNumber = ""
    @State private var cargoDescription = ""
    @State private var packageCount = ""
    @State private var grossWeightKg = ""
    @State private var volumeCBM = ""
    @State private var loadPortId: Int?
    @State private var dischargePortId: Int?
    @State private var hazmatClass = ""
    @State private var temperatureRequired = ""
    @State private var stowagePosition = ""
    @State private var attempt = VesselWriteAttempt()
    @State private var submitting = false
    @State private var errorMessage: String?

    init(
        ports: [EusoTripAPI.VesselWritePort],
        voyages: [EusoTripAPI.VesselWriteVoyageRow],
        shipments: [EusoTripAPI.VesselWriteShipmentRow],
        onPersisted: @escaping (VesselWriteReceipt) -> Void
    ) {
        self.ports = ports
        self.voyages = voyages
        self.shipments = shipments
        self.onPersisted = onPersisted
        let firstVoyage = voyages.first
        _voyageId = State(initialValue: firstVoyage?.id)
        _shipmentId = State(initialValue: shipments.first(where: {
            $0.vesselId == nil || $0.vesselId == firstVoyage?.vesselId
        })?.id)
        _loadPortId = State(initialValue: ports.first?.id)
        _dischargePortId = State(initialValue: ports.dropFirst().first?.id)
    }

    private var selectedVoyage: EusoTripAPI.VesselWriteVoyageRow? {
        voyages.first { $0.id == voyageId }
    }

    private var compatibleShipments: [EusoTripAPI.VesselWriteShipmentRow] {
        guard let vesselId = selectedVoyage?.vesselId else { return shipments }
        return shipments.filter { $0.vesselId == nil || $0.vesselId == vesselId }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Records") {
                    Picker("Voyage", selection: $voyageId) {
                        ForEach(voyages) { voyage in Text(voyage.displayLabel).tag(Optional(voyage.id)) }
                    }
                    Picker("Shipment", selection: $shipmentId) {
                        ForEach(compatibleShipments) { shipment in
                            Text(shipment.displayLabel).tag(Optional(shipment.id))
                        }
                    }
                }
                Section("Cargo") {
                    TextField("Cargo description", text: $cargoDescription, axis: .vertical)
                    TextField("Container number", text: $containerNumber).textInputAutocapitalization(.characters)
                    TextField("Seal number", text: $sealNumber)
                    TextField("Package count", text: $packageCount).keyboardType(.numberPad)
                    TextField("Gross weight (kg)", text: $grossWeightKg).keyboardType(.decimalPad)
                    TextField("Volume (CBM)", text: $volumeCBM).keyboardType(.decimalPad)
                }
                Section("Ports") {
                    portPicker("Load port", selection: $loadPortId)
                    portPicker("Discharge port", selection: $dischargePortId)
                }
                Section("Handling") {
                    TextField("Hazmat class", text: $hazmatClass)
                    TextField("Required temperature", text: $temperatureRequired).keyboardType(.numbersAndPunctuation)
                    TextField("Stowage position", text: $stowagePosition)
                }
                formSubmitSection(title: "Create manifest", submitting: submitting, errorMessage: errorMessage, submit: submit)
            }
            .navigationTitle("Create cargo manifest")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: voyageId) { _ in
                if !compatibleShipments.contains(where: { $0.id == shipmentId }) {
                    shipmentId = compatibleShipments.first?.id
                }
            }
        }
    }

    private func portPicker(_ title: String, selection: Binding<Int?>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ports) { port in Text(port.displayLabel).tag(Optional(port.id)) }
        }
    }

    private func submit() async {
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        do {
            guard let voyageId, let shipmentId else {
                throw VesselWriteFormError.invalid("Choose a compatible voyage and shipment.")
            }
            guard let loadPortId, let dischargePortId, loadPortId != dischargePortId else {
                throw VesselWriteFormError.invalid("Choose two different active ports.")
            }
            let normalizedContainer = try VesselWriteValidation.optional(containerNumber.uppercased(), label: "Container number", max: 20, min: 4)
            let normalizedTemperature = temperatureRequired.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedTemperature.isEmpty {
                let absoluteZero = Decimal(-27_315) / Decimal(100)
                guard normalizedTemperature.range(of: "^-?\\d{1,4}(\\.\\d{1,2})?$", options: .regularExpression) != nil,
                      let value = Decimal(string: normalizedTemperature, locale: Locale(identifier: "en_US_POSIX")),
                      value >= absoluteZero else {
                    throw VesselWriteFormError.invalid("Required temperature must be at or above -273.15 with no more than two decimal places.")
                }
            }
            var input = EusoTripAPI.CreateVesselCargoManifestInput(
                requestKey: "",
                voyageId: voyageId,
                shipmentId: shipmentId,
                containerNumber: normalizedContainer,
                sealNumber: try VesselWriteValidation.optional(sealNumber, label: "Seal number", max: 50),
                cargoDescription: try VesselWriteValidation.required(cargoDescription, label: "Cargo description", min: 3, max: 4_000),
                packageCount: try VesselWriteValidation.optionalNonNegativeInteger(packageCount, label: "Package count"),
                grossWeightKg: try VesselWriteValidation.decimal(grossWeightKg, label: "Gross weight", integerDigits: 10, positive: true),
                volumeCBM: try VesselWriteValidation.optionalDecimal(volumeCBM, label: "Volume", integerDigits: 8),
                loadPortId: loadPortId,
                dischargePortId: dischargePortId,
                hazmatClass: try VesselWriteValidation.optional(hazmatClass, label: "Hazmat class", max: 10),
                temperatureRequired: normalizedTemperature.isEmpty ? nil : normalizedTemperature,
                stowagePosition: try VesselWriteValidation.optional(stowagePosition, label: "Stowage position", max: 20)
            )
            input.requestKey = try attempt.key(for: input)
            let result = try await EusoTripAPI.shared.createVesselCargoManifest(input)
            attempt.completed()
            onPersisted(.init(action: .createCargoManifest, id: result.id, idempotent: result.idempotent, totalCost: nil, currency: nil))
        } catch {
            errorMessage = vesselWriteFailureMessage(error)
        }
    }
}

private struct VesselBunkerDeliveryForm: View {
    let role: EusoRole?
    let ports: [EusoTripAPI.VesselWritePort]
    let vessels: [EusoTripAPI.VesselWriteFleetRow]
    let voyages: [EusoTripAPI.VesselWriteVoyageRow]
    let onPersisted: (VesselWriteReceipt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vesselId: Int?
    @State private var includeVoyage: Bool
    @State private var voyageId: Int?
    @State private var portId: Int?
    @State private var fuelType = EusoTripAPI.VesselFuelType.vlsfo
    @State private var quantityMT = ""
    @State private var pricePerMT = ""
    @State private var currency = "USD"
    @State private var supplier = ""
    @State private var deliveryDate = Date()
    @State private var bunkerDeliveryNote = ""
    @State private var sulphurContent = ""
    @State private var attempt = VesselWriteAttempt()
    @State private var submitting = false
    @State private var errorMessage: String?

    init(
        role: EusoRole?,
        ports: [EusoTripAPI.VesselWritePort],
        vessels: [EusoTripAPI.VesselWriteFleetRow],
        voyages: [EusoTripAPI.VesselWriteVoyageRow],
        onPersisted: @escaping (VesselWriteReceipt) -> Void
    ) {
        self.role = role
        self.ports = ports
        self.vessels = vessels
        self.voyages = voyages
        self.onPersisted = onPersisted
        let firstVessel = vessels.first
        _vesselId = State(initialValue: firstVessel?.id)
        _includeVoyage = State(initialValue: role == .shipCaptain)
        _voyageId = State(initialValue: voyages.first(where: { $0.vesselId == firstVessel?.id })?.id)
        _portId = State(initialValue: ports.first?.id)
    }

    private var compatibleVoyages: [EusoTripAPI.VesselWriteVoyageRow] {
        guard let vesselId else { return [] }
        return voyages.filter { $0.vesselId == vesselId }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Delivery") {
                    Picker("Vessel", selection: $vesselId) {
                        ForEach(vessels) { vessel in Text(vessel.displayLabel).tag(Optional(vessel.id)) }
                    }
                    Toggle("Link voyage", isOn: $includeVoyage)
                        .disabled(role == .shipCaptain)
                    if includeVoyage {
                        Picker("Voyage", selection: $voyageId) {
                            ForEach(compatibleVoyages) { voyage in Text(voyage.displayLabel).tag(Optional(voyage.id)) }
                        }
                    }
                    Picker("Delivery port", selection: $portId) {
                        ForEach(ports) { port in Text(port.displayLabel).tag(Optional(port.id)) }
                    }
                    Picker("Fuel type", selection: $fuelType) {
                        ForEach(EusoTripAPI.VesselFuelType.allCases) { fuel in
                            Text(fuel.rawValue.uppercased()).tag(fuel)
                        }
                    }
                    DatePicker("Delivery date", selection: $deliveryDate, in: ...Date().addingTimeInterval(300))
                }
                Section("Commercial evidence") {
                    TextField("Quantity (MT)", text: $quantityMT).keyboardType(.decimalPad)
                    TextField("Price per MT", text: $pricePerMT).keyboardType(.decimalPad)
                    TextField("Currency", text: $currency).textInputAutocapitalization(.characters)
                    TextField("Supplier", text: $supplier)
                    TextField("Bunker delivery note", text: $bunkerDeliveryNote)
                    TextField("Sulphur content", text: $sulphurContent).keyboardType(.decimalPad)
                }
                formSubmitSection(title: "Record delivery", submitting: submitting, errorMessage: errorMessage, submit: submit)
            }
            .navigationTitle("Bunker delivery")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: vesselId) { _ in
                if !compatibleVoyages.contains(where: { $0.id == voyageId }) {
                    voyageId = compatibleVoyages.first?.id
                }
            }
        }
    }

    private func submit() async {
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        do {
            guard let vesselId, let portId else {
                throw VesselWriteFormError.invalid("Choose a scoped vessel and active port.")
            }
            if role == .shipCaptain, voyageId == nil {
                throw VesselWriteFormError.invalid("A voyage is required for a captain-recorded delivery.")
            }
            if deliveryDate > Date().addingTimeInterval(300) {
                throw VesselWriteFormError.invalid("A bunker delivery cannot be future-dated.")
            }
            let normalizedCurrency = try VesselWriteValidation.currency(currency)
            let sulphur = sulphurContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sulphur.isEmpty,
               sulphur.range(of: "^\\d{1,2}(\\.\\d{1,2})?$", options: .regularExpression) == nil {
                throw VesselWriteFormError.invalid("Sulphur content must fit the supported percentage format.")
            }
            var input = EusoTripAPI.RecordVesselBunkerDeliveryInput(
                requestKey: "",
                vesselId: vesselId,
                voyageId: includeVoyage ? voyageId : nil,
                portId: portId,
                fuelType: fuelType,
                quantityMT: try VesselWriteValidation.decimal(quantityMT, label: "Quantity", integerDigits: 8, positive: true),
                pricePerMT: try VesselWriteValidation.decimal(pricePerMT, label: "Price per MT", integerDigits: 8, positive: true),
                currency: normalizedCurrency,
                supplier: try VesselWriteValidation.required(supplier, label: "Supplier", min: 2, max: 255),
                deliveryDate: VesselWriteValidation.instantString(from: deliveryDate),
                bunkerDeliveryNote: try VesselWriteValidation.required(bunkerDeliveryNote, label: "Bunker delivery note", min: 2, max: 50),
                sulphurContent: sulphur.isEmpty ? nil : sulphur
            )
            input.requestKey = try attempt.key(for: input)
            let result = try await EusoTripAPI.shared.recordVesselBunkerDelivery(input)
            attempt.completed()
            onPersisted(.init(action: .recordBunkerDelivery, id: result.id, idempotent: result.idempotent, totalCost: result.totalCost, currency: normalizedCurrency))
        } catch {
            errorMessage = vesselWriteFailureMessage(error)
        }
    }
}

private struct IntermodalContainerRegistrationForm: View {
    let onPersisted: (VesselWriteReceipt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var containerNumber = ""
    @State private var size = EusoTripAPI.VesselInventoryContainerSize.fortyFoot
    @State private var type = EusoTripAPI.VesselInventoryContainerType.standard
    @State private var status = EusoTripAPI.VesselInventoryStatus.empty
    @State private var chassisId = ""
    @State private var locationId = ""
    @State private var spotId = ""
    @State private var steamshipLine = ""
    @State private var bookingNumber = ""
    @State private var sealNumber = ""
    @State private var weight = ""
    @State private var hasLastFreeDay = false
    @State private var lastFreeDay = Date()
    @State private var demurrageRate = ""
    @State private var hasArrivalTime = false
    @State private var arrivalTime = Date()
    @State private var hasDepartureTime = false
    @State private var departureTime = Date()
    @State private var notes = ""
    @State private var attempt = VesselWriteAttempt()
    @State private var submitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Equipment") {
                    TextField("Container number", text: $containerNumber).textInputAutocapitalization(.characters)
                    Picker("Size", selection: $size) {
                        ForEach(EusoTripAPI.VesselInventoryContainerSize.allCases) { value in Text(value.rawValue).tag(value) }
                    }
                    Picker("Type", selection: $type) {
                        ForEach(EusoTripAPI.VesselInventoryContainerType.allCases) { value in Text(label(value.rawValue)).tag(value) }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(EusoTripAPI.VesselInventoryStatus.allCases) { value in Text(label(value.rawValue)).tag(value) }
                    }
                    TextField("Chassis ID", text: $chassisId).keyboardType(.numberPad)
                }
                Section("Location and booking") {
                    TextField("Location ID", text: $locationId)
                    TextField("Spot ID", text: $spotId)
                    TextField("Steamship line", text: $steamshipLine)
                    TextField("Booking number", text: $bookingNumber)
                    TextField("Seal number", text: $sealNumber)
                    TextField("Weight", text: $weight).keyboardType(.numberPad)
                }
                Section("Timing and charges") {
                    Toggle("Set last free day", isOn: $hasLastFreeDay)
                    if hasLastFreeDay { DatePicker("Last free day", selection: $lastFreeDay) }
                    TextField("Demurrage rate", text: $demurrageRate).keyboardType(.decimalPad)
                    Toggle("Set arrival time", isOn: $hasArrivalTime)
                    if hasArrivalTime { DatePicker("Arrival", selection: $arrivalTime) }
                    Toggle("Set departure time", isOn: $hasDepartureTime)
                    if hasDepartureTime { DatePicker("Departure", selection: $departureTime) }
                }
                Section("Notes") {
                    TextField("Operational notes", text: $notes, axis: .vertical)
                }
                formSubmitSection(title: "Register container", submitting: submitting, errorMessage: errorMessage, submit: submit)
            }
            .navigationTitle("Register container")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func label(_ rawValue: String) -> String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func submit() async {
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        do {
            let number = try VesselWriteValidation.required(containerNumber.uppercased(), label: "Container number", min: 4, max: 20)
            guard number.range(of: "^[A-Z0-9-]+$", options: .regularExpression) != nil else {
                throw VesselWriteFormError.invalid("Container number can contain only letters, numbers, and hyphens.")
            }
            if hasArrivalTime, hasDepartureTime, departureTime < arrivalTime {
                throw VesselWriteFormError.invalid("Container departure cannot precede arrival.")
            }
            var input = EusoTripAPI.RegisterIntermodalContainerInput(
                requestKey: "",
                containerNumber: number,
                size: size,
                type: type,
                status: status,
                chassisId: try VesselWriteValidation.optionalPositiveInteger(chassisId, label: "Chassis ID"),
                locationId: try VesselWriteValidation.optional(locationId, label: "Location ID", max: 50),
                spotId: try VesselWriteValidation.optional(spotId, label: "Spot ID", max: 20),
                steamshipLine: try VesselWriteValidation.optional(steamshipLine, label: "Steamship line", max: 100),
                bookingNumber: try VesselWriteValidation.optional(bookingNumber, label: "Booking number", max: 50),
                sealNumber: try VesselWriteValidation.optional(sealNumber, label: "Seal number", max: 50),
                weight: try VesselWriteValidation.optionalPositiveInteger(weight, label: "Weight", maximum: Int(Int32.max)),
                lastFreeDay: hasLastFreeDay ? VesselWriteValidation.instantString(from: lastFreeDay) : nil,
                demurrageRate: try VesselWriteValidation.optionalDecimal(demurrageRate, label: "Demurrage rate", integerDigits: 8),
                arrivalTime: hasArrivalTime ? VesselWriteValidation.instantString(from: arrivalTime) : nil,
                departureTime: hasDepartureTime ? VesselWriteValidation.instantString(from: departureTime) : nil,
                notes: try VesselWriteValidation.optional(notes, label: "Notes", max: 4_000)
            )
            input.requestKey = try attempt.key(for: input)
            let result = try await EusoTripAPI.shared.registerIntermodalContainer(input)
            attempt.completed()
            onPersisted(.init(action: .registerContainer, id: result.id, idempotent: result.idempotent, totalCost: nil, currency: nil))
        } catch {
            errorMessage = vesselWriteFailureMessage(error)
        }
    }
}

@ViewBuilder
private func formSubmitSection(
    title: String,
    submitting: Bool,
    errorMessage: String?,
    submit: @escaping () async -> Void
) -> some View {
    Section {
        if let errorMessage {
            Text(errorMessage).foregroundStyle(Brand.danger)
        }
        Button { Task { await submit() } } label: {
            if submitting {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text(title).frame(maxWidth: .infinity)
            }
        }
        .disabled(submitting)
    }
}

private func vesselWriteFailureMessage(_ error: Error) -> String {
    if let formError = error as? VesselWriteFormError {
        return formError.errorDescription ?? "Check the highlighted fields and try again."
    }
    if let contractError = error as? VesselWriteContractError {
        return contractError.errorDescription ?? "The vessel operation was not confirmed."
    }
    guard let apiError = error as? EusoTripAPIError else {
        return "The vessel operation could not be completed. Refresh and try again."
    }
    switch apiError {
    case .unauthenticated:
        return "Sign in again to complete this vessel operation."
    case .forbidden:
        return "This account is not permitted to complete that vessel operation."
    case .httpStatus(let code, _):
        return code == 401 || code == 403
            ? "Sign in again or confirm your vessel-operation permissions."
            : "The vessel operation was not confirmed (error \(code)). Refresh before retrying."
    case .decodingFailed, .empty:
        return "The operation may have completed, but its confirmation could not be verified. Refresh before retrying."
    case .queuedForOfflineReplay:
        return "This vessel operation needs an internet connection. Reconnect and try again."
    case .notConfigured, .badURL, .trpcError:
        return "The vessel operation was not accepted. Refresh its source records and try again."
    }
}
