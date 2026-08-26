//
//  204H_ShipperFlatbedCargoSecurement.swift
//  EusoTrip 2027 - Shipper flatbed securement.
//
//  The load supplies cargo and weight. It does not currently persist tiedown
//  inventory or measured working-load limits, so this screen calculates only
//  the server-rule reference minimum and never claims a securement pass.
//

import SwiftUI

private struct FlatbedRequirement204H: Decodable, Identifiable {
    let id: String
    let rule: String?
    let title: String
    let desc: String
}

private struct FlatbedRequirementGroup204H: Decodable {
    let title: String
    let cfr: String?
    let requirements: [FlatbedRequirement204H]
}

private struct FlatbedAlert204H: Decodable, Identifiable {
    var id: String { "\(severity)-\(message)" }
    let severity: String
    let message: String
}

private struct FlatbedRegulations204H: Decodable {
    let title: String
    let cargoSecurement: FlatbedRequirementGroup204H
    let oversizeOverweight: FlatbedRequirementGroup204H
    let tarpingRequirements: FlatbedRequirementGroup204H
    let alerts: [FlatbedAlert204H]
    let inspectionChecklist: [String]
}

@MainActor
private final class SecurementStore204H: ObservableObject {
    @Published private(set) var load: LoadsAPI.LoadDetail?
    @Published private(set) var regulations: FlatbedRegulations204H?
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
            errorMessage = "Open cargo securement from a flatbed load to see its records."
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

            struct Input: Encodable {
                let productName: String?
                let weight: Double?
            }
            regulations = try await api.query(
                "trailerRegulatory.getFlatbedRegulations",
                input: Input(
                    productName: resolved.commodityName ?? resolved.commodity,
                    weight: weightInPounds(resolved)
                )
            )
        } catch {
            regulations = nil
            errorMessage = error.eusoUserCopy
        }
    }

    private func weightInPounds(_ load: LoadsAPI.LoadDetail) -> Double? {
        guard load.weightValue > 0,
              let unit = load.weightUnit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        else { return nil }

        switch unit {
        case "lb", "lbs", "pound", "pounds":
            return load.weightValue
        case "kg", "kgs", "kilogram", "kilograms":
            return load.weightValue * 2.204_622_621_8
        case "mt", "tonne", "tonnes", "metric ton", "metric tons":
            return load.weightValue * 2_204.622_621_8
        case "short ton", "short tons", "us ton", "us tons":
            return load.weightValue * 2_000
        default:
            return nil
        }
    }
}

struct ShipperFlatbedCargoSecurement: View {
    let loadId: String
    @StateObject private var store: SecurementStore204H
    @Environment(\.palette) private var palette

    init(loadId: String = "") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: SecurementStore204H(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(
                    eyebrow: "SHIPPER · FLATBED · SECUREMENT",
                    idText: store.load?.loadNumber ?? loadId,
                    title: "Cargo securement"
                )

                if let errorMessage = store.errorMessage {
                    DegradedNote(text: errorMessage)
                        .padding(.top, Space.s3)
                }

                if store.isLoading, store.load == nil {
                    ProgressView("Loading securement requirements")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s6)
                }

                if let load = store.load {
                    loadCard(load)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)

                    wllReference(load)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s3)

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

                    SectionLabel(regulations.cargoSecurement.cfr ?? "CARGO SECUREMENT")
                        .padding(.top, Space.s5)
                    requirementGroup(regulations.cargoSecurement, tint: Brand.info)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    SectionLabel("OVERSIZE / OVERWEIGHT")
                        .padding(.top, Space.s5)
                    requirementGroup(regulations.oversizeOverweight, tint: Brand.warning)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    SectionLabel("TARPING & COVER")
                        .padding(.top, Space.s5)
                    requirementGroup(regulations.tarpingRequirements, tint: Brand.rail)
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
                AddendaIconChip(systemImage: "truck.box.fill", tint: Brand.info)
                VStack(alignment: .leading, spacing: 4) {
                    Text(load.commodityName ?? load.commodity ?? "Flatbed cargo")
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
            factRow("CARGO WEIGHT", load.weightDisplay)
            factRow("EQUIPMENT", load.equipmentType ?? "Not recorded")
            factRow("PERMIT", permitText(load.permitType))
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private func wllReference(_ load: LoadsAPI.LoadDetail) -> some View {
        HStack(alignment: .center, spacing: Space.s4) {
            ZStack {
                Circle().stroke(palette.borderSoft, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: load.weightValue > 0 ? 0.5 : 0)
                    .stroke(Brand.info, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("50%")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(width: 86, height: 86)

            VStack(alignment: .leading, spacing: 5) {
                Text("Aggregate WLL reference")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text(load.weightValue > 0 ? "Minimum reference: \(formatWeight(load.weightValue / 2, unit: load.weightUnit)) in each required direction." : "Cargo weight is not recorded, so the reference minimum cannot be calculated.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("REFERENCE ONLY · NOT A SECUREMENT PASS")
                    .font(EType.mono(.micro))
                    .foregroundStyle(Brand.warning)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private var evidenceAvailability: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("Securement evidence is not recorded")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text("This load has no tiedown roster, device ratings, attachment points, dimensions, blocking, bracing, or inspection evidence. EusoTrip cannot calculate supplied WLL or mark the cargo secured.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private func alerts(_ alerts: [FlatbedAlert204H]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(alerts.enumerated()), id: \.element.id) { index, alert in
                HStack(alignment: .top, spacing: Space.s3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(alert.severity == "critical" ? Brand.hazmat : Brand.warning)
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

    private func requirementGroup(_ group: FlatbedRequirementGroup204H, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.title)
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
                .padding(Space.s4)
            Divider().overlay(palette.borderFaint)
            ForEach(Array(group.requirements.enumerated()), id: \.element.id) { index, requirement in
                HStack(alignment: .top, spacing: Space.s3) {
                    AddendaIconChip(systemImage: "link", tint: tint)
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

    private func permitText(_ value: String?) -> String {
        guard let value, !value.isEmpty, value.lowercased() != "none" else { return "Not recorded" }
        return value.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private func formatWeight(_ value: Double, unit: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
        return "\(number) \(unit ?? "lb")"
    }
}

#Preview("204H · Flatbed securement · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperFlatbedCargoSecurement()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("204H · Flatbed securement · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperFlatbedCargoSecurement()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
