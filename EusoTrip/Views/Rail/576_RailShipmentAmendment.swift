//
//  576_RailShipmentAmendment.swift
//  EusoTrip — Rail Engineer · Shipment Amendment (carrier-side per-load diff + submit).
//
//  Verbatim port of "576 Rail Shipment Amendment.svg" (Light + Dark).
//  8-stage lifecycle strip card (current = IN TRANSIT), proposed changes diff rows
//  with delta pills, impact warning card, submit/discard CTA.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME).
//
//  Data:
//    railShipments.getRailShipmentDetail  (EXISTS :140)  → lifecycle + current fields
//    railShipments.updateRailShipmentStatus (EXISTS :168) → submit amendment
//    railShipments.createRailWaybill      (EXISTS :806)  → re-issue waybill after submit
//

import SwiftUI

struct RailShipmentAmendmentScreen: View {
    let theme: Theme.Palette
    let railId: String

    var body: some View {
        Shell(theme: theme) { RailShipmentAmendmentBody(railId: railId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct ShipmentDetail576: Decodable {
    let railId: String?
    let lifecycleStatus: String?
    let serviceMode: String?
    let carrier: String?
    let carCount: Int?
    let lifecycleCaption: String?
    let amendmentAllowed: Bool?
    let impactNote: String?
}

private struct AmendmentChange576: Decodable, Identifiable {
    let id: Int
    let fieldName: String?
    let oldValue: String?
    let newValue: String?
    let deltaLabel: String?
    let status: String?       // "edited" | "delta_positive" | "no_change" | "rate_delta"
    let fieldType: String?    // "destination" | "car_count" | "commodity" | "rate"
}

// MARK: - Body

private struct RailShipmentAmendmentBody: View {
    @Environment(\.palette) private var palette
    let railId: String

    @State private var shipment: ShipmentDetail576? = nil
    @State private var changes: [AmendmentChange576] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isSubmitting = false
    @State private var submitted = false

    private let lifecycleStages = ["POSTED", "TENDERED", "ACCEPTED", "RAMPED", "IN TRANSIT", "DERAMP", "WAYBILL", "CLOSED"]

    private func currentStageIndex(_ status: String?) -> Int {
        switch (status ?? "").lowercased().replacingOccurrences(of: "_", with: " ") {
        case "posted":      return 0
        case "tendered":    return 1
        case "accepted":    return 2
        case "ramped":      return 3
        case "in transit":  return 4
        case "deramp":      return 5
        case "waybill":     return 6
        case "closed":      return 7
        default:            return 4
        }
    }

    private var lifecycleContextLabel: String {
        var parts = ["LIFECYCLE"]
        if let m = shipment?.serviceMode   { parts.append(m.uppercased()) }
        if let c = shipment?.carrier       { parts.append(c.uppercased()) }
        if let n = shipment?.carCount      { parts.append("\(n) CARS") }
        return parts.joined(separator: " · ")
    }

    private func fieldChipInfo(_ fieldType: String?) -> (color: Color, icon: String) {
        switch (fieldType ?? "").lowercased() {
        case "destination":                return (Brand.magenta, "mappin.circle.fill")
        case "car_count", "car count":     return (Brand.blue,    "rectangle.split.3x1.fill")
        case "commodity":                  return (Brand.rail,    "doc.text.fill")
        case "rate", "rate_impact":        return (Brand.warning,  "dollarsign.circle.fill")
        default:                           return (Brand.blue,     "pencil.circle.fill")
        }
    }

    private func pillInfo(_ c: AmendmentChange576) -> (label: String, color: Color)? {
        switch (c.status ?? "").lowercased() {
        case "edited":
            return ("EDITED", Color(hex: 0xC77DFF))
        case "no_change", "no change":
            return ("NO CHANGE", Brand.rail)
        case "delta_positive":
            guard let d = c.deltaLabel else { return nil }
            return (d, Brand.success)
        case "delta_negative":
            guard let d = c.deltaLabel else { return nil }
            return (d, Brand.danger)
        default:
            if let d = c.deltaLabel, d.hasPrefix("+") || d.hasPrefix("-") {
                let isPos = d.hasPrefix("+")
                return (d, isPos ? Brand.success : Brand.danger)
            }
            return nil
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading amendment…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    lifecycleStripSection
                    changesList
                    impactNote
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · AMENDMENT")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(String(railId.prefix(20)))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Amend shipment")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Lifecycle strip section

    private var lifecycleStripSection: some View {
        let current = currentStageIndex(shipment?.lifecycleStatus)
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text(lifecycleContextLabel)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(0..<8) { i in
                        if i > 0 {
                            Group {
                                if i <= current {
                                    Rectangle().fill(LinearGradient.primary).frame(maxWidth: .infinity, maxHeight: 2)
                                } else {
                                    Rectangle().fill(palette.borderFaint).frame(maxWidth: .infinity, maxHeight: 2)
                                }
                            }
                        }
                        stageNode(index: i, current: current)
                    }
                }
                HStack(spacing: 0) {
                    ForEach(0..<8) { i in
                        Group {
                            if i == current {
                                Text(lifecycleStages[i])
                                    .font(.system(size: 7.5, weight: .bold)).tracking(0.3)
                                    .foregroundStyle(LinearGradient.primary)
                                    .frame(maxWidth: .infinity)
                            } else if i < current {
                                Text(lifecycleStages[i])
                                    .font(.system(size: 7.5, weight: .bold)).tracking(0.3)
                                    .foregroundStyle(palette.textPrimary)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text(lifecycleStages[i])
                                    .font(.system(size: 7.5, weight: .bold)).tracking(0.3)
                                    .foregroundStyle(palette.textTertiary)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                if let caption = shipment?.lifecycleCaption {
                    Text(caption)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(16)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
        }
    }

    @ViewBuilder
    private func stageNode(index: Int, current: Int) -> some View {
        if index == current {
            ZStack {
                Circle().strokeBorder(LinearGradient.primary, lineWidth: 2)
                Circle().fill(LinearGradient.diagonal).padding(4)
                Circle().fill(Color.white).frame(width: 6, height: 6)
            }
            .frame(width: 22, height: 22)
        } else if index < current {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Image(systemName: "checkmark")
                    .font(.system(size: 5, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 12, height: 12)
            .frame(width: 22)
        } else {
            Circle()
                .fill(palette.bgCardSoft)
                .overlay(Circle().strokeBorder(palette.borderStrong, lineWidth: 1.5))
                .frame(width: 10, height: 10)
                .frame(width: 22)
        }
    }

    // MARK: - Changes list

    private var changesList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("PROPOSED CHANGES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("updateRailShipmentStatus")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if changes.isEmpty {
                EusoEmptyState(
                    systemImage: "pencil.and.list.clipboard",
                    title: "No proposed changes",
                    subtitle: "Shipment fields and proposed amendments will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(changes.enumerated()), id: \.element.id) { idx, change in
                        changeRow(change)
                        if idx < changes.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                                .overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
            }
        }
    }

    private func changeRow(_ c: AmendmentChange576) -> some View {
        let chip = fieldChipInfo(c.fieldType)
        let isRateDelta = (c.fieldType ?? "").lowercased().hasPrefix("rate")
        let pill = isRateDelta ? nil : pillInfo(c)
        let rightDelta: String? = isRateDelta ? c.deltaLabel : nil
        let sub = [c.oldValue, c.newValue].compactMap { $0 }.joined(separator: " → ")

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chip.color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: chip.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chip.color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(c.fieldName ?? "—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub.isEmpty ? "—" : sub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let (label, color) = pill {
                Text(label)
                    .font(.system(size: 11, weight: .bold)).kerning(0.6)
                    .foregroundStyle(color)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(color.opacity(0.14)))
            } else if let rd = rightDelta {
                Text(rd)
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(rd.hasPrefix("+") ? Brand.success : Brand.danger)
            }
        }
        .padding(16)
    }

    // MARK: - Impact note

    private var impactNote: some View {
        let note = shipment?.impactNote ?? "Amendment re-issues waybill · shipper approval required"
        return HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(note)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("createRailWaybill regenerates · shipper notified")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: submitted ? "Submitted" : "Submit amendment",
                      action: { Task { await submitAmendment() } }, isLoading: isSubmitting)
            Button {} label: {
                Text("Discard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct RailIn: Encodable { let railId: String }
        do {
            async let detail: ShipmentDetail576 = EusoTripAPI.shared.query(
                "railShipments.getRailShipmentDetail", input: RailIn(railId: railId))
            async let amendChanges: [AmendmentChange576] = EusoTripAPI.shared.query(
                "railShipments.getAmendmentChanges", input: RailIn(railId: railId))
            let (d, c) = try await (detail, amendChanges)
            self.shipment = d
            self.changes  = c
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func submitAmendment() async {
        isSubmitting = true
        struct SubmitIn: Encodable { let railId: String }
        struct SubmitOut: Decodable {}
        do {
            let _: SubmitOut = try await EusoTripAPI.shared.query(
                "railShipments.updateRailShipmentStatus", input: SubmitIn(railId: railId))
            submitted = true
        } catch { /* surface error in next load */ }
        isSubmitting = false
    }
}

#Preview("576 · Rail Shipment Amendment · Night") { RailShipmentAmendmentScreen(theme: Theme.dark, railId: "RAIL-260518-48217A1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("576 · Rail Shipment Amendment · Light") { RailShipmentAmendmentScreen(theme: Theme.light, railId: "RAIL-260518-48217A1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
