//
//  DriverJurisdiction.swift
//  EusoTrip — shared tri-country (US·CA·MX) jurisdiction model for the Driver
//  compliance cluster COUNTRY-DONE bands (078 / 079 / 104).
//
//  Staged 2026-06-15 by the truck build lane for the-oath-apply to integrate.
//  The active jurisdiction is resolved from the driver's current position /
//  active load via `detectLoadCountry` (frontend/server/routers/loads.ts:107),
//  which maps a state/province abbreviation → "US" | "CA" | "MX".
//
//  0% mock doctrine: the per-jurisdiction REGULATORY CONSTANTS below are real
//  law (49 CFR Part 395/396 · SOR/2005-313 · NOM-087-SCT / NOM-068-SCT), kept as
//  a typed reference table — they are constants, not fabricated live values.
//  The LIVE pieces (which jurisdiction is active now; recomputing the driver's
//  actual clocks/standard against it) come from real endpoints; where no such
//  endpoint exists on disk it is flagged STUB·named-gap in each band header and
//  handed to the-oath. Constants cross-checked against the platform
//  `cross_border_hos` reference (US/CA/MX HOS comparison) on 2026-06-15.
//

import SwiftUI

/// Operating jurisdiction for a truck driver. Resolved server-side from the
/// active load / current GPS state via `detectLoadCountry` (loads.ts:107).
enum DriverJurisdiction: String, CaseIterable, Codable, Identifiable {
    case us = "US", ca = "CA", mx = "MX"
    var id: String { rawValue }
    var code: String { rawValue }

    /// Sovereign road-safety authority shown on compliance surfaces.
    var authority: String {
        switch self {
        case .us: return "FMCSA"
        case .ca: return "Transport Canada / NSC"
        case .mx: return "SICT (SCT)"
        }
    }
}
