//
//  204G_ShipperHHGChainOfCustody.swift
//  EusoTrip 2027 - Shipper household-goods custody.
//
//  Custody transfers are persisted by load. A descriptive household-goods
//  inventory is not; this surface keeps those two facts separate.
//

import SwiftUI

private struct HHGComplianceRule204G: Decodable, Identifiable {
    let id: String
    let regulation: String
    let description: String
    let severity: String
    let autoCheck: Bool
}

private struct HHGDocumentRequirement204G: Decodable, Identifiable {
    let id: String
    let name: String
    let required: Bool
    let category: String
    let description: String
}

private struct HHGEnvironmentalRequirement204G: Decodable, Identifiable {
    let category: String
    let id: String
    let regulation: String
    let title: String
    let description: String
    let severity: String
}

private struct HHGCompliance204G: Decodable {
    let verticalId: String
    let verticalName: String
    let baseRules: [HHGComplianceRule204G]
    let environmentalCompliance: [HHGEnvironmentalRequirement204G]
    let requiredDocuments: [HHGDocumentRequirement204G]
    let specialRequirements: [String]
}

private struct CustodyTransfer204G: Decodable, Identifiable {
    let id: Int
    let sequenceNumber: Int
    let transportMode: String
    let fromPartyRole: String
    let fromPartyName: String?
    let toPartyRole: String
    let toPartyName: String?
    let transferredAt: String
    let locationDescription: String?
    let cargoCondition: String?
    let sealNumbers: [String]?
    let sealIntact: Bool?
    let photoUrls: [String]?
    let notes: String?
}

@MainActor
private final class HHGStore204G: ObservableObject {
    @Published private(set) var load: LoadsAPI.LoadDetail?
    @Published private(set) var compliance: HHGCompliance204G?
    @Published private(set) var custody: [CustodyTransfer204G] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

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
            custody = []
            errorMessage = "Open household-goods custody from a load to see its records."
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            guard let resolved = try await api.loads.getDetail(id: loadId) else {
                load = nil
                compliance = nil
                custody = []
                errorMessage = "This load is no longer available. Return to Loads and choose another one."
                return
            }
            load = resolved

            var failures: [String] = []
            struct VerticalInput: Encodable { let verticalId: String }
            do {
                compliance = try await api.query(
                    "industryVerticals.getComplianceRequirements",
                    input: VerticalInput(verticalId: "moving_household")
                )
            } catch {
                compliance = nil
                failures.append(error.eusoUserCopy)
            }

            guard resolved.numericId > 0 else {
                custody = []
                failures.append("This load has no numeric record identifier, so its custody history cannot be matched.")
                errorMessage = failures.joined(separator: " ")
                return
            }

            struct CustodyInput: Encodable { let loadId: Int }
            do {
                custody = try await api.query(
                    "loadLifecycle.getCustodyChain",
                    input: CustodyInput(loadId: resolved.numericId)
                )
            } catch {
                custody = []
                failures.append(error.eusoUserCopy)
            }
            errorMessage = failures.isEmpty ? nil : failures.joined(separator: " ")
        } catch {
            load = nil
            compliance = nil
            custody = []
            errorMessage = error.eusoUserCopy
        }
    }
}

struct ShipperHHGChainOfCustody: View {
    let loadId: String
    @StateObject private var store: HHGStore204G
    @Environment(\.palette) private var palette

    init(loadId: String = "") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: HHGStore204G(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(
                    eyebrow: "SHIPPER · HOUSEHOLD GOODS",
                    idText: store.load?.loadNumber ?? loadId,
                    title: "Chain of custody"
                )

                if let errorMessage = store.errorMessage {
                    DegradedNote(text: errorMessage)
                        .padding(.top, Space.s3)
                }

                if store.isLoading, store.load == nil {
                    ProgressView("Loading custody records")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s6)
                }

                if let load = store.load {
                    loadCard(load)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)

                    inventoryAvailability
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s3)

                    SectionLabel("RECORDED CUSTODY TRANSFERS")
                        .padding(.top, Space.s5)
                    custodyList
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)
                }

                if let compliance = store.compliance {
                    SectionLabel(compliance.verticalName.uppercased())
                        .padding(.top, Space.s5)
                    complianceRules(compliance.baseRules)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    SectionLabel("REQUIRED DOCUMENTS")
                        .padding(.top, Space.s5)
                    documentRequirements(compliance.requiredDocuments)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    if !compliance.environmentalCompliance.isEmpty {
                        SectionLabel("ADDITIONAL REQUIREMENTS")
                            .padding(.top, Space.s5)
                        environmentalRequirements(compliance.environmentalCompliance)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)
                    }
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
    }

    private func loadCard(_ load: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                AddendaIconChip(systemImage: "shippingbox.and.arrow.backward.fill", tint: Brand.rail)
                VStack(alignment: .leading, spacing: 4) {
                    Text(load.commodityName ?? load.commodity ?? "Household goods")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text(load.laneDisplay)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                AddendaChip(text: load.status.replacingOccurrences(of: "_", with: " ").uppercased(), color: Brand.info)
            }
            Divider().overlay(palette.borderFaint)
            factRow("WEIGHT", load.weightDisplay)
            factRow("MODE", (load.transportMode ?? "Not recorded").uppercased())
            factRow("CUSTODY EVENTS", "\(store.custody.count)")
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private var inventoryAvailability: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("Descriptive inventory not recorded")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text("Custody transfers can prove who received the shipment, when, where, its recorded condition, seals, and evidence. The current load contract has no itemized household-goods inventory or declared-value record, so EusoTrip cannot show item counts or inventory completion.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    @ViewBuilder
    private var custodyList: some View {
        if store.custody.isEmpty {
            emptyPanel(
                icon: "arrow.left.arrow.right",
                title: "No custody transfers recorded",
                message: "No party handoff has been persisted for this load."
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(store.custody.enumerated()), id: \.element.id) { index, transfer in
                    custodyRow(transfer)
                    if index < store.custody.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.leading, 56)
                    }
                }
            }
            .addendaPanel(palette)
        }
    }

    private func custodyRow(_ transfer: CustodyTransfer204G) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            AddendaIconChip(systemImage: "person.2.fill", tint: conditionColor(transfer.cargoCondition))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(party(transfer.fromPartyName, role: transfer.fromPartyRole)) → \(party(transfer.toPartyName, role: transfer.toPartyRole))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(formatDate(transfer.transferredAt))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                if let location = nonEmpty(transfer.locationDescription) {
                    Text(location)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                HStack(spacing: Space.s2) {
                    if let condition = transfer.cargoCondition {
                        AddendaChip(text: condition.replacingOccurrences(of: "_", with: " ").uppercased(), color: conditionColor(condition))
                    }
                    if let seals = transfer.sealNumbers, !seals.isEmpty {
                        AddendaChip(
                            text: "\(seals.count) SEAL\(seals.count == 1 ? "" : "S")",
                            color: transfer.sealIntact == false ? Brand.warning : Brand.success
                        )
                    }
                    if let photos = transfer.photoUrls, !photos.isEmpty {
                        AddendaChip(text: "\(photos.count) PHOTO\(photos.count == 1 ? "" : "S")", color: Brand.info)
                    }
                }
            }
            Spacer(minLength: 0)
            Text("#\(transfer.sequenceNumber)")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
    }

    private func complianceRules(_ rules: [HHGComplianceRule204G]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                requirementRow(
                    title: rule.regulation,
                    description: rule.description,
                    detail: rule.autoCheck ? "AUTOMATED FIELD CHECK AVAILABLE" : nil,
                    tint: severityColor(rule.severity)
                )
                if index < rules.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, 56)
                }
            }
        }
        .addendaPanel(palette)
    }

    private func documentRequirements(_ documents: [HHGDocumentRequirement204G]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                requirementRow(
                    title: document.name,
                    description: document.description,
                    detail: document.required ? "REQUIRED" : "CONDITIONAL",
                    tint: document.required ? Brand.warning : Brand.info
                )
                if index < documents.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, 56)
                }
            }
        }
        .addendaPanel(palette)
    }

    private func environmentalRequirements(_ requirements: [HHGEnvironmentalRequirement204G]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(requirements.enumerated()), id: \.element.id) { index, requirement in
                requirementRow(
                    title: requirement.title,
                    description: requirement.description,
                    detail: requirement.regulation,
                    tint: severityColor(requirement.severity)
                )
                if index < requirements.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, 56)
                }
            }
        }
        .addendaPanel(palette)
    }

    private func requirementRow(title: String, description: String, detail: String?, tint: Color) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            AddendaIconChip(systemImage: "doc.text.magnifyingglass", tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(description)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(EType.mono(.micro))
                        .foregroundStyle(tint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
    }

    private func emptyPanel(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(EType.title).foregroundStyle(palette.textPrimary)
                Text(message)
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

    private func party(_ name: String?, role: String) -> String {
        nonEmpty(name) ?? role.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func formatDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func conditionColor(_ condition: String?) -> Color {
        switch condition?.lowercased() {
        case "good": return Brand.success
        case "damaged", "contaminated", "refused": return Brand.warning
        default: return Brand.info
        }
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "critical": return Brand.hazmat
        case "high": return Brand.warning
        default: return Brand.info
        }
    }
}

#Preview("204G · HHG custody · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperHHGChainOfCustody()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("204G · HHG custody · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperHHGChainOfCustody()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
