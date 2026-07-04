//
//  VesselLandfallRegimeRail.swift
//  EusoTrip 2027 · 06 Vessel · VISIBILITY/TRACKING COUNTRY-DONE staging
//  STATIC-REVIEWED — NOT compile-verified in the Cowork build lane (⌘B owned by the-oath-apply).
//
//  Scope: takes the four VISIBILITY / TRACKING surfaces from US-only to COUNTRY-DONE —
//    003 Vessel Live Tracking (Shipper) · 660 Vessel Live Position (Operator) ·
//    666 Vessel Container Timeline (Operator) · 707 Vessel Container Movement Log (Operator).
//
//  The country axis for a tracking surface is NOT a currency badge — it is the DESTINATION /
//  DISCHARGE country, which decides the arrival-notice regime, the customs entry/release
//  instrument, and the free-time/per-diem currency. So this cluster introduces a NEW affordance,
//  deliberately distinct from the customs vertical band, the money band, and the port-ops
//  horizontal strip / 3-pill segment, to keep the catalog from reading monotone (the #1 vessel
//  defect):
//
//    • LandfallRegimeRail — a route-SPINE of three destination-port flag waypoints
//      (US Long Beach · CA Vancouver · MX Manzanillo) sitting on a thin rule that echoes the
//      screen's own voyage/route line. The ACTIVE waypoint is ringed (cardRim) + column-tinted;
//      the two STANDBY waypoints are muted. Two render variants so the four screens don't clone:
//        - .evenWaypoints  (660, 666): three evenly-spread waypoints, each labelled port + regime.
//        - .selectorCaption (003, 707): three flag waypoints on the left + an active-regime caption
//          block on the right.
//
//  One country is ACTIVE; all three encoded + tappable + gated = COUNTRY-DONE. US is real today
//  (vessel-native reads, verified live 2026-06-15). CA/MX maritime doc logic EXISTS as a SERVICE
//  (server/services/crossBorderVessel.ts — CA_import ACI Ocean eManifest :114, MX_import
//  pedimento/VUCEM :116; getRequiredVesselDocs / checkVesselCrossBorderCompliance imported
//  crossBorder.ts:39) but is NOT surfaced at the vessel tRPC layer → STANDBY until the named-gap
//  resolver lands (foot of this file).
//
//  PRODUCTION GATE (build-lane): the rail's onSelect must call the intent-level resolver
//  vessel.getLandfallRegime (NOT a raw router) and re-key the screen off booking.direction /
//  discharge country. Any agent/tool payload built from this must pin JSON key order
//  (Swift .sortedKeys) so the provider cache (Gemini today / Apple FM next) is not invalidated.
//  Hand the missing endpoint + its test + (where ESang re-keys copy) its eval to the-oath.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Model (one destination-port landfall regime)

struct LandfallRegime: Identifiable {
    let id = UUID()
    let code: String            // "US" | "CA" | "MX"
    let port: String            // "US · LONG BEACH" | "CA · VANCOUVER" | "MX · MANZANILLO"
    let portShort: String       // "US·LGB" | "CA·VAN" | "MX·ZLO" (or terminal: "US·LBCT")
    let regimeLine: String      // per-screen: arrival instrument / release instrument / free-time basis
    let flag: Flag              // which flag glyph to draw
    let active: Bool

    enum Flag { case us, ca, mx }
}

extension LandfallRegime {
    /// 003 / 660 — ARRIVAL regime (USCG eNOA / TC PAIR / SEMAR Arribo) + currency.
    static let arrival: [LandfallRegime] = [
        .init(code: "US", port: "US · LONG BEACH", portShort: "US·LGB", regimeLine: "USCG eNOA · USD", flag: .us, active: true),
        .init(code: "CA", port: "CA · VANCOUVER",  portShort: "CA·VAN", regimeLine: "TC PAIR · CAD",   flag: .ca, active: false),
        .init(code: "MX", port: "MX · MANZANILLO", portShort: "MX·ZLO", regimeLine: "SEMAR · MXN",     flag: .mx, active: false),
    ]
    /// 666 — DESTINATION-RELEASE regime (CBP ACE / CBSA ACI / SAT Pedimento).
    static let release: [LandfallRegime] = [
        .init(code: "US", port: "US · LONG BEACH", portShort: "US·LGB · CBP ACE",  regimeLine: "release on discharge", flag: .us, active: true),
        .init(code: "CA", port: "CA · VANCOUVER",  portShort: "CA·VAN · CBSA ACI", regimeLine: "RNS release",          flag: .ca, active: false),
        .init(code: "MX", port: "MX · MANZANILLO", portShort: "MX·ZLO · SAT PED",  regimeLine: "VUCEM · previo",       flag: .mx, active: false),
    ]
    /// 707 — TERMINAL FREE-TIME regime (FMC 46 CFR 541 / CTA·VFPA / SAT·API) + currency.
    static let terminalFreeTime: [LandfallRegime] = [
        .init(code: "US", port: "US · LBCT",  portShort: "US·LBCT", regimeLine: "FMC 46 CFR 541 · USD", flag: .us, active: true),
        .init(code: "CA", port: "CA · VFPA",  portShort: "CA·VFPA", regimeLine: "CTA tariff · CAD",     flag: .ca, active: false),
        .init(code: "MX", port: "MX · API",   portShort: "MX·ZLO",  regimeLine: "SAT estadías · MXN",   flag: .mx, active: false),
    ]
}

// MARK: - Flag glyph (recognizable at 18×12; mirrors the SVG flags)

struct LandfallFlag: View {
    let kind: LandfallRegime.Flag
    var muted: Bool = false
    var body: some View {
        ZStack {
            switch kind {
            case .us:
                Color.white
                Rectangle().fill(Color(red: 0.235, green: 0.231, blue: 0.431)) // #3C3B6E
                    .frame(width: 8, height: 6).offset(x: -5, y: -3)
                VStack(spacing: 1.5) {
                    Spacer()
                    Rectangle().fill(Color(red: 0.698, green: 0.133, blue: 0.204)).frame(height: 1.6) // #B22234
                    Rectangle().fill(Color(red: 0.698, green: 0.133, blue: 0.204)).frame(height: 1.6)
                }
            case .ca:
                Color.white
                HStack {
                    Rectangle().fill(Color(red: 0.835, green: 0.169, blue: 0.118)).frame(width: 4) // #D52B1E
                    Spacer()
                    Rectangle().fill(Color(red: 0.835, green: 0.169, blue: 0.118)).frame(width: 4)
                }
                Circle().fill(Color(red: 0.835, green: 0.169, blue: 0.118)).frame(width: 4.4, height: 4.4)
            case .mx:
                HStack(spacing: 0) {
                    Rectangle().fill(Color(red: 0.0, green: 0.408, blue: 0.278))   // #006847
                    Rectangle().fill(Color.white)
                    Rectangle().fill(Color(red: 0.808, green: 0.067, blue: 0.149)) // #CE1126
                }
                Circle().fill(Color(red: 0.549, green: 0.384, blue: 0.224)).frame(width: 3, height: 3)
            }
        }
        .frame(width: 18, height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 1))
        .opacity(muted ? 0.6 : 1)
    }
}

// MARK: - The rail

struct LandfallRegimeRail: View {
    @Environment(\.palette) private var palette
    enum Variant { case evenWaypoints, selectorCaption }

    let eyebrow: String                 // e.g. "ARRIVAL LANDFALL · GATES ON DISCHARGE PORT"
    let trailingEyebrow: String?        // e.g. "GATES ON DESTINATION" (selectorCaption only)
    let regimes: [LandfallRegime]       // expect exactly 3 (US, CA, MX)
    let variant: Variant
    /// active-regime caption lines for .selectorCaption (003 arrival / 707 free-time)
    var captionLines: [CaptionLine] = []
    var onSelect: (String) -> Void = { _ in }

    struct CaptionLine: Identifiable { let id = UUID(); let text: String; let tone: Tone
        enum Tone { case primary, secondary, success, warning } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(eyebrow).font(.system(size: 9, weight: .heavy)).kerning(0.9)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                if let t = trailingEyebrow {
                    Text(t).font(.system(size: 8, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.bottom, 10)

            switch variant {
            case .evenWaypoints:   evenWaypoints
            case .selectorCaption: selectorCaption
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.borderFaint, lineWidth: 1)))
    }

    // 660 / 666 — three evenly-spread waypoints, each labelled port + regime line.
    private var evenWaypoints: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(regimes) { r in
                Button { onSelect(r.code) } label: { waypoint(r) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(alignment: .top) {        // the route-spine
            Rectangle().fill(Color(red: 0.078, green: 0.451, blue: 1).opacity(0.30))
                .frame(height: 1.6).padding(.horizontal, 28).padding(.top, 9)
        }
    }

    @ViewBuilder private func waypoint(_ r: LandfallRegime) -> some View {
        VStack(spacing: 5) {
            LandfallFlag(kind: r.flag, muted: !r.active)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 3).fill(palette.bgElev)
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .stroke(r.active ? AnyShapeStyle(LinearGradient.primary)
                                          : AnyShapeStyle(palette.borderFaint),
                                lineWidth: r.active ? 1.5 : 1)))
            Text(r.port).font(.system(size: 9, weight: r.active ? .heavy : .bold))
                .foregroundStyle(r.active ? palette.textPrimary : palette.textSecondary)
            Text(r.regimeLine).font(.system(size: 8, weight: .bold))
                .foregroundStyle(r.active ? Brand.blue : palette.textSecondary)
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(r.active ? Brand.blue.opacity(0.06) : .clear))
    }

    // 003 / 707 — flag waypoints on the left + active-regime caption block on the right.
    private var selectorCaption: some View {
        HStack(alignment: .top, spacing: 14) {
            HStack(spacing: 18) {
                ForEach(regimes) { r in
                    Button { onSelect(r.code) } label: {
                        VStack(spacing: 6) {
                            LandfallFlag(kind: r.flag, muted: !r.active)
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: 3).fill(palette.bgElev)
                                    .overlay(RoundedRectangle(cornerRadius: 3)
                                        .stroke(r.active ? AnyShapeStyle(LinearGradient.primary)
                                                          : AnyShapeStyle(palette.borderFaint),
                                                lineWidth: r.active ? 1.5 : 1)))
                            Text(r.portShort).font(.system(size: 8, weight: r.active ? .heavy : .bold))
                                .foregroundStyle(r.active ? palette.textPrimary : palette.textSecondary)
                        }
                    }.buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(captionLines) { line in
                    Text(line.text)
                        .font(.system(size: line.tone == .primary ? 10 : 9,
                                       weight: line.tone == .primary ? .heavy : (line.tone == .secondary ? .regular : .bold)))
                        .foregroundStyle(color(line.tone))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func color(_ t: CaptionLine.Tone) -> Color {
        switch t {
        case .primary:   return palette.textPrimary
        case .secondary: return palette.textSecondary
        case .success:   return palette.success
        case .warning:   return palette.warning
        }
    }
}

// MARK: - Per-screen call sites (the 4 visibility surfaces)

extension LandfallRegimeRail {
    /// 003 Vessel Live Tracking (Shipper) — selector + arrival caption; re-keys the DISCHARGE & FREE TIME strip.
    /// Caption lines are REQUIRED: build them from the live shipment's discharge regime —
    /// never from sample container/terminal identifiers.
    static func liveTracking003(captionLines: [CaptionLine],
                                onSelect: @escaping (String) -> Void) -> LandfallRegimeRail {
        .init(eyebrow: "DISCHARGE LANDFALL", trailingEyebrow: "GATES ON DESTINATION",
              regimes: LandfallRegime.arrival, variant: .selectorCaption,
              captionLines: captionLines, onSelect: onSelect)
    }
    /// 660 Vessel Live Position (Operator) — even waypoints, arrival regime.
    static func livePosition660(onSelect: @escaping (String) -> Void) -> LandfallRegimeRail {
        .init(eyebrow: "ARRIVAL LANDFALL · GATES ON DISCHARGE PORT", trailingEyebrow: nil,
              regimes: LandfallRegime.arrival, variant: .evenWaypoints, onSelect: onSelect)
    }
    /// 666 Vessel Container Timeline (Operator) — even waypoints, destination-release regime.
    static func containerTimeline666(onSelect: @escaping (String) -> Void) -> LandfallRegimeRail {
        .init(eyebrow: "DESTINATION RELEASE · GATES ON DISCHARGE COUNTRY", trailingEyebrow: nil,
              regimes: LandfallRegime.release, variant: .evenWaypoints, onSelect: onSelect)
    }
    /// 707 Vessel Container Movement Log (Operator) — selector + free-time caption; re-keys the dwell clock.
    /// Caption lines are REQUIRED: build them from the live container's dwell clock —
    /// never from sample container/terminal identifiers.
    static func movementLog707(captionLines: [CaptionLine],
                               onSelect: @escaping (String) -> Void) -> LandfallRegimeRail {
        .init(eyebrow: "TERMINAL FREE-TIME", trailingEyebrow: "DWELL CLOCK GATES ON TERMINAL",
              regimes: LandfallRegime.terminalFreeTime, variant: .selectorCaption,
              captionLines: captionLines, onSelect: onSelect)
    }
}

// MARK: - Previews

#Preview("Landfall regime rail · Dark") {
    VStack(spacing: 16) {
        LandfallRegimeRail.livePosition660(onSelect: { _ in })
        LandfallRegimeRail.containerTimeline666(onSelect: { _ in })
    }
    .padding()
    .background(Theme.dark.bgPage)
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("Landfall regime rail · Light") {
    VStack(spacing: 16) {
        LandfallRegimeRail.livePosition660(onSelect: { _ in })
        LandfallRegimeRail.liveTracking003(captionLines: [
            .init(text: "USCG eNOA −96h", tone: .primary),
            .init(text: "CBP ACE + ISF 10+2", tone: .secondary),
        ], onSelect: { _ in })
    }
    .padding()
    .background(Theme.light.bgPage)
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}

//
//  ── NAMED-GAP handed to the-oath (the single resolver behind all four rails) ────────────────
//
//  vessel.getLandfallRegime({ trackingId | containerId | voyageId, country: 'US'|'CA'|'MX' })
//      -> { portAuthority, arrivalInstrument, customsEntry, releaseInstrument,
//           freeTimeBasis, ratePerDay, currency }
//      · vesselProcedure (RBAC trpc.ts:265)
//      · US path is REAL today and composes vessel-native reads (all verified live 2026-06-15):
//          liveVesselPosition vesselShipments.ts:1821 · liveTrackOceanShipment :1921 ·
//          getVesselTrack :1874 · getContainerPositions :1406 · getVesselPortCalls :1849 ·
//          getVesselShipmentDetail :264 · calculateVesselDemurrage :1429 · getVesselDemurrage :1141 ·
//          tracking.getGeofenceEvents :465 · containerTimeline.timeline :19 / liveStatus :73 ·
//          yardManagement.getGateLog :1615.
//      · CA/MX path: surface the EXISTING maritime service server/services/crossBorderVessel.ts
//          (CA_import ACI Ocean eManifest :114, MX_import pedimento/VUCEM :116; manifest switch :142;
//           getRequiredVesselDocs / checkVesselCrossBorderCompliance imported crossBorder.ts:39) +
//          CA createACIManifest crossBorder.ts:3043 · MX calculatePedimentoTaxes crossBorder.ts:4062.
//      · VERIFIED ABSENT on disk 2026-06-15: getArrivalRegime / getDischargeRegime /
//          getDestinationRegime / getLandfallRegime (0 matches) — this resolver does not exist yet.
//      · PRODUCTION: ships with a test (red on main / green on the fix); where the rail re-keys
//          ESang copy, ships an eval. Pin Swift JSON key order (.sortedKeys) on any agent payload.
//
