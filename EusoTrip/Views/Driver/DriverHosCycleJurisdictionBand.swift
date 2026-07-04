//
//  DriverHosCycleJurisdictionBand.swift
//  EusoTrip — COUNTRY-DONE band for the Driver compliance surface (wireframe 078 Home Compliance).
//
//  1:1 port of the "HOS CYCLE · BY JURISDICTION" ledger added to
//  `01 Driver/{Light,Dark}-SVG/078 Home Compliance.svg`. A 3-row
//  ledger (US active / CA / MX) that makes the cycle window BASIS
//  explicit and switches it on the driver's jurisdiction.
//
//  Wiring:
//    • active jurisdiction  → detectLoadCountry (loads router) on current position
//    • cycle figures redraw  → STUB·named-gap → the-oath:
//          eld.getActiveHosRuleset(jurisdiction) / hos.getCycleRule(country)
//      (getDriverHosWindow is 49-CFR-395-only; no per-country
//       ruleset endpoint exists on disk — surfaced to the-oath).
//    • constants grounded in the platform cross_border_hos reference (verified 2026-06-15).
//  RBAC: driverProcedure. transportMode: truck.
//

import SwiftUI

/// Real HOS cycle rule per jurisdiction (typed reference table — statutory constants, not mock).
struct HosCycleRule: Identifiable {
    let jx: DriverJurisdiction
    let ruleset: String      // statutory citation
    let cycle: String        // cycle hours / day window
    let reset: String        // restart / reset rule
    let basis: String        // applicability note
    var id: String { jx.rawValue }

    /// Constants per 49 CFR Part 395 (US) · SOR/2005-313 (CA) · NOM-087-SCT (MX).
    static let table: [HosCycleRule] = [
        .init(jx: .us, ruleset: "49 CFR 395",   cycle: "70h / 8-day", reset: "34h restart", basis: "property carrier · interstate"),
        .init(jx: .ca, ruleset: "SOR/2005-313", cycle: "70h / 7-day", reset: "36h reset",   basis: "property carrier · south of 60°N"),
        .init(jx: .mx, ruleset: "NOM-087-SCT",  cycle: "72h / 7-day", reset: "24h rest",    basis: "property carrier · jornada"),
    ]
}

struct DriverHosCycleJurisdictionBand: View {
    @Environment(\.palette) private var palette
    /// Resolved from detectLoadCountry on the driver's current position.
    let active: DriverJurisdiction

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HOS CYCLE · BY JURISDICTION")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("ACTIVE · \(active.code)")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                    .foregroundStyle(LinearGradient.primary)
            }
            VStack(spacing: 0) {
                ForEach(Array(HosCycleRule.table.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Rectangle().fill(palette.borderFaint).frame(height: 1) }
                    row(r, isActive: r.jx == active)
                }
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
        }
    }

    private func row(_ r: HosCycleRule, isActive: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(r.jx.code)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(isActive ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textSecondary))
                .frame(width: 34, height: 22)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? AnyShapeStyle(LinearGradient.primary.opacity(0.18))
                                   : AnyShapeStyle(Color(white: 0.45).opacity(0.16))))
            VStack(alignment: .leading, spacing: 2) {
                Text(r.ruleset)
                    .font(.system(size: 11.5, weight: .heavy))
                    .foregroundStyle(isActive ? palette.textPrimary : palette.textSecondary)
                Text(r.basis)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(r.cycle).font(.system(size: 13, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(isActive ? palette.textPrimary : palette.textSecondary)
                Text(r.reset).font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isActive ? Brand.success : palette.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(isActive ? AnyShapeStyle(LinearGradient.primary.opacity(0.08)) : AnyShapeStyle(Color.clear)))
    }
}

// MARK: - Previews

#Preview("HOS Cycle Band · Dark") {
    DriverHosCycleJurisdictionBand(active: .us)
        .padding()
        .background(Theme.dark.bgPage)
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("HOS Cycle Band · Light") {
    DriverHosCycleJurisdictionBand(active: .us)
        .padding()
        .background(Theme.light.bgPage)
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
