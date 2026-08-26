//
//  204C_ShipperHazmatManifestGate.swift
//  EusoTrip 2027 - Shipper hazmat manifest gate (drill-down of 204 Post a Load).
//
//  ARCHETYPE: COMPLIANCE / GATE. The DOT identity block and every gate row
//  come from the server's own hazmat validation for THIS load. There is no
//  local gate table: if the server returns four checks, four rows render.
//  A load with no recorded hazmat class produces no verdict at all rather
//  than a fabricated CLEARED.
//
//  SwiftUI twin of:
//    02 Shipper/Light-SVG/204C Shipper Hazmat Manifest Gate.svg
//    02 Shipper/Dark-SVG/204C Shipper Hazmat Manifest Gate.svg
//
//  ── WIRING MANIFEST (line-confirmed on disk frontend/server/routers/) ──
//    loads.getById              EXISTS · loads.ts:1225
//    hazmat.validateLoad        EXISTS · hazmat.ts:173  (checks[] + summary + overallStatus)
//    hazmat.ergQuickLookup      EXISTS · hazmat.ts:326  (UN identity + ERG guide + placard)
//    hazmat.determinePlacards   EXISTS · hazmat.ts:123  (placard requirement + threshold reason)
//  NOT CALLED — no such procedure exists tree-wide:
//    insurance.bindCargoEndorsement  MISSING · the SVG's "Resolve gates" action
//      has no backing mutation, so the screen shows a named unavailable state
//      instead of a button that cannot do anything.
//
//  DELIBERATE OMISSIONS (each would have required inventing data):
//    · The SVG's "$5M financial responsibility" row is NOT rendered.
//      hazmat.validateLoad does not emit a 49 CFR 387.9 check, and no other
//      procedure reports a bound MCS-90 limit for a load.
//    · The SVG's segregation chip is NOT rendered. hazmat.checkSegregation
//      (hazmat.ts:154) compares MULTIPLE materials; the load row carries one
//      hazmat class, so a "no conflict" result would be trivially true and
//      would read as a cleared multi-material segregation that never ran.
//    · The SVG's escort chip is NOT rendered — no procedure reports an
//      escort requirement for a hazmat truck load.
//
//  §W OFFLINE POLICY: ONLINE_ONLY(a 49 CFR manifest verdict is re-derived
//  server-side on every query against live driver-endorsement and carrier-
//  authorization rows; a cached CLEARED could mask an endorsement that
//  lapsed since the cache was written). Nothing is persisted client-side.
//
//  — Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Decoded models

private struct HazmatCheck204C: Decodable, Identifiable {
    var id: String { "\(name)|\(regulation)" }
    let name: String
    /// "pass" | "fail" | "warn"
    let status: String
    let detail: String
    let regulation: String
}

private struct HazmatSummary204C: Decodable {
    let total: Int
    let pass: Int
    let fail: Int
    let warn: Int
}

private struct HazmatValidation204C: Decodable {
    let valid: Bool
    let checks: [HazmatCheck204C]
    let summary: HazmatSummary204C
    /// "BLOCKED" | "WARNING" | "CLEAR"
    let overallStatus: String
}

private struct ErgLookup204C: Decodable {
    let found: Bool
    let unNumber: String?
    let name: String?
    let guideNumber: Int?
    let hazardClass: String?
    let placard: String?
    let isTIH: Bool?
    let isWR: Bool?
}

private struct PlacardRule204C: Decodable, Identifiable {
    var id: String { "\(hazmatClass)|\(placardName)" }
    let hazmatClass: String
    let placardName: String
    let required: Bool
    let reason: String
}

private struct PlacardDetermination204C: Decodable {
    let placards: [PlacardRule204C]
    let useDangerousPlacardOption: Bool
    let dangerousPlacardNote: String?
    let totalMaterials: Int
}

/// Why the gate could not run. Distinguishes "not a hazmat load" from
/// "hazmat load with an incomplete manifest" — those are different truths.
private enum HazmatGateBlock204C {
    case notHazmat
    case missingWeight
}

// MARK: - Store

@MainActor
private final class HazmatGateStore204C: ObservableObject {
    @Published private(set) var load: LoadsAPI.LoadDetail?
    @Published private(set) var validation: HazmatValidation204C?
    @Published private(set) var erg: ErgLookup204C?
    @Published private(set) var placards: PlacardDetermination204C?
    @Published private(set) var block: HazmatGateBlock204C?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    let loadId: String
    private let api: EusoTripAPI

    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    private func clear() {
        load = nil
        validation = nil
        erg = nil
        placards = nil
        block = nil
    }

    func refresh() async {
        guard !loadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clear()
            errorMessage = "Open the manifest gate from a load to see its hazmat checks."
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            guard let resolved = try await api.loads.getDetail(id: loadId) else {
                clear()
                errorMessage = "This load is no longer available. Return to Loads and choose another one."
                return
            }
            load = resolved
            validation = nil
            erg = nil
            placards = nil
            block = nil

            let hazmatClass = resolved.hazmatClass?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !hazmatClass.isEmpty else {
                block = .notHazmat
                return
            }

            // hazmat.validateLoad requires a numeric weight. Zero means the
            // column is absent or unparseable — the gate is NOT run against a
            // substituted weight, because the placarding thresholds are
            // weight-driven and a wrong weight produces a wrong verdict.
            let weight = resolved.weightValue
            guard weight > 0 else {
                block = .missingWeight
                return
            }

            let unNumber = resolved.unNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
            let weightUnit = normalizedWeightUnit(resolved.weightUnit)
            let trailerType = resolved.equipmentType?.trimmingCharacters(in: .whitespacesAndNewlines)
            var failures: [String] = []

            struct ValidateInput: Encodable {
                let loadId: Int?
                let hazmatClass: String
                let unNumber: String?
                let weight: Double
                let weightUnit: String
                let trailerType: String?
            }
            do {
                validation = try await api.query(
                    "hazmat.validateLoad",
                    input: ValidateInput(
                        loadId: Int(resolved.id),
                        hazmatClass: hazmatClass,
                        unNumber: (unNumber?.isEmpty == false) ? unNumber : nil,
                        weight: weight,
                        weightUnit: weightUnit,
                        trailerType: (trailerType?.isEmpty == false) ? trailerType : nil
                    )
                )
            } catch {
                validation = nil
                failures.append(error.eusoUserCopy)
            }

            if let unNumber, !unNumber.isEmpty {
                struct ErgInput: Encodable { let unNumber: String }
                do {
                    erg = try await api.query(
                        "hazmat.ergQuickLookup",
                        input: ErgInput(unNumber: unNumber)
                    )
                } catch {
                    erg = nil
                    failures.append(error.eusoUserCopy)
                }
            }

            struct Material: Encodable {
                let hazmatClass: String
                let unNumber: String?
                let weight: Double
                let weightUnit: String
            }
            struct PlacardInput: Encodable { let materials: [Material] }
            do {
                placards = try await api.query(
                    "hazmat.determinePlacards",
                    input: PlacardInput(materials: [
                        Material(
                            hazmatClass: hazmatClass,
                            unNumber: (unNumber?.isEmpty == false) ? unNumber : nil,
                            weight: weight,
                            weightUnit: weightUnit
                        )
                    ])
                )
            } catch {
                placards = nil
                failures.append(error.eusoUserCopy)
            }

            errorMessage = failures.isEmpty ? nil : failures.joined(separator: " ")
        } catch {
            clear()
            errorMessage = error.eusoUserCopy
        }
    }

    /// hazmat.validateLoad / determinePlacards accept only "lbs" or "kg".
    /// Anything else on the load row falls back to the server's own default
    /// unit rather than being sent as an invalid enum value.
    private func normalizedWeightUnit(_ raw: String?) -> String {
        switch raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "kg", "kgs", "kilogram", "kilograms": return "kg"
        default: return "lbs"
        }
    }
}

// MARK: - Screen

struct ShipperHazmatManifestGate: View {
    let loadId: String
    @StateObject private var store: HazmatGateStore204C
    @Environment(\.palette) private var palette

    init(loadId: String = "") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: HazmatGateStore204C(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(
                    eyebrow: "SHIPPER · HAZMAT · 49 CFR MANIFEST",
                    idText: store.load?.loadNumber ?? loadId,
                    title: "Manifest gate"
                )

                if let errorMessage = store.errorMessage {
                    DegradedNote(text: errorMessage)
                        .padding(.top, Space.s3)
                }

                if store.isLoading, store.load == nil {
                    ProgressView("Loading manifest checks")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s6)
                }

                if let load = store.load {
                    identityCard(load)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)

                    if let block = store.block {
                        blockedCard(block)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s4)
                    }

                    if let validation = store.validation {
                        SectionLabel("GATE VERDICT")
                            .padding(.top, Space.s5)
                        verdictCard(validation)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)

                        SectionLabel("MANIFEST GATES · 49 CFR / PHMSA · \(validation.checks.count)")
                            .padding(.top, Space.s5)
                        gateList(validation.checks)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)
                    }

                    if let placards = store.placards, !placards.placards.isEmpty {
                        SectionLabel("PLACARDING · 49 CFR 172.504")
                            .padding(.top, Space.s5)
                        placardList(placards)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)
                    }

                    resolutionGapNote
                        .padding(.top, Space.s5)
                }

                if !loadId.isEmpty {
                    AddendaCTAPair(
                        primary: "Re-run validation",
                        secondary: "Message ESang",
                        primaryLoading: store.isLoading,
                        onPrimary: { Task { await store.refresh() } }
                    )
                    .padding(.top, Space.s5)
                }

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .eusoRefreshable { await store.refresh() }
    }

    // MARK: DOT identity

    private func identityCard(_ load: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                placardDiamond
                VStack(alignment: .leading, spacing: 4) {
                    Text(identityTitle(load))
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(load.laneDisplay)
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
            factRow("HAZARD CLASS", load.hazmatClass?.isEmpty == false ? load.hazmatClass! : "Not recorded")
            factRow("UN NUMBER", load.unNumber?.isEmpty == false ? load.unNumber! : "Not recorded")
            factRow("WEIGHT", load.weightDisplay)
            if let erg = store.erg, erg.found {
                if let guideNumber = erg.guideNumber {
                    factRow("ERG GUIDE", "\(guideNumber)")
                }
                if let placard = erg.placard {
                    factRow("PLACARD", placard.uppercased())
                }
                if erg.isTIH == true {
                    hazardFlag("Toxic inhalation hazard · 49 CFR 172.505")
                }
                if erg.isWR == true {
                    hazardFlag("Marine pollutant / water-reactive · additional handling rules")
                }
            } else if store.erg != nil {
                factRow("ERG GUIDE", "UN number not found in ERG")
            }
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private func identityTitle(_ load: LoadsAPI.LoadDetail) -> String {
        if let erg = store.erg, erg.found, let name = erg.name, !name.isEmpty {
            return name
        }
        return load.commodityName ?? load.commodity ?? "Commodity not recorded"
    }

    /// DOT placard diamond. Painted in the house hazmat token — the server's
    /// `placardColor` hex is intentionally not used, so the diamond always
    /// reconciles to the app theme. The placard NAME (which is the regulated
    /// fact) comes from the server verbatim.
    private var placardDiamond: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Brand.hazmat.opacity(0.20))
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Brand.hazmat, lineWidth: 1.4)
                )
                .rotationEffect(.degrees(45))
            Text(store.load?.hazmatClass ?? "—")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Brand.hazmat)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 34)
        }
        .frame(width: 58, height: 58)
        .accessibilityLabel("Hazard class \(store.load?.hazmatClass ?? "not recorded") placard")
    }

    private func hazardFlag(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.danger)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Verdict

    private func verdictCard(_ validation: HazmatValidation204C) -> some View {
        let tone = verdictTone(validation.overallStatus)
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                AddendaIconChip(systemImage: tone.icon, tint: tone.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tone.title)
                        .font(EType.title)
                        .foregroundStyle(tone.color)
                    Text("\(validation.summary.pass) of \(validation.summary.total) checks passed · \(validation.summary.fail) failing · \(validation.summary.warn) warning")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            segmentedProgress(validation.checks)
            Text("This verdict covers only the checks the server was able to run for this load. Checks that need a driver, carrier, or packing group the load row does not carry simply do not appear — their absence is not a pass.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private func verdictTone(_ overallStatus: String) -> (title: String, color: Color, icon: String) {
        switch overallStatus.uppercased() {
        case "BLOCKED":
            return ("BLOCKED", Brand.danger, "xmark.octagon.fill")
        case "WARNING":
            return ("WARNING", Brand.warning, "exclamationmark.triangle.fill")
        case "CLEAR":
            return ("CLEAR", Brand.success, "checkmark.seal.fill")
        default:
            return (overallStatus.uppercased(), Brand.neutral, "questionmark.circle")
        }
    }

    private func segmentedProgress(_ checks: [HazmatCheck204C]) -> some View {
        HStack(spacing: 5) {
            ForEach(checks) { check in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(statusColor(check.status))
                    .frame(height: 6)
            }
        }
    }

    // MARK: Gates

    private func gateList(_ checks: [HazmatCheck204C]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                gateRow(check)
                if index < checks.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, 56)
                }
            }
        }
        .addendaPanel(palette)
    }

    private func gateRow(_ check: HazmatCheck204C) -> some View {
        let tint = statusColor(check.status)
        return HStack(alignment: .top, spacing: Space.s3) {
            AddendaIconChip(systemImage: statusIcon(check.status), tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(check.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.s2)
                    AddendaChip(text: statusLabel(check.status), color: tint)
                }
                Text(check.detail)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(check.regulation)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "pass": return Brand.success
        case "fail": return Brand.danger
        case "warn": return Brand.warning
        default: return Brand.neutral
        }
    }

    private func statusIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "pass": return "checkmark"
        case "fail": return "xmark"
        case "warn": return "exclamationmark"
        default: return "questionmark"
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status.lowercased() {
        case "pass": return "CLEARED"
        case "fail": return "BLOCKING"
        case "warn": return "WARNING"
        default: return status.uppercased()
        }
    }

    // MARK: Placards

    private func placardList(_ determination: PlacardDetermination204C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(determination.placards.enumerated()), id: \.element.id) { index, rule in
                HStack(alignment: .top, spacing: Space.s3) {
                    AddendaIconChip(
                        systemImage: rule.required ? "rhombus.fill" : "rhombus",
                        tint: rule.required ? Brand.hazmat : Brand.neutral
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(rule.placardName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                            Spacer(minLength: Space.s2)
                            AddendaChip(
                                text: rule.required ? "REQUIRED" : "OPTIONAL",
                                color: rule.required ? Brand.hazmat : Brand.neutral
                            )
                        }
                        Text(rule.reason)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.s4)
                if index < determination.placards.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, 56)
                }
            }
            if let note = determination.dangerousPlacardNote, !note.isEmpty {
                Divider().overlay(palette.borderFaint)
                Text(note)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.s4)
            }
        }
        .addendaPanel(palette)
    }

    // MARK: Blocked states

    private func blockedCard(_ block: HazmatGateBlock204C) -> some View {
        let copy: (String, String) = {
            switch block {
            case .notHazmat:
                return ("No hazard class on this load",
                        "The manifest gate evaluates a recorded DOT hazard class. This load has none, so no 49 CFR verdict is produced. If the shipment is regulated, record the hazard class and UN number on the load first.")
            case .missingWeight:
                return ("Gross weight not recorded",
                        "Placarding and financial-responsibility thresholds in 49 CFR are weight-driven. EusoTrip will not substitute a weight to force a verdict — record the load weight and re-run validation.")
            }
        }()
        return HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(copy.0)
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text(copy.1)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    // MARK: Named backend gap

    private var resolutionGapNote: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            SectionLabel("GATE RESOLUTION")
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("In-app gate resolution unavailable")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text("Clearing a failing gate from this screen would need a mutation that does not exist on the server (insurance.bindCargoEndorsement is not implemented). Resolve failing checks at their source — the driver endorsement, carrier hazmat registration, or trailer assignment — then re-run validation here.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .addendaPanel(palette)
            .padding(.horizontal, Space.s5)
        }
    }

    // MARK: Shared parts

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
}

#Preview("204C · Hazmat Manifest Gate · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperHazmatManifestGate()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("204C · Hazmat Manifest Gate · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperHazmatManifestGate()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
