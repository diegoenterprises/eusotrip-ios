//
//  DriverCrossBorderLicenceBand.swift
//  EusoTrip — COUNTRY-DONE band for the Driver credentials surface (wireframe 079 Certifications Documents).
//
//  1:1 port of the "LICENCE TO DRIVE · BY COUNTRY" passport strip added to
//  `01 Driver/{Light,Dark}-SVG/079 Certifications Documents.svg`.
//  Three columns (US active / CA / MX) showing the commercial-licence document
//  the driver must carry to be legal to drive in each country — the cross-border
//  equivalence of the CDL hero above it.
//
//  Wiring:
//    • active jurisdiction  → detectLoadCountry (loads router)
//    • licence equivalence  → STUB·named-gap → the-oath:
//          credentials.getLicenceByJurisdiction(country)
//      (licence-equivalence map atop the existing wallet fuse;
//       underlying cert reads EXIST: drivers.getCertifications,
//       profile.getCertifications, training.getExpiringCertifications).
//  RBAC: protectedProcedure (driver self). transportMode: truck.
//

import SwiftUI

/// Real commercial-licence regime per jurisdiction (typed reference table).
struct LicenceRegime: Identifiable {
    let jx: DriverJurisdiction
    let licence: String     // licence class / document
    let extras: String      // accompanying credentials
    var id: String { jx.rawValue }

    static let table: [LicenceRegime] = [
        .init(jx: .us, licence: "Class A",       extras: "DOT med · TWIC"),
        .init(jx: .ca, licence: "Class 1 / AZ",  extras: "FAST · abstract"),
        .init(jx: .mx, licence: "Lic. Federal",  extras: "examen psicofísico"),
    ]
}

struct DriverCrossBorderLicenceBand: View {
    @Environment(\.palette) private var palette
    let active: DriverJurisdiction

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(LicenceRegime.table.enumerated()), id: \.element.id) { i, r in
                column(r, isActive: r.jx == active)
                if i < LicenceRegime.table.count - 1 {
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 34)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint))
        .overlay(alignment: .topLeading) {
            Text("LICENCE TO DRIVE · BY COUNTRY")
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
                .padding(.leading, 16).padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            Text("ACTIVE · \(active.code)")
                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                .foregroundStyle(LinearGradient.primary)
                .padding(.trailing, 16).padding(.top, 8)
        }
    }

    private func column(_ r: LicenceRegime, isActive: Bool) -> some View {
        VStack(spacing: 3) {
            Text(r.jx.code)
                .font(.system(size: 9.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(isActive ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textSecondary))
            Text(r.licence)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(isActive ? palette.textPrimary : palette.textSecondary)
            Text(r.extras)
                .font(.system(size: 7.6, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 11)
                    .fill(LinearGradient.primary.opacity(0.08))
                    .padding(.horizontal, 6)
            }
        }
    }
}

// MARK: - Previews

#Preview("Licence Band · Dark") {
    DriverCrossBorderLicenceBand(active: .us)
        .padding()
        .background(Theme.dark.bgPage)
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("Licence Band · Light") {
    DriverCrossBorderLicenceBand(active: .us)
        .padding()
        .background(Theme.light.bgPage)
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
