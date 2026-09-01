//
//  204E_ShipperLivestock28HourClock.swift
//  EusoTrip 2027 - Shipper livestock compliance.
//
//  The load row does not currently persist confinement-start or qualifying-rest
//  events. This surface therefore presents the real load context and the
//  server-owned livestock requirements without synthesizing an active clock.
//

import SwiftUI

private struct LivestockRequirement204E: Decodable, Identifiable {
    let id: String
    let rule: String?
    let title: String
    let desc: String
}

private struct LivestockRequirementGroup204E: Decodable {
    let title: String
    let statute: String?
    let requirements: [LivestockRequirement204E]
}

private struct LivestockRegulations204E: Decodable {
    let title: String
    let twentyEightHourLaw: LivestockRequirementGroup204E
    let usdaHealth: LivestockRequirementGroup204E?
    let animalWelfare: LivestockRequirementGroup204E
    let hosExemption: LivestockRequirementGroup204E
    let inspectionChecklist: [String]
}

@MainActor
private final class LivestockStore204E: ObservableObject {
    @Published private(set) var load: LoadsAPI.LoadDetail?
    @Published private(set) var regulations: LivestockRegulations204E?
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
            errorMessage = "Open livestock compliance from a load to see its records."
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
                let animalType: String?
                let headCount: Int?
                let isInterstate: Bool?
            }

            let originState = resolved.pickupLocation?.state?.trimmingCharacters(in: .whitespacesAndNewlines)
            let destinationState = resolved.deliveryLocation?.state?.trimmingCharacters(in: .whitespacesAndNewlines)
            let interstate: Bool?
            if let originState, !originState.isEmpty,
               let destinationState, !destinationState.isEmpty {
                interstate = originState.caseInsensitiveCompare(destinationState) != .orderedSame
            } else {
                interstate = nil
            }

            regulations = try await api.query(
                "trailerRegulatory.getLivestockRegulations",
                input: Input(
                    animalType: resolved.commodityName ?? resolved.commodity,
                    headCount: nil,
                    isInterstate: interstate
                )
            )
        } catch {
            regulations = nil
            errorMessage = error.eusoUserCopy
        }
    }
}

struct ShipperLivestock28HourClock: View {
    let loadId: String
    @StateObject private var store: LivestockStore204E
    @Environment(\.palette) private var palette

    init(loadId: String = "") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: LivestockStore204E(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(
                    eyebrow: "SHIPPER · LIVESTOCK · 28-HOUR LAW",
                    idText: store.load?.loadNumber ?? loadId,
                    title: "Livestock compliance"
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

                    clockAvailability
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s3)
                }

                if let regulations = store.regulations {
                    SectionLabel(regulations.twentyEightHourLaw.statute ?? "28-HOUR LAW")
                        .padding(.top, Space.s5)
                    requirementGroup(regulations.twentyEightHourLaw)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    if let health = regulations.usdaHealth {
                        SectionLabel("INTERSTATE HEALTH REQUIREMENTS")
                            .padding(.top, Space.s5)
                        requirementGroup(health)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)
                    }

                    SectionLabel("ANIMAL WELFARE")
                        .padding(.top, Space.s5)
                    requirementGroup(regulations.animalWelfare)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    SectionLabel("DRIVER HOURS")
                        .padding(.top, Space.s5)
                    requirementGroup(regulations.hosExemption)
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
                AddendaIconChip(systemImage: "pawprint.fill", tint: Brand.success)
                VStack(alignment: .leading, spacing: 4) {
                    Text(load.commodityName ?? load.commodity ?? "Livestock cargo")
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
            factRow("HEAD COUNT", "Not recorded")
            factRow("WEIGHT", load.weightDisplay)
            factRow("PICKUP", load.pickupDate.map(formatDate) ?? "Not recorded")
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private var clockAvailability: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("Confinement clock not started")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text("This load has no recorded confinement-start or qualifying five-hour rest event. A scheduled pickup time is not proof that animals were loaded, so EusoTrip will not manufacture a countdown.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private func requirementGroup(_ group: LivestockRequirementGroup204E) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.title)
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
                .padding(Space.s4)
            Divider().overlay(palette.borderFaint)
            ForEach(Array(group.requirements.enumerated()), id: \.element.id) { index, requirement in
                requirementRow(requirement)
                if index < group.requirements.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, 52)
                }
            }
        }
        .addendaPanel(palette)
    }

    private func requirementRow(_ requirement: LivestockRequirement204E) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            AddendaIconChip(systemImage: "doc.text.magnifyingglass", tint: Brand.info)
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
            Text(label)
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s3)
            Text(value)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview("204E · Livestock compliance · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperLivestock28HourClock()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("204E · Livestock compliance · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperLivestock28HourClock()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
