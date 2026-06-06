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
    /// Canonical cargo category (rawValue of `ShipperAPI.CargoType`:
    /// "hazmat", "petroleum", "refrigerated", "general", …). Lets the
    /// server gate hazmat-safe equipment even when no UN number was
    /// captured (e.g. petroleum/diesel posts).
    let cargoTypeRaw: String?
    /// Real UN identification number the user entered (e.g. "UN1267").
    /// Sent verbatim — nil/empty when the load isn't hazmat.
    let hazmatUnNumber: String?
    /// 49 CFR hazard class/division the user entered (e.g. "3").
    let hazmatClass: String?
    /// Packing group the user entered ("I" | "II" | "III").
    let hazmatPackingGroup: String?
    /// Proper shipping name (49 CFR 172.101 column 2 / ERG name), e.g.
    /// "DIESEL FUEL". Lets the agent reason about the actual substance,
    /// not just the UN id.
    let hazmatProperShippingName: String?
    /// ERG response guide number resolved for this UN (e.g. "128").
    /// Drives the emergency-response doc + placard expectations.
    let hazmatErgGuide: String?
    /// Toxic/poison-inhalation-hazard flag (TIH/PIH) from the ERG match.
    /// Forces inhalation-hazard equipment + routing constraints.
    let hazmatInhalationHazard: Bool?
    /// Reefer setpoint the user entered (free text incl. unit, e.g.
    /// "-10" / "34°F"). Sent verbatim so the agent can match a reefer/
    /// multi-temp trailer to the commodity. nil for non-reefer loads.
    let reeferTempLow: String?
    let reeferTempHigh: String?
    /// Oversized dimensions in feet (nil unless the user entered them).
    /// Drive flatbed/step-deck/RGN/lowboy selection + permit red flags.
    let oversizeLengthFt: Double?
    let oversizeWidthFt: Double?
    let oversizeHeightFt: Double?
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
            input.cargoTypeRaw ?? "",
            input.hazmatUnNumber ?? "", input.hazmatClass ?? "",
            input.hazmatPackingGroup ?? "", input.hazmatProperShippingName ?? "",
            input.hazmatErgGuide ?? "", "\(input.hazmatInhalationHazard ?? false)",
            input.reeferTempLow ?? "", input.reeferTempHigh ?? "",
            "\(input.oversizeLengthFt ?? 0)", "\(input.oversizeWidthFt ?? 0)",
            "\(input.oversizeHeightFt ?? 0)", "\(input.isOverdimensional)",
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
            // Swallow URLSession / structured-concurrency cancellation.
            // The widget uses `.task(id: fingerprint)` — typing into the
            // weight field (or any other input that feeds the fingerprint)
            // flips the id and SwiftUI cancels the in-flight URLSession
            // dataTask, which surfaces as NSURLErrorCancelled (-999) or
            // a Swift CancellationError. Both are NORMAL during user
            // interaction and a fresh recommendation is already on its
            // way — surfacing the cancellation as an "ESANG Equipment
            // Recommendation" error scares the user and obscures the
            // real recommendation that's about to arrive.
            let ns = error as NSError
            let isCancel = ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
                || error is CancellationError
            if isCancel { return }
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

    /// Cargo-category hint used for client-side compatibility filtering
    /// (founder bug 2026-05-31: ESANG was suggesting `dry_van` for
    /// diesel-fuel posts and for vessel-mode posts, both nonsensical).
    /// Pass the rawValue of `ShipperAPI.CargoType` ("hazmat",
    /// "petroleum", "refrigerated", "general", etc.); empty/nil = "general".
    var cargoTypeRaw: String = "general"

    /// Real hazmat fields the user entered on the post-load wizard.
    /// Wired into the rec request so ESANG returns mode + hazmat-aware
    /// equipment (C2: previously hardcoded nil, so a UN1267/Class-3
    /// diesel post still got a Dry Van top pick). Empty when not hazmat.
    var hazmatUnNumber: String = ""
    var hazmatClass: String = ""
    var hazmatPackingGroup: String = ""
    /// Rest of the hazmat profile (proper shipping name, ERG guide,
    /// inhalation-hazard flag) so the agent reasons on the substance,
    /// not just the UN id. Empty/false when the load isn't hazmat.
    var hazmatProperShippingName: String = ""
    var hazmatErgGuide: String = ""
    var hazmatInhalationHazard: Bool = false
    /// Reefer setpoint text (verbatim incl. unit). Empty unless reefer.
    var reeferTempLow: String = ""
    var reeferTempHigh: String = ""
    /// Oversized dimensions (ft). nil unless the user entered them.
    var oversizeLengthFt: Double? = nil
    var oversizeWidthFt: Double? = nil
    var oversizeHeightFt: Double? = nil

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
                // Apply client-side compatibility filter before rendering.
                // Server may return Dry Van for vessel-mode or for diesel
                // (hazmat) cargo; both are nonsensical. The filter drops
                // those rows and promotes the first valid alternative to
                // the top slot so the user always sees a mode-coherent +
                // cargo-coherent recommendation.
                let filtered = filteredPicks(top: resp.topPick, alts: resp.alternatives)
                if let top = filtered.topPick {
                    Text(resp.synthesis)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .padding(.bottom, 2)

                    pickRow(top, isTop: true)

                    if !filtered.alternatives.isEmpty {
                        Text("ALTERNATIVES")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                        ForEach(filtered.alternatives.prefix(2)) { opt in
                            pickRow(opt, isTop: false)
                        }
                    }
                } else {
                    // ESANG returned ONLY incompatible options for this
                    // mode + cargo combo. Surface a clear nudge instead
                    // of silently swallowing the response.
                    Text("No mode-compatible recommendations for this \(prettyVertical) + \(prettyCargo) combination yet. Picking equipment manually below is the safest path.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
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
         cargoTypeRaw, hazmatUnNumber, hazmatClass, hazmatPackingGroup,
         "\(isOverdimensional)", "\(companyId ?? 0)"]
            .joined(separator: "|")
    }

    private func canRecommend() -> Bool {
        guard let companyId, companyId > 0 else { return false }
        return !commodity.trimmingCharacters(in: .whitespaces).isEmpty
            && (weightLbs ?? 0) > 0
    }

    private func buildInput() -> EquipmentRecommendInput {
        // Normalize: a UN number arrives as "UN1267" or "1267"; the
        // server hazmat tables key on the raw 4-digit id, so strip a
        // leading "UN" prefix and trim. Empty hazmat fields go up as
        // nil (not "") so the server treats the load as non-hazmat
        // rather than matching an empty key.
        func nilIfBlank(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let unRaw = hazmatUnNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let unNormalized = unRaw.uppercased().hasPrefix("UN")
            ? String(unRaw.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            : unRaw
        return EquipmentRecommendInput(
            commodity: commodity,
            weightLbs: weightLbs,
            vertical: vertical,
            originState: originState,
            destState: destState,
            cargoTypeRaw: nilIfBlank(cargoTypeRaw),
            hazmatUnNumber: nilIfBlank(unNormalized),
            hazmatClass: nilIfBlank(hazmatClass),
            hazmatPackingGroup: nilIfBlank(hazmatPackingGroup),
            hazmatProperShippingName: nilIfBlank(hazmatProperShippingName),
            hazmatErgGuide: nilIfBlank(hazmatErgGuide),
            // Only send the TIH flag when this is actually a hazmat load
            // — a non-hazmat post should never carry an inhalation flag.
            hazmatInhalationHazard: nilIfBlank(unNormalized) == nil ? nil : hazmatInhalationHazard,
            reeferTempLow: nilIfBlank(reeferTempLow),
            reeferTempHigh: nilIfBlank(reeferTempHigh),
            oversizeLengthFt: oversizeLengthFt,
            oversizeWidthFt: oversizeWidthFt,
            oversizeHeightFt: oversizeHeightFt,
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

    private var prettyVertical: String {
        switch vertical {
        case "VESSEL": return "vessel"
        case "RAIL":   return "rail"
        default:       return "truck"
        }
    }
    private var prettyCargo: String {
        let raw = cargoTypeRaw.lowercased()
        if raw.isEmpty { return "general" }
        return raw.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - Client-side compatibility filter
    //
    // Founder bug 2026-05-31: ESANG was returning Dry Van as the top
    // pick for VESSEL mode AND for hazmat (diesel-fuel) posts. Both
    // are operationally + regulatorily wrong. We can't unilaterally
    // fix the server here, but we CAN refuse to surface a row whose
    // trailerKey is incompatible with the user's mode/cargo intent.
    //
    // The filter is conservative: when in doubt, an option is kept.
    // Truly bad rows (wrong mode, hazmat in dry van) are dropped, and
    // the first surviving alternative is promoted to the top slot.

    private static let truckTrailerKeys: Set<String> = [
        "dry_van", "reefer", "flatbed", "step_deck", "conestoga", "container",
        "power_only", "lowboy", "hot_shot", "tanker_petro", "tanker_hazmat",
        "tanker_liquid", "tanker_gas", "oversized"
    ]
    private static let railTrailerKeys: Set<String> = [
        "rail_tofc", "rail_cofc", "rail_intermodal", "rail_boxcar",
        "rail_reefer_boxcar", "rail_tank_gas", "rail_tank_liquid",
        "rail_hopper", "rail_centerbeam", "rail_gondola",
        "rail_auto_rack", "rail_flatcar"
    ]
    private static let vesselTrailerKeys: Set<String> = [
        "vessel_container", "vessel_bulk", "vessel_tanker",
        "vessel_iso_tank", "vessel_lng", "vessel_reefer_container",
        "vessel_ro_ro"
    ]

    /// Equipment that's legally + operationally able to carry
    /// hazmat / petroleum / diesel-class cargo. Drums in a dry van
    /// for *placarded* hazmat is a §177.834 violation; the recommender
    /// must never surface that. Tankers / ISO tanks / rail tank cars
    /// are the only valid carriers.
    private static let hazmatSafeKeys: Set<String> = [
        "tanker_hazmat", "tanker_petro", "tanker_liquid", "tanker_gas",
        "rail_tank_gas", "rail_tank_liquid",
        "vessel_tanker", "vessel_iso_tank", "vessel_lng"
    ]

    private func isCargoHazmatLike(_ raw: String) -> Bool {
        let r = raw.lowercased()
        return r.contains("hazmat") || r.contains("chemical")
            || r.contains("petroleum") || r.contains("gas")
            || r.contains("liquid") || r.contains("diesel")
            || r.contains("fuel")
    }

    private func isOptionCompatible(_ opt: EquipmentOption) -> Bool {
        let allowedForMode: Set<String>
        switch vertical {
        case "TRUCK":  allowedForMode = Self.truckTrailerKeys
        case "RAIL":   allowedForMode = Self.railTrailerKeys
        case "VESSEL": allowedForMode = Self.vesselTrailerKeys
        default:       allowedForMode = Self.truckTrailerKeys
            .union(Self.railTrailerKeys).union(Self.vesselTrailerKeys)
        }
        guard allowedForMode.contains(opt.trailerKey) else { return false }
        if isCargoHazmatLike(cargoTypeRaw),
           !Self.hazmatSafeKeys.contains(opt.trailerKey) {
            return false
        }
        return true
    }

    private func filteredPicks(top: EquipmentOption,
                               alts: [EquipmentOption])
        -> (topPick: EquipmentOption?, alternatives: [EquipmentOption])
    {
        var ordered = [top] + alts
        ordered = ordered.filter { isOptionCompatible($0) }
        guard let first = ordered.first else { return (nil, []) }
        return (first, Array(ordered.dropFirst()))
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
