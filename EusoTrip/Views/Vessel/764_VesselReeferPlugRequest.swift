//
//  764_VesselReeferPlugRequest.swift
//  EusoTrip — Vessel Operator · Reefer Plug Request (ALLOCATION SLOT-GRID).
//
//  Verbatim bespoke port of canonical wireframe "764 Vessel Reefer Plug
//  Request · Dark" (06 Vessel · Vessel Operator). ALLOCATION archetype,
//  purpose-built as a shore-power-vs-genset segmented selector over a
//  terminal plug-rack availability grid + a power summary — the REQUEST /
//  ALLOCATION step, deliberately DISTINCT from the reefer MONITORING
//  surfaces (702/799/818/820/821). Pre-arrival power booking for a
//  refrigerated container.
//
//  Docked under SHIPMENTS. transportMode=vessel · tri-country US·CA·MX.
//
//  REAL WIRING (tRPC):
//    · SC-GENSET "Generator Set (Reefer)" — FLAT $200, modes RAIL/VESSEL
//      (server/services/verticalPricingEngine.ts:80) backs the genset cost.
//    · createVesselBooking {cargoType, containerSize incl. reefer, set-point}
//      (server/routers/vesselShipments.ts:424) carries the reefer container.
//  STUB (handed to the-oath): reeferPlug.getRack / reeferPlug.requestAllocation
//  — there is no terminal plug-rack availability model nor an allocation
//  reservation verb today (reefer telemetry is enum-only). The rack grid +
//  power summary render the certified reference model; the request is a real
//  LOCAL compose action that surfaces the persistence gap honestly (it does
//  not fabricate a confirmed reservation).
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselReeferPlugRequestScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselReeferPlugRequestBody()
        } nav: {
            BottomNav.vesselOperatorShipments()
        }
    }
}

// MARK: - Model

private struct PlugSlot764: Identifiable {
    enum State { case available, occupied }
    let id: String            // "B-14"
    let state: State
}

private enum PowerSource764 { case shore, genset }

// MARK: - Body

private struct VesselReeferPlugRequestBody: View {
    @Environment(\.palette) private var palette

    // Real local compose state — the operator's choices.
    @State private var source: PowerSource764 = .shore
    @State private var selectedSlot: String = "B-14"
    @State private var requested = false

    // Certified reference rack (rack B · 18 slots). Available slots are
    // requestable; occupied slots are locked.
    private let slots: [PlugSlot764] = {
        let available: Set<String> = ["B-3", "B-5", "B-6", "B-8", "B-11", "B-12", "B-14", "B-15", "B-18"]
        return (1...18).map { i in
            let id = "B-\(i)"
            return PlugSlot764(id: id, state: available.contains(id) ? .available : .occupied)
        }
    }()

    private let cols = [GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDocTopBar(eyebrow: "VESSEL OPERATOR · REEFER PLUG",
                            idCaption: "USLGB PIER T",
                            title: "Plug request")
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s5) {
                heroCard
                sourceSection
                rackSection
                summarySection
                TriCountryAuthorityBand(title: "TERMINAL POWER · COLD-TREATMENT",
                                        regimes: powerRegimes)
                VesselDocCTAPair(primaryTitle: requested ? "Requested \(selectedSlot)" : "Request plug \(selectedSlot)",
                                 secondaryTitle: "Use genset",
                                 primaryIcon: requested ? "checkmark" : "bolt.fill",
                                 primaryDisabled: source == .genset,
                                 onPrimary: { withAnimation(.easeOut(duration: 0.12)) { requested = true } },
                                 onSecondary: { withAnimation(.easeOut(duration: 0.12)) { source = .genset } })
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("CONT MSCU7714028 · 40'HC reefer")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(requested ? "REQUESTED" : "PLUG NEEDED")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(requested ? Brand.success : Color(hex: 0xFFC246))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill((requested ? Brand.success : Color(hex: 0xFFC246)).opacity(0.16)))
            }
            Text(source == .shore ? "Shore-power slot — REQUEST" : "Genset fallback — SELECTED")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
            Text("set point −18°C · genset fallback")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 3)
            Text("USLGB Pier T · rack B · USDA cold-treat")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: Power-source segmented selector

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "POWER SOURCE", right: source == .shore ? "shore" : "genset")
            HStack(spacing: 4) {
                sourceOption("Shore power", isOn: source == .shore) {
                    withAnimation(.easeOut(duration: 0.12)) { source = .shore }
                }
                sourceOption("Genset fallback", isOn: source == .genset) {
                    withAnimation(.easeOut(duration: 0.12)) { source = .genset }
                }
            }
            .padding(4)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func sourceOption(_ title: String, isOn: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title)
                .font(.system(size: 11, weight: isOn ? .heavy : .bold))
                .foregroundStyle(isOn ? Color.white : palette.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background {
                    if isOn { Capsule().fill(LinearGradient.primary) }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Plug-rack grid

    private var rackSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "RACK B · PLUG AVAILABILITY",
                                right: source == .shore ? "\(availableCount) open" : "genset")
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(slots) { s in slotCell(s) }
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .opacity(source == .genset ? 0.5 : 1.0)

            VesselDocGapNote(text: "Reference plug-rack layout. Live availability + the allocation reservation land with the terminal plug endpoint.")
        }
    }

    private var availableCount: Int { slots.filter { $0.state == .available }.count }

    private func slotCell(_ s: PlugSlot764) -> some View {
        let isSelected = s.id == selectedSlot && source == .shore
        let isAvailable = s.state == .available
        return Button {
            guard isAvailable, source == .shore else { return }
            withAnimation(.easeOut(duration: 0.10)) {
                selectedSlot = s.id
                requested = false
            }
        } label: {
            Text(s.id)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(cellText(isSelected: isSelected, isAvailable: isAvailable))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LinearGradient.primary)
                    } else if isAvailable {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.bgCardSoft)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Brand.success, lineWidth: 1.5))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.textPrimary.opacity(0.06))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable || source == .genset)
    }

    private func cellText(isSelected: Bool, isAvailable: Bool) -> Color {
        if isSelected { return .white }
        if isAvailable { return Brand.success }
        return palette.textTertiary
    }

    // MARK: Power summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "DRAW · SET POINT · LOG", right: source == .shore ? "shore 60Hz" : "genset $200")
            HStack(spacing: 0) {
                summaryMetric("7.2 kW", "draw")
                summaryMetric("−18°C", "set point")
                summaryMetric("30-min", "log cadence")
            }
            .padding(.vertical, Space.s3)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func summaryMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Space.s4)
    }

    private var powerRegimes: [CountryRegime] {
        [
            .init(code: "US", authority: "US · USLGB", detail: "USDA cold-treat · 60Hz", consequence: nil, state: .active),
            .init(code: "CA", authority: "CA · CAVAN", detail: "CFIA · 60Hz", consequence: nil, state: .standby),
            .init(code: "MX", authority: "MX · MXZLO", detail: "SENASICA · 60Hz", consequence: nil, state: .standby),
        ]
    }
}

#Preview("764 · Vessel Reefer Plug Request · Night") {
    VesselReeferPlugRequestScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("764 · Vessel Reefer Plug Request · Light") {
    VesselReeferPlugRequestScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
