//
//  430_IndustryVerticals.swift
//  EusoTrip - Shipper industry workflow registry.
//

import SwiftUI

private struct IndustryCatalogSector: Decodable, Identifiable {
    let sectorId: String
    let displayName: String
    let iconName: String
    let summary: String
    let selectionStrategy: String
    let ruleSet: IndustryCatalogRuleSet

    var id: String { sectorId }
}

private struct IndustryCatalogRuleSet: Decodable {
    let id: Int
    let version: Int
    let workflowOptions: [IndustryCatalogWorkflow]
    let applicableModes: [String]
    let documentRules: [IndustryCatalogDocumentRule]
    let regulatoryRules: [IndustryCatalogRegulatoryRule]
    let accessorialAllowList: [String]
    let effectiveFrom: String
    let effectiveUntil: String?
    let sources: [IndustryCatalogSource]
}

private struct IndustryCatalogWorkflow: Decodable, Identifiable {
    let workflowId: String
    let label: String
    let appliesWhen: String
    let safeDefaults: IndustryCatalogDefaults

    var id: String { workflowId }
}

private struct IndustryCatalogDefaults: Decodable {
    let cargoType: String?
    let trailerCode: String?
    let requiredEndorsements: [String]?
    let specialEquipment: [String]?
    let hazmatAuthRequired: Bool?
    let preCoolRequired: Bool?
    let continuousMonitoring: Bool?
}

private struct IndustryCatalogDocumentRule: Decodable, Identifiable {
    let documentType: String
    let requiredWhen: String
    let blockingAt: String

    var id: String { "\(documentType)|\(requiredWhen)|\(blockingAt)" }
}

private struct IndustryCatalogRegulatoryRule: Decodable, Identifiable {
    let ruleId: String
    let title: String
    let authority: String
    let appliesToModes: [String]
    let appliesToCountries: [String]
    let appliesWhen: String
    let requirement: String
    let blockingWhenMissing: Bool
    let sourceKey: String

    var id: String { ruleId }
}

private struct IndustryCatalogSource: Decodable, Identifiable {
    let sourceKey: String
    let authority: String
    let title: String
    let sourceUrl: String
    let verificationStatus: String
    let checkedAt: String
    let validUntil: String

    var id: String { sourceKey }
}

struct IndustryVerticalsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            IndustryVerticalsBody()
        } nav: {
            shipperLifecycleNav()
        }
    }
}

private struct IndustryVerticalsBody: View {
    @Environment(\.palette) private var palette
    @State private var catalog: [IndustryCatalogSector] = []
    @State private var selectedSector: IndustryCatalogSector?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
        }
        .eusoRefreshable { await loadCatalog() }
        .task { await loadCatalog() }
        .sheet(item: $selectedSector) { sector in
            IndustryVerticalDetail(
                sector: sector,
                onUseWorkflow: openPostLoad,
                onCheckFacilities: openFacilityFit
            )
            .environment(\.palette, palette)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && catalog.isEmpty {
            LifecycleCard {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading current industry rules")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                }
            }
        } else if let errorMessage, catalog.isEmpty {
            LifecycleCard(accentDanger: true) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Brand.danger)
                    Text(errorMessage)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                Button {
                    Task { await loadCatalog() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        } else if catalog.isEmpty {
            LifecycleCard {
                Text("No active industry rule sets are available.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        } else {
            ForEach(catalog) { sector in
                Button {
                    selectedSector = sector
                } label: {
                    LifecycleCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: sector.iconName)
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundStyle(LinearGradient.diagonal)
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(sector.displayName)
                                    .font(EType.bodyStrong)
                                    .foregroundStyle(palette.textPrimary)
                                Text(sector.summary)
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 5) {
                                    statusChip("\(sector.ruleSet.workflowOptions.count) workflows")
                                    statusChip("Rules v\(sector.ruleSet.version)")
                                    statusChip("\(sector.ruleSet.sources.count) sources")
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette.textTertiary)
                                .padding(.top, 5)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func statusChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(palette.tintNeutral)
            .clipShape(Capsule())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · INDUSTRY VERTICALS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Vertical workflows")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Versioned operating rules, workflow fit, source evidence, and facility compatibility.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor
    private func loadCatalog() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let rows: [IndustryCatalogSector] = try await EusoTripAPI.shared.queryNoInput(
                "industryVerticals.catalog"
            )
            catalog = rows
        } catch {
            errorMessage = (error as? EusoTripAPIError)?.errorDescription
                ?? error.localizedDescription
        }
        isLoading = false
    }

    private func openPostLoad(_ handoff: IndustryWorkflowHandoff) {
        selectedSector = nil
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap,
                object: nil,
                userInfo: [
                    "screenId": "250",
                    "industryWorkflow": handoff,
                ]
            )
        }
    }

    private func openFacilityFit(_ product: String) {
        selectedSector = nil
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap,
                object: nil,
                userInfo: [
                    "screenId": "425",
                    "product": product,
                ]
            )
        }
    }
}

private struct IndustryVerticalDetail: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let sector: IndustryCatalogSector
    let onUseWorkflow: (IndustryWorkflowHandoff) -> Void
    let onCheckFacilities: (String) -> Void

    @State private var selectedWorkflowId: String?
    @State private var productName = ""

    init(
        sector: IndustryCatalogSector,
        onUseWorkflow: @escaping (IndustryWorkflowHandoff) -> Void,
        onCheckFacilities: @escaping (String) -> Void
    ) {
        self.sector = sector
        self.onUseWorkflow = onUseWorkflow
        self.onCheckFacilities = onCheckFacilities
        _selectedWorkflowId = State(
            initialValue: sector.ruleSet.workflowOptions.count == 1
                ? sector.ruleSet.workflowOptions.first?.workflowId
                : nil
        )
    }

    private var selectedWorkflow: IndustryCatalogWorkflow? {
        sector.ruleSet.workflowOptions.first { $0.workflowId == selectedWorkflowId }
    }

    private var cleanedProduct: String {
        productName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var requiresProduct: Bool {
        sector.selectionStrategy == "product_required"
    }

    private var canUseWorkflow: Bool {
        selectedWorkflow != nil && (!requiresProduct || !cleanedProduct.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    sectorSummary
                    productInput
                    workflowSelection
                    if let selectedWorkflow {
                        selectedWorkflowSummary(selectedWorkflow)
                    }
                    regulatoryEvidence
                    sourceEvidence
                    actionRow
                }
                .padding(18)
            }
            .background(palette.bgPage)
            .navigationTitle(sector.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private var sectorSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(sector.summary, systemImage: sector.iconName)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            HStack(spacing: 6) {
                detailChip("Rules v\(sector.ruleSet.version)")
                detailChip(sector.ruleSet.applicableModes.map(displayLabel).joined(separator: " · "))
            }
        }
    }

    @ViewBuilder
    private var productInput: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(requiresProduct ? "EXACT PRODUCT OR COMMODITY" : "PRODUCT OR COMMODITY")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(palette.textSecondary)
            TextField("Product, grade, species, asset, or commodity", text: $productName)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .background(palette.tintNeutral)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(palette.borderSoft, lineWidth: 1)
                }
            if requiresProduct && cleanedProduct.isEmpty {
                Text("This sector is assessed from the exact product, not from the sector name.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            }
        }
    }

    private var workflowSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OPERATIONAL WORKFLOW")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(palette.textSecondary)
            ForEach(sector.ruleSet.workflowOptions) { workflow in
                Button {
                    selectedWorkflowId = workflow.workflowId
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selectedWorkflowId == workflow.workflowId
                              ? "checkmark.circle.fill"
                              : "circle")
                            .foregroundStyle(selectedWorkflowId == workflow.workflowId
                                             ? Brand.success
                                             : palette.textTertiary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workflow.label)
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                            Text(workflow.appliesWhen)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(11)
                    .background(palette.tintNeutral)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func selectedWorkflowSummary(_ workflow: IndustryCatalogWorkflow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORKFLOW DEFAULTS")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(palette.textSecondary)
            if let cargo = workflow.safeDefaults.cargoType {
                detailRow("Cargo", displayLabel(cargo))
            }
            if let trailer = workflow.safeDefaults.trailerCode {
                detailRow("Equipment", displayLabel(trailer))
            }
            if let endorsements = workflow.safeDefaults.requiredEndorsements,
               !endorsements.isEmpty {
                detailRow("Endorsements", endorsements.joined(separator: ", "))
            }
            if !sector.ruleSet.accessorialAllowList.isEmpty {
                detailRow(
                    "Accessorials",
                    sector.ruleSet.accessorialAllowList.map(displayLabel).joined(separator: ", ")
                )
            }
        }
    }

    @ViewBuilder
    private var regulatoryEvidence: some View {
        if !sector.ruleSet.regulatoryRules.isEmpty || !sector.ruleSet.documentRules.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("CONDITIONAL REQUIREMENTS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.7)
                    .foregroundStyle(palette.textSecondary)
                ForEach(sector.ruleSet.regulatoryRules) { rule in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(rule.authority) · \(rule.title)")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text(rule.appliesWhen)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                        Text(rule.requirement)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.vertical, 5)
                }
                ForEach(sector.ruleSet.documentRules) { rule in
                    detailRow(
                        displayLabel(rule.documentType),
                        "\(rule.requiredWhen) · \(displayLabel(rule.blockingAt))"
                    )
                }
            }
        }
    }

    private var sourceEvidence: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCE EVIDENCE")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(palette.textSecondary)
            if sector.ruleSet.sources.isEmpty {
                Text("No verified source evidence is attached to this rule set.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            } else {
                ForEach(sector.ruleSet.sources) { source in
                    if let url = URL(string: source.sourceUrl) {
                        Link(destination: url) {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(
                                        source.verificationStatus == "verified"
                                            ? Brand.success
                                            : Brand.warning
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(source.authority) · \(source.title)")
                                        .font(EType.bodyStrong)
                                        .foregroundStyle(palette.textPrimary)
                                    Text("Checked \(datePart(source.checkedAt)) · valid through \(datePart(source.validUntil))")
                                        .font(EType.caption)
                                        .foregroundStyle(palette.textSecondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var actionRow: some View {
        VStack(spacing: 10) {
            Button {
                guard let workflow = selectedWorkflow else { return }
                let defaults = workflow.safeDefaults
                onUseWorkflow(IndustryWorkflowHandoff(
                    sectorId: sector.sectorId,
                    ruleSetId: sector.ruleSet.id,
                    workflowId: workflow.workflowId,
                    productName: cleanedProduct.isEmpty ? nil : cleanedProduct,
                    cargoType: defaults.cargoType,
                    trailerCode: defaults.trailerCode,
                    requiredEndorsements: defaults.requiredEndorsements ?? [],
                    specialEquipment: defaults.specialEquipment ?? [],
                    accessorialAllowList: sector.ruleSet.accessorialAllowList,
                    hazmatAuthRequired: defaults.hazmatAuthRequired ?? false,
                    preCoolRequired: defaults.preCoolRequired ?? false,
                    continuousMonitoring: defaults.continuousMonitoring ?? false
                ))
            } label: {
                Label("Use in Post-a-Load", systemImage: "plus.square.fill")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(canUseWorkflow
                                ? AnyShapeStyle(LinearGradient.diagonal)
                                : AnyShapeStyle(palette.textTertiary))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canUseWorkflow)

            Button {
                onCheckFacilities(cleanedProduct)
            } label: {
                Label("Check compatible facilities", systemImage: "building.2.crop.circle")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(palette.tintNeutral)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(cleanedProduct.isEmpty)
            .opacity(cleanedProduct.isEmpty ? 0.5 : 1)
        }
    }

    private func detailChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(palette.tintNeutral)
            .clipShape(Capsule())
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func displayLabel(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func datePart(_ iso: String) -> String {
        String(iso.prefix(10))
    }
}

#Preview("430 · Verticals · Night") {
    IndustryVerticalsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("430 · Verticals · Afternoon") {
    IndustryVerticalsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
