//
//  EquipmentRecommenderWidget.swift
//  EusoTrip — IO 2026 Tier 2 #40 · Equipment selection agent surface
//
//  Inline widget for the Shipper post-load wizard. Calls
//  `equipmentAgent.recommend` once enough context exists (cargo
//  description + weight) and surfaces the top pick + two
//  alternatives with fit scores. A tap on any pick fires the
//  bound `onApply` closure so the wizard can switch its
//  `equipmentType` State in one move.
//
//  Sits between the equipment-section header and the chip strip
//  in `204_ShipperPostLoad.swift`.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire models

struct EquipmentOption: Decodable, Hashable, Identifiable {
    var id: String { trailerKey }
    let trailerKey: String
    let fitScore: Int
    let reason: String
    let availableInFleet: Int
    let docsRequired: [String]
    let redFlags: [String]
}

struct EquipmentRecommendResponse: Decodable {
    let generatedAtUtc: String
    let topPick: EquipmentOption
    let alternatives: [EquipmentOption]
    let synthesis: String
    let childrenFiredCount: Int
}

struct EquipmentRecommendInput: Encodable {
    let commodity: String
    let weightLbs: Int?
    let vertical: String          // "TRUCK" | "RAIL" | "VESSEL"
    let originState: String?
    let destState: String?
    let hazmatUnNumber: String?
    let isOverdimensional: Bool
    let companyId: Int
}

// MARK: - Store

@MainActor
final class EquipmentRecommenderStore: ObservableObject {
    @Published var response: EquipmentRecommendResponse?
    @Published var loading: Bool = false
    @Published var error: String?

    /// Fired once per (commodity + weight + vertical) tuple so the
    /// recommendation only re-pulls when the meaningful inputs
    /// change. Prevents the agent from being called on every keystroke.
    private var lastFingerprint: String?

    func recommendIfNeeded(input: EquipmentRecommendInput) async {
        let fingerprint = [
            input.commodity, "\(input.weightLbs ?? 0)", input.vertical,
            input.originState ?? "", input.destState ?? "",
            input.hazmatUnNumber ?? "", "\(input.isOverdimensional)",
        ].joined(separator: "|")
        if fingerprint == lastFingerprint, response != nil { return }
        lastFingerprint = fingerprint
        await recommend(input: input)
    }

    func recommend(input: EquipmentRecommendInput) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let resp: EquipmentRecommendResponse = try await EusoTripAPI.shared
                .equipmentAgent.recommend(input: input)
            self.response = resp
            self.error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

// MARK: - Widget

struct EquipmentRecommenderWidget: View {
    @StateObject private var store = EquipmentRecommenderStore()

    /// Caller-supplied current state. The widget pulls when these
    /// resolve to a usable input and renders idle otherwise.
    let commodity: String
    let weightLbs: Int?
    let vertical: String                  // "TRUCK" | "RAIL" | "VESSEL"
    let companyId: Int?
    let originState: String?
    let destState: String?
    let isOverdimensional: Bool

    /// Called when the user taps a recommended trailer.
    /// Passes the `trailerKey` (matches `EquipmentChoice.rawValue`).
    let onApply: (String) -> Void

    /// Currently-selected trailerKey so the matching row gets a
    /// "selected" outline.
    let currentSelection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption2.weight(.bold))
                Text("ESANG · EQUIPMENT RECOMMENDATION")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                Spacer()
                if store.loading {
                    ProgressView().controlSize(.mini)
                } else if store.response != nil {
                    Button {
                        Task { await store.recommend(input: buildInput()) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2.weight(.bold))
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(.secondary)

            if let resp = store.response {
                // Top pick row
                Text(resp.synthesis)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 2)

                pickRow(resp.topPick, isTop: true)

                if !resp.alternatives.isEmpty {
                    Text("ALTERNATIVES")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                    ForEach(resp.alternatives.prefix(2)) { opt in
                        pickRow(opt, isTop: false)
                    }
                }
            } else if let err = store.error {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(Color.red)
            } else if !canRecommend() {
                Text("Enter cargo description and weight to get an equipment recommendation.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if store.loading {
                Text("Asking ESANG…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .task(id: fingerprint) {
            guard canRecommend() else { return }
            await store.recommendIfNeeded(input: buildInput())
        }
    }

    // MARK: helpers

    private var fingerprint: String {
        [commodity, "\(weightLbs ?? 0)", vertical, originState ?? "", destState ?? "",
         "\(isOverdimensional)", "\(companyId ?? 0)"]
            .joined(separator: "|")
    }

    private func canRecommend() -> Bool {
        guard let companyId, companyId > 0 else { return false }
        return !commodity.trimmingCharacters(in: .whitespaces).isEmpty
            && (weightLbs ?? 0) > 0
    }

    private func buildInput() -> EquipmentRecommendInput {
        EquipmentRecommendInput(
            commodity: commodity,
            weightLbs: weightLbs,
            vertical: vertical,
            originState: originState,
            destState: destState,
            hazmatUnNumber: nil,
            isOverdimensional: isOverdimensional,
            companyId: companyId ?? 1
        )
    }

    @ViewBuilder
    private func pickRow(_ opt: EquipmentOption, isTop: Bool) -> some View {
        Button {
            onApply(opt.trailerKey)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isTop ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                    Text("\(opt.fitScore)")
                        .font(.caption2.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(isTop ? Color.accentColor : .primary)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(prettyTrailerKey(opt.trailerKey))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                        if opt.availableInFleet > 0 {
                            Text("\(opt.availableInFleet) in fleet")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.18)))
                                .foregroundStyle(Color.green)
                        }
                        if !opt.redFlags.isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.orange)
                        }
                    }
                    Text(opt.reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if opt.trailerKey == currentSelection {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(opt.trailerKey == currentSelection
                          ? Color.accentColor.opacity(0.08)
                          : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        opt.trailerKey == currentSelection
                            ? Color.accentColor.opacity(0.5)
                            : Color.primary.opacity(0.06),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func prettyTrailerKey(_ raw: String) -> String {
        raw.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }
}

// MARK: - Previews

#Preview("Idle · Dark") {
    EquipmentRecommenderWidget(
        commodity: "",
        weightLbs: nil,
        vertical: "TRUCK",
        companyId: 1,
        originState: "GA",
        destState: "FL",
        isOverdimensional: false,
        onApply: { _ in },
        currentSelection: "dry_van"
    )
    .padding(20)
    .preferredColorScheme(.dark)
}

#Preview("Loading · Light") {
    EquipmentRecommenderWidget(
        commodity: "Frozen poultry, 12 pallets",
        weightLbs: 38_500,
        vertical: "TRUCK",
        companyId: 1,
        originState: "GA",
        destState: "FL",
        isOverdimensional: false,
        onApply: { _ in },
        currentSelection: "dry_van"
    )
    .padding(20)
    .preferredColorScheme(.light)
}
