//
//  ES04_PermitRequirements.swift
//  EusoTrip — Escort · ES-04 Permit & Requirements (per-state OS/OW matrix).
//
//  The state-by-state oversize/overweight compliance matrix an escort checks
//  before a permitted move. Wired to the real backend data (fix pack L10-3):
//    REAL  escorts.getStateRequirements → per-state escort thresholds, travel
//          restrictions, permit cost, and limits vs federal (was a [] stub).
//
//  This is a pure read surface; the load-route-specific getPermitPacket (permit
//  status joined to the load's route) is a follow-up.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire contracts (mirror escorts.getStateRequirements L10-3)

private struct StateLimits: Decodable { let maxHeightFt: Double?; let maxWidthFt: Double?; let maxGVWLb: Double? }
private struct StateEscortThresholds: Decodable {
    let frontEscortWidthFt: Double?
    let dualEscortWidthFt: Double?
    let heightPoleFt: Double?
    let lengthFt: Double?
    let weightLb: Double?
}
private struct StateTravel: Decodable {
    let curfewStart: Int?
    let curfewEnd: Int?
    let daylightOnly: Bool
    let weekendBan: Bool
    let holidayBan: Bool
    let maxSpeedMph: Int?
}
private struct StateRequirement: Decodable, Identifiable {
    let state: String
    let limits: StateLimits
    let escortThresholds: StateEscortThresholds
    let travel: StateTravel
    let permitRequired: Bool
    let permitCostEstimate: Double?
    let notes: String?
    let isDefaultRuleset: Bool
    var id: String { state }
}
private struct EmptyReqInput: Encodable {}

// MARK: - Screen

struct EscortPermitRequirements: View {
    @Environment(\.palette) private var palette

    @State private var requirements: [StateRequirement] = []
    @State private var loading = true
    @State private var query = ""
    @State private var errorMessage: String? = nil
    @State private var expanded: Set<String> = []

    private var filtered: [StateRequirement] {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty else { return requirements }
        return requirements.filter { $0.state.contains(q) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading state requirements…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    if let err = errorMessage { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                    searchField
                    VStack(spacing: 10) { ForEach(filtered) { stateCard($0) } }
                }
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .eusoRefreshTask { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "doc.badge.gearshape").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("ESCORT · PERMIT & REQUIREMENTS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("OS/OW state matrix").font(.system(size: 24, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Text("\(requirements.count) states · escort thresholds, curfews & permits")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textTertiary)
            TextField("Filter by state (e.g. TX)", text: $query)
                .font(EType.body).textInputAutocapitalization(.characters)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func stateCard(_ r: StateRequirement) -> some View {
        let isOpen = expanded.contains(r.state)
        return LifecycleCard {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    if isOpen { expanded.remove(r.state) } else { expanded.insert(r.state) }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(r.state)
                        .font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundStyle(.white)
                        .frame(width: 44, height: 34)
                        .background(LinearGradient.diagonal).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if r.travel.daylightOnly { chip("DAYLIGHT", Brand.warning) }
                            if r.travel.weekendBan { chip("NO WKND", Brand.danger) }
                            if r.isDefaultRuleset { chip("GENERIC", palette.textTertiary) }
                        }
                        Text(permitLine(r)).font(EType.mono(.micro)).tracking(0.3).foregroundStyle(palette.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textTertiary).rotationEffect(.degrees(isOpen ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                Rectangle().fill(palette.borderFaint.opacity(0.4)).frame(height: 1).padding(.vertical, 6)
                detailGrid(r)
                if let notes = r.notes, !notes.isEmpty {
                    Text(notes).font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                }
            }
        }
    }

    private func detailGrid(_ r: StateRequirement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metric("Front escort ≥", r.escortThresholds.frontEscortWidthFt.map { String(format: "%.1f ft wide", $0) })
            metric("Dual escort ≥", r.escortThresholds.dualEscortWidthFt.map { String(format: "%.1f ft wide", $0) })
            metric("Height pole ≥", r.escortThresholds.heightPoleFt.map { String(format: "%.1f ft tall", $0) })
            metric("Length escort ≥", r.escortThresholds.lengthFt.map { String(format: "%.0f ft", $0) })
            metric("Curfew", curfewText(r.travel))
            metric("Max speed", r.travel.maxSpeedMph.map { "\($0) mph" })
            metric("Permit", r.permitRequired ? (r.permitCostEstimate.map { String(format: "required · ~$%.0f/trip", $0) } ?? "required") : "not required")
        }
    }

    private func metric(_ label: String, _ value: String?) -> some View {
        HStack(spacing: 8) {
            Text(label).font(EType.caption).foregroundStyle(palette.textTertiary).frame(width: 118, alignment: .leading)
            Text(value ?? "—").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private func chip(_ t: String, _ tint: Color) -> some View {
        Text(t).font(.system(size: 8, weight: .heavy)).tracking(0.4).foregroundStyle(tint)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
    }

    private func permitLine(_ r: StateRequirement) -> String {
        var parts: [String] = []
        if r.permitRequired { parts.append(r.permitCostEstimate.map { String(format: "permit ~$%.0f", $0) } ?? "permit required") }
        if let s = r.travel.maxSpeedMph { parts.append("\(s) mph") }
        if let h = r.escortThresholds.heightPoleFt { parts.append(String(format: "pole ≥%.0fft", h)) }
        return parts.isEmpty ? "tap for detail" : parts.joined(separator: " · ")
    }

    private func curfewText(_ t: StateTravel) -> String? {
        guard let start = t.curfewStart, let end = t.curfewEnd else { return t.daylightOnly ? "daylight only" : nil }
        return String(format: "no travel %02d:00–%02d:00", start, end)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let rows: [StateRequirement] = try await EusoTripAPI.shared.query(
                "escorts.getStateRequirements", input: EmptyReqInput())
            requirements = rows.sorted { $0.state < $1.state }
        } catch {
            errorMessage = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't load state requirements. Try again."
        }
    }
}

// MARK: - Registered surface wrapper (id 607)

struct EscortPermitRequirementsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortPermitRequirements()
        } nav: {
            BottomNav(
                leading: EscortNavRoute.leading(current: .corridor),
                trailing: EscortNavRoute.trailing(current: .corridor),
                orbState: .idle
            )
        }
    }
}

#Preview("ES-04 · Permit & Requirements · Dark") {
    EscortPermitRequirementsScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("ES-04 · Permit & Requirements · Light") {
    EscortPermitRequirementsScreen(theme: Theme.light).preferredColorScheme(.light)
}
