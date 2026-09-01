//
//  204F_ShipperAutoTransportVINCondition.swift
//  EusoTrip 2027 - Shipper auto-transport requirements.
//
//  A load currently stores the vehicle count, but not a per-unit VIN manifest,
//  damage diagram, or condition-photo set. This screen never infers those
//  records from the count; it shows the real load and server-owned requirements.
//

import SwiftUI

private struct AutoRequirement204F: Decodable, Identifiable {
    let id: String
    let rule: String?
    let title: String
    let desc: String
}

private struct AutoRequirementGroup204F: Decodable {
    let title: String
    let cfr: String?
    let requirements: [AutoRequirement204F]
}

private struct AutoAlert204F: Decodable, Identifiable {
    var id: String { "\(severity)-\(message)" }
    let severity: String
    let message: String
}

private struct AutoRegulations204F: Decodable {
    let title: String
    let vehicleSecurement: AutoRequirementGroup204F
    let conditionReporting: AutoRequirementGroup204F
    let specialConsiderations: AutoRequirementGroup204F
    let alerts: [AutoAlert204F]
    let inspectionChecklist: [String]
}

@MainActor
private final class AutoStore204F: ObservableObject {
    @Published private(set) var load: LoadsAPI.LoadDetail?
    @Published private(set) var regulations: AutoRegulations204F?
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
            regulations = nil
            errorMessage = "Open vehicle condition from an auto-transport load to see its records."
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            guard let resolved = try await api.loads.getDetail(id: loadId) else {
                load = nil
                regulations = nil
                errorMessage = "This load is no longer available. Return to Loads and choose another one."
                return
            }
            load = resolved

            struct Input: Encodable { let vehicleCount: Int? }
            regulations = try await api.query(
                "trailerRegulatory.getAutoCarrierRegulations",
                input: Input(vehicleCount: resolved.multiVehicleCount.flatMap { $0 > 0 ? $0 : nil })
            )
        } catch {
            regulations = nil
            errorMessage = error.eusoUserCopy
        }
    }
}

struct ShipperAutoTransportVINCondition: View {
    let loadId: String
    @StateObject private var store: AutoStore204F
    @Environment(\.palette) private var palette

    init(loadId: String = "") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: AutoStore204F(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(
                    eyebrow: "SHIPPER · AUTO-TRANSPORT",
                    idText: store.load?.loadNumber ?? loadId,
                    title: "VIN & condition"
                )

                if let errorMessage = store.errorMessage {
                    DegradedNote(text: errorMessage)
                        .padding(.top, Space.s3)
                }

                if store.isLoading, store.load == nil {
                    ProgressView("Loading load records")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s6)
                }

                if let load = store.load {
                    loadCard(load)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)

                    evidenceAvailability
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s3)
                }

                if let regulations = store.regulations {
                    if !regulations.alerts.isEmpty {
                        SectionLabel("LOAD ALERTS")
                            .padding(.top, Space.s5)
                        alerts(regulations.alerts)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)
                    }

                    SectionLabel(regulations.vehicleSecurement.cfr ?? "VEHICLE SECUREMENT")
                        .padding(.top, Space.s5)
                    requirementGroup(regulations.vehicleSecurement, tint: Brand.info)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    SectionLabel("CONDITION REPORTING")
                        .padding(.top, Space.s5)
                    requirementGroup(regulations.conditionReporting, tint: Brand.warning)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    SectionLabel("SPECIAL VEHICLE TYPES")
                        .padding(.top, Space.s5)
                    requirementGroup(regulations.specialConsiderations, tint: Brand.rail)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    SectionLabel("INSPECTION CHECKLIST")
                        .padding(.top, Space.s5)
                    checklist(regulations.inspectionChecklist)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)
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
                AddendaIconChip(systemImage: "car.side.fill", tint: Brand.info)
                VStack(alignment: .leading, spacing: 4) {
                    Text(load.commodityName ?? load.commodity ?? "Vehicle cargo")
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
            factRow("VEHICLES", countText(load.multiVehicleCount))
            factRow("EQUIPMENT", load.equipmentType ?? "Not recorded")
            factRow("WEIGHT", load.weightDisplay)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private var evidenceAvailability: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("Per-vehicle evidence is not linked")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text("The load records a vehicle count only. It has no load-linked VIN manifest, signed vehicle condition reports, damage marks, or photo evidence, so no unit can be shown as verified or clean.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private func alerts(_ alerts: [AutoAlert204F]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(alerts.enumerated()), id: \.element.id) { index, alert in
                HStack(alignment: .top, spacing: Space.s3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Brand.warning)
                    Text(alert.message)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(Space.s4)
                if index < alerts.count - 1 {
                    Divider().overlay(palette.borderFaint)
                }
            }
        }
        .addendaPanel(palette)
    }

    private func requirementGroup(_ group: AutoRequirementGroup204F, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.title)
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
                .padding(Space.s4)
            Divider().overlay(palette.borderFaint)
            ForEach(Array(group.requirements.enumerated()), id: \.element.id) { index, requirement in
                HStack(alignment: .top, spacing: Space.s3) {
                    AddendaIconChip(systemImage: "doc.text.magnifyingglass", tint: tint)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(requirement.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                            Spacer(minLength: Space.s2)
                            if let rule = requirement.rule {
                                Text(rule)
                                    .font(EType.mono(.micro))
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                        Text(requirement.desc)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Space.s4)
                if index < group.requirements.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, 52)
                }
            }
        }
        .addendaPanel(palette)
    }

    private func checklist(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: Space.s3) {
                    Image(systemName: "square")
                        .foregroundStyle(palette.textTertiary)
                    Text(item)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(Space.s4)
                if index < items.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, 44)
                }
            }
        }
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

    private func countText(_ count: Int?) -> String {
        guard let count, count > 0 else { return "Not recorded" }
        return "\(count)"
    }
}

#Preview("204F · Auto condition · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperAutoTransportVINCondition()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("204F · Auto condition · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperAutoTransportVINCondition()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
