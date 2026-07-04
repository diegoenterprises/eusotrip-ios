//
//  VesselPortOpsCountryDone.swift
//  EusoTrip 2027 · 06 Vessel · PORT-OPS COUNTRY-DONE staging
//  STATIC-REVIEWED — NOT compile-verified in the Cowork build lane (⌘B owned by the-oath-apply).
//
//  Scope: takes the five PORT-OPS operator surfaces from US-only to COUNTRY-DONE —
//    655 Container Positions · 661 Port Calls · 704 Bay Plan · 698 Berth Window · 688 Sailing Schedule.
//  Port-ops country variation is THINNER than customs/money: it is PORT/TERMINAL AUTHORITY +
//  LOCAL TIME / FREE-TIME REGIME (lighter on currency). So instead of the vertical
//  TriCountryAuthorityBand used on the customs + money clusters, port-ops uses two NEW, lighter
//  affordances (also keeps the cluster from reading monotone — the #1 vessel defect):
//    • PortOpsCountryStrip  — a horizontal 3-COLUMN comparison strip (US | CA | MX), one column ACTIVE,
//      tap a column to switch active country. Used on 655 / 661 / 704.
//    • CountrySegment (already shipped in VesselTriCountryAuthorityBand.swift) — a 3-PILL row.
//      Used on 698 (allocation authority + local timezone) and 688 (destination import/VGM regime).
//
//  One country is ACTIVE; all three encoded + gated = COUNTRY-DONE. US rows are real today
//  (vessel-native procedures, verified live 2026-06-14/15). CA/MX live only in the cross-border
//  router → STANDBY until a vessel-scoped wrapper lands (NAMED-GAPS at the foot of this file).
//
//  Real port-authority strings are the operatingAuthority values from port_lookup (verified live):
//    CAVAN "Vancouver Fraser Port Authority" (VFPA) · MXZLO "API Manzanillo" (API = Administración
//    Portuaria Integral, the SCT/SEMAR port concession). Use verbatim in CA/MX columns.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Model (one column / one regime)

struct PortOpsRegime: Identifiable {
    let id = UUID()
    let code: String        // "US" | "CA" | "MX"
    let authority: String   // line 1 next to chip, e.g. "POLB · MTO"
    let line2: String       // e.g. "LFD + per-diem · FMC"
    let line3: String       // e.g. "$380/d · USD" (US) / "C$/day · CAD · STANDBY"
    let active: Bool
    /// optional accent on line3 for the active column (per-diem danger etc.); nil = default accent
    let line3IsDanger: Bool
}

// MARK: - Horizontal 3-column port-ops country strip (655 / 661 / 704)

struct PortOpsCountryStrip: View {
    @Environment(\.palette) private var palette
    let title: String                 // section eyebrow
    let regimes: [PortOpsRegime]      // expect exactly 3 (US, CA, MX)
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).kerning(1)
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: 7) {
                ForEach(regimes) { column($0) }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 14).fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.borderFaint, lineWidth: 1)))
        }
    }

    @ViewBuilder private func column(_ r: PortOpsRegime) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(r.code)
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(r.active ? Color.white : palette.textSecondary)
                    .frame(width: 22, height: 14)
                    .background {
                        if r.active { RoundedRectangle(cornerRadius: 4).fill(LinearGradient.primary) }
                        else { RoundedRectangle(cornerRadius: 4).fill(palette.textPrimary.opacity(0.10)) }
                    }
                Text(r.authority)
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(r.active ? Brand.blue : palette.textSecondary)
                    .lineLimit(1)
            }
            Text(r.line2).font(.system(size: 8.5)).foregroundStyle(palette.textSecondary).lineLimit(1)
            Text(r.line3)
                .font(.system(size: 8.5, weight: r.active ? .heavy : .bold))
                .foregroundStyle(r.line3IsDanger && r.active ? Brand.danger
                                 : (r.active ? Brand.blue : palette.textSecondary))
                .lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 48)
        .background(r.active ? AnyShapeStyle(LinearGradient.primary.opacity(0.10)) : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: 11))
        .contentShape(RoundedRectangle(cornerRadius: 11))
        .onTapGesture { onSelect(r.code) }
    }
}

// MARK: - Per-screen data (mirrors the committed SVGs verbatim)

enum VesselPortOpsCountryData {

    // 655 Container Positions — replaces the ESang row · "TRI-COUNTRY DISCHARGE · PORT AUTHORITY + FREE-TIME"
    static let containerPositions: [PortOpsRegime] = [
        .init(code: "US", authority: "POLB · MTO",  line2: "LFD + per-diem · FMC", line3: "$380/d · USD",            active: true,  line3IsDanger: true),
        .init(code: "CA", authority: "VFPA",        line2: "storage · CTA",        line3: "C$/day · CAD · STANDBY",  active: false, line3IsDanger: false),
        .init(code: "MX", authority: "API MZO",     line2: "estadías · SAT",       line3: "MX$/day · MXN · STANDBY", active: false, line3IsDanger: false),
    ]

    // 661 Port Calls — below the ESang card · "TRI-COUNTRY ARRIVAL · PRE-ARRIVAL AUTHORITY"
    static let portCalls: [PortOpsRegime] = [
        .init(code: "US", authority: "USCG · eNOA", line2: "−96h NVMC",        line3: "33 CFR 160 · ACTIVE", active: true,  line3IsDanger: false),
        .init(code: "CA", authority: "TC Marine",   line2: "96-hr PAIR",       line3: "MTSR · STANDBY",      active: false, line3IsDanger: false),
        .init(code: "MX", authority: "SEMAR",       line2: "Arribo/Despacho",  line3: "agente · STANDBY",    active: false, line3IsDanger: false),
    ]

    // 704 Bay Plan — between ESang card and CTA · "TRI-COUNTRY STOW · DISCHARGE TERMINAL AUTHORITY"
    static let bayPlan: [PortOpsRegime] = [
        .init(code: "US", authority: "POLB Pier T", line2: "VGM SOLAS VI/2", line3: "USCG · ACTIVE",  active: true,  line3IsDanger: false),
        .init(code: "CA", authority: "VFPA",        line2: "VGM SOLAS",      line3: "TC · STANDBY",   active: false, line3IsDanger: false),
        .init(code: "MX", authority: "API MZO",     line2: "VGM SOLAS",      line3: "SEMAR · STANDBY",active: false, line3IsDanger: false),
    ]

    // 698 Berth Window — CountrySegment (3 pills) above the CTA
    // title "TRI-COUNTRY BERTH · ALLOCATION AUTHORITY + LOCAL TIME"
    static let berthWindow: [CountryChip] = [
        .init(code: "US · POLB",    instrument: "Pier T · PDT", active: true),
        .init(code: "CA · VFPA",    instrument: "berth · PT",   active: false),
        .init(code: "MX · API MZO", instrument: "ventana · CT", active: false),
    ]

    // 688 Sailing Schedule — CountrySegment (3 pills) above the Book CTA
    // title "TRI-COUNTRY DESTINATION · IMPORT + VGM CUTOFF REGIME"
    static let sailingDestination: [CountryChip] = [
        .init(code: "US · CBP",  instrument: "ISF 10+2 · USD", active: true),
        .init(code: "CA · CBSA", instrument: "ACI · CAD",      active: false),
        .init(code: "MX · SAT",  instrument: "VUCEM · MXN",    active: false),
    ]
}

//
//  INSERTION POINTS (1:1 with the committed SVGs)
//  655: replace the ESang advisory row with
//       PortOpsCountryStrip(title: "TRI-COUNTRY DISCHARGE · PORT AUTHORITY + FREE-TIME",
//                           regimes: VesselPortOpsCountryData.containerPositions) { ... }
//  661: add below the ESang card (screen has no CTA pair)
//       PortOpsCountryStrip(title: "TRI-COUNTRY ARRIVAL · PRE-ARRIVAL AUTHORITY",
//                           regimes: VesselPortOpsCountryData.portCalls) { ... }
//  704: between the ESang card and the Resolve/Full-grid CTA pair
//       PortOpsCountryStrip(title: "TRI-COUNTRY STOW · DISCHARGE TERMINAL AUTHORITY",
//                           regimes: VesselPortOpsCountryData.bayPlan) { ... }
//  698: above the Book/List CTA pair
//       CountrySegment(chips: VesselPortOpsCountryData.berthWindow) { ... }   // + the eyebrow Text
//  688: above the single Book CTA (CTA slid down to make room)
//       CountrySegment(chips: VesselPortOpsCountryData.sailingDestination) { ... }
//
//  NAMED-GAP endpoints to build (hand to the-oath; US is real today, CA/MX STANDBY until wrapped):
//   • vesselShipments.getDischargeRegime({bookingId,country})       → {portAuthority,freeTimeBasis,perDiemRate,currency}   (655)
//   • vesselShipments.getArrivalRegime({serviceLoop|vesselImo,country}) → {authority,instrument,timing}                   (661; same shape proposed for 672)
//   • vesselShipments.getStowAuthority({vesselImo,dischargePort,country}) → {terminal,vgmRegime,nationalAuthority}        (704)
//   • vesselShipments.getBerthAllocationRegime({portId,country})    → {authority,timezone,currency}                       (698)
//   • vesselShipments.getDestinationRegime({voyageId,country})      → {customsAuthority,entryInstrument,currency}         (688)
//  US backing real today: getVesselShipments / getVesselShipmentDetail / getBerthSchedule(:1101) / getVesselSchedules(:637)
//  / getContainerPositions(:1282) / getContainerTracking(:738). CA/MX exist only in crossBorder.ts (ACI / pedimento /
//  getTrustedPrograms:3350) → paint STANDBY. acceptance test = active-country read returns + tapping a column re-reads.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

// MARK: - Previews

#Preview("Port-ops country strip · Dark") {
    VStack(spacing: 16) {
        PortOpsCountryStrip(title: "TRI-COUNTRY DISCHARGE · PORT AUTHORITY + FREE-TIME",
                            regimes: VesselPortOpsCountryData.containerPositions)
        PortOpsCountryStrip(title: "TRI-COUNTRY ARRIVAL · PRE-ARRIVAL AUTHORITY",
                            regimes: VesselPortOpsCountryData.portCalls)
    }
    .padding()
    .background(Theme.dark.bgPage)
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("Port-ops country strip · Light") {
    VStack(spacing: 16) {
        PortOpsCountryStrip(title: "TRI-COUNTRY STOW · DISCHARGE TERMINAL AUTHORITY",
                            regimes: VesselPortOpsCountryData.bayPlan)
        CountrySegment(chips: VesselPortOpsCountryData.berthWindow)
    }
    .padding()
    .background(Theme.light.bgPage)
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
