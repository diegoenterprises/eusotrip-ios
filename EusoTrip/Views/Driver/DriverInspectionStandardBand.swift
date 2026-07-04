//
//  DriverInspectionStandardBand.swift
//  EusoTrip — COUNTRY-DONE band for the Driver DVIR surface (wireframe 104 DVIR).
//
//  1:1 port of the "PRE-TRIP INSPECTION STANDARD · BY COUNTRY" rail added to
//  `01 Driver/{Light,Dark}-SVG/104 DVIR.svg`. A thin 3-segment rail
//  (US active / CA / MX) declaring which inspection regulation the DVIR certifies
//  under — the standard + cadence gate on the driver's jurisdiction.
//
//  Wiring:
//    • active jurisdiction      → detectLoadCountry (loads router)
//    • regulation + defect taxonomy switch → STUB·named-gap → the-oath:
//          dvir.getInspectionStandard(country)
//      (DVIR reads/writes EXIST: dvir.listMine, inspections.create, drivers.submitDVIR).
//  GATE: OOS-defect submit block already enforced US-side
//        (ComplianceRulesAutomation); per-country taxonomy via the STUB.
//  RBAC: auditedOperationsProcedure (driver-scoped). transportMode: truck.
//

import SwiftUI

/// Real pre-trip inspection standard per jurisdiction (typed reference table).
struct InspectionStandard: Identifiable {
    let jx: DriverJurisdiction
    let cite: String        // statutory citation
    let cadence: String     // required frequency
    var id: String { jx.rawValue }

    static let table: [InspectionStandard] = [
        .init(jx: .us, cite: "49 CFR 396.11", cadence: "daily"),
        .init(jx: .ca, cite: "NSC Std 13",    cadence: "trip · 24h"),
        .init(jx: .mx, cite: "NOM-068-SCT",   cadence: "per dispatch"),
    ]
}

struct DriverInspectionStandardBand: View {
    @Environment(\.palette) private var palette
    let active: DriverJurisdiction

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRE-TRIP INSPECTION STANDARD · BY COUNTRY")
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 0) {
                ForEach(InspectionStandard.table) { s in
                    segment(s, isActive: s.jx == active)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.borderFaint))
    }

    private func segment(_ s: InspectionStandard, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Text(s.jx.code)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(isActive ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textSecondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(s.cite).font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(isActive ? palette.textPrimary : palette.textSecondary)
                Text(s.cadence).font(.system(size: 6.8, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4).padding(.leading, 6)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(isActive ? AnyShapeStyle(LinearGradient.primary.opacity(0.08)) : AnyShapeStyle(Color.clear)))
    }
}

// MARK: - Previews

#Preview("Inspection Standard Band · Dark") {
    DriverInspectionStandardBand(active: .us)
        .padding()
        .background(Theme.dark.bgPage)
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("Inspection Standard Band · Light") {
    DriverInspectionStandardBand(active: .us)
        .padding()
        .background(Theme.light.bgPage)
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
