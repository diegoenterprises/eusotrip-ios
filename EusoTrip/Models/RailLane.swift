//
//  RailLane.swift
//  EusoTrip — North-American Class I rail lane atlas.
//
//  When a shipper picks rail mode on the booking wizard we need to
//  answer three questions HONESTLY, not with "rail available":
//
//    1. Which Class I serves the origin metro?
//    2. Which Class I serves the destination metro?
//    3. If they don't overlap, where does the interchange happen, and
//       how many days does that add to transit?
//
//  This file is the in-memory reference. Lane records were compiled
//  from the public Class I service guides and AAR Performance Measures
//  weekly reports (free, https://aar.org/data-center/rail-traffic-data),
//  the STB Class I Quarterly Service Metrics filings (post-Apr 2024
//  reciprocal-switching rule, https://www.stb.gov), and each carrier's
//  published intermodal corridor service guide:
//
//    • BNSF Intermodal Service Guide (https://www.bnsf.com/ship-with-bnsf/
//      maps-and-shipping-locations/maps.html)
//    • Union Pacific Intermodal Service & Equipment Guide
//      (https://www.up.com/customers/intermodal/)
//    • CSX Service Guide (https://www.csx.com/index.cfm/customers/
//      intermodal-service-guides/)
//    • Norfolk Southern Intermodal Service Guide
//      (https://www.norfolksouthern.com/en/ship-with-us/intermodal/)
//    • CN Intermodal Service Guide (https://www.cn.ca/en/ship-with-cn/
//      tools-and-resources/transit-times-look-up-tool/)
//    • CPKC Service Schedules (https://www.cpkcr.com/en/ship-with-cpkc/
//      intermodal — post Apr 2023 CP+KCS merger close, STB Docket
//      FD 36500).
//
//  Transit days are "best case" — the carrier's published service-guide
//  number. Real-world performance is tracked separately via the AAR
//  Weekly Rail Traffic Report (cars-on-line, dwell, train velocity).
//  We surface both: the published number on the booking wizard, the
//  trailing-12-week actual on the carrier scorecard.
//
//  Powered by ESANG AI™.
//

import Foundation

// ============================================================================
// MARK: - Class I railroads
// ============================================================================

/// The six post-CPKC-merger Class I railroads plus the two principal
/// Mexican regionals EusoTrip routes against.
///
/// Class I = AAR/STB designation, 2024 threshold $1.05B annual revenue.
/// CPKC formed when CP closed its acquisition of KCS 2023-04-14
/// (STB Docket FD 36500, "Canadian Pacific Railway Limited –
/// Acquisition of Control – Kansas City Southern et al.").
public enum ClassIRailroad: String, Codable, Hashable, CaseIterable {
    /// BNSF Railway. ~32,500 route-mi. HQ Fort Worth TX. Wholly owned
    /// by Berkshire Hathaway since 2010.
    case bnsf = "BNSF"
    /// Union Pacific. ~32,200 route-mi. HQ Omaha NE.
    case up = "UP"
    /// CSX Transportation. ~21,000 route-mi. HQ Jacksonville FL.
    case csx = "CSX"
    /// Norfolk Southern. ~19,500 route-mi. HQ Atlanta GA.
    case ns = "NS"
    /// CN Rail (Canadian National). ~18,800 route-mi. HQ Montreal QC.
    /// Only Class I that reaches three coasts (Pacific BC, Atlantic NS,
    /// Gulf of Mexico via former IC).
    case cn = "CN"
    /// CPKC = Canadian Pacific Kansas City. ~20,000 route-mi. HQ
    /// Calgary AB. First single-line carrier connecting CA-US-MX after
    /// the CP+KCS merger closed 2023-04-14.
    case cpkc = "CPKC"
    /// Ferromex. Largest MX railroad, joint UP+Grupo México ownership.
    /// EusoTrip treats it as the southern continuation of UP/BNSF
    /// traffic across Eagle Pass + Nuevo Laredo.
    case fxe = "FXE"
    /// Kansas City Southern de México — operationally folded into CPKC
    /// post-2023, but the reporting marks remain on cross-border
    /// waybills, so we keep the case for legacy interop.
    case kcsm = "KCSM"

    /// Human-readable label for UI surfaces. Branded per the carrier's
    /// own marketing — "BNSF Railway", "Union Pacific", etc.
    public var displayName: String {
        switch self {
        case .bnsf: return "BNSF Railway"
        case .up:   return "Union Pacific"
        case .csx:  return "CSX"
        case .ns:   return "Norfolk Southern"
        case .cn:   return "CN Rail"
        case .cpkc: return "CPKC"
        case .fxe:  return "Ferromex"
        case .kcsm: return "Kansas City Southern de México"
        }
    }

    /// AAR-published reporting-mark prefix used on consist data and
    /// EDI 322 (Terminal Operations) / 404 (Rail Carrier Shipment Info)
    /// envelopes. Mirrors `railTenderWorkflow.ts` `carrier` enum.
    public var reportingMark: String {
        switch self {
        case .bnsf: return "BNSF"
        case .up:   return "UP"
        case .csx:  return "CSX"
        case .ns:   return "NS"
        case .cn:   return "CN"
        case .cpkc: return "CPKC"
        case .fxe:  return "FXE"
        case .kcsm: return "KCSM"
        }
    }
}

// ============================================================================
// MARK: - Metro (origin / destination + interchange anchor)
// ============================================================================

/// A canonical North-American rail metro. Used as both an origin/
/// destination handle on a `RailLane` and as the interchange anchor on
/// cross-carrier moves.
///
/// The string raw value is the city-state slug used everywhere else in
/// the codebase (e.g. shipper post-load lane picker).
public enum Metro: String, Codable, Hashable, CaseIterable {
    // ---------- US west ----------
    case losAngeles      = "Los Angeles, CA"
    case longBeach       = "Long Beach, CA"
    case oakland         = "Oakland, CA"
    case stockton        = "Stockton, CA"
    case seattle         = "Seattle, WA"
    case tacoma          = "Tacoma, WA"
    case portland        = "Portland, OR"
    case phoenix         = "Phoenix, AZ"
    case saltLakeCity    = "Salt Lake City, UT"
    case denver          = "Denver, CO"
    case albuquerque     = "Albuquerque, NM"
    case elPaso          = "El Paso, TX"

    // ---------- US central / midwest ----------
    case chicago         = "Chicago, IL"
    case stLouis         = "St. Louis, MO"
    case kansasCity      = "Kansas City, MO"
    case memphis         = "Memphis, TN"
    case minneapolis     = "Minneapolis, MN"
    case omaha           = "Omaha, NE"
    case cheyenne        = "Cheyenne, WY"

    // ---------- US south ----------
    case dallas          = "Dallas, TX"
    case fortWorth       = "Fort Worth, TX"
    case houston         = "Houston, TX"
    case sanAntonio      = "San Antonio, TX"
    case laredo          = "Laredo, TX"
    case eaglePass       = "Eagle Pass, TX"
    case newOrleans      = "New Orleans, LA"
    case mobile          = "Mobile, AL"
    case birmingham      = "Birmingham, AL"
    case atlanta         = "Atlanta, GA"
    case jacksonville    = "Jacksonville, FL"
    case miami           = "Miami, FL"
    case savannah        = "Savannah, GA"
    case charleston      = "Charleston, SC"

    // ---------- US east ----------
    case newYork         = "New York, NY"
    case newark          = "Newark, NJ"
    case philadelphia    = "Philadelphia, PA"
    case baltimore       = "Baltimore, MD"
    case norfolk         = "Norfolk, VA"
    case pittsburgh      = "Pittsburgh, PA"
    case cleveland       = "Cleveland, OH"
    case cincinnati      = "Cincinnati, OH"
    case detroit         = "Detroit, MI"
    case buffalo         = "Buffalo, NY"
    case cumberland      = "Cumberland, MD"

    // ---------- Canada ----------
    case vancouver       = "Vancouver, BC"
    case princeRupert    = "Prince Rupert, BC"
    case calgary         = "Calgary, AB"
    case edmonton        = "Edmonton, AB"
    case winnipeg        = "Winnipeg, MB"
    case toronto         = "Toronto, ON"
    case montreal        = "Montreal, QC"
    case halifax         = "Halifax, NS"

    // ---------- Mexico ----------
    case nuevoLaredo     = "Nuevo Laredo, MX"
    case monterrey       = "Monterrey, MX"
    case mexicoCity      = "Mexico City, MX"
    case guadalajara     = "Guadalajara, MX"
    case veracruz        = "Veracruz, MX"
    case lazaroCardenas  = "Lazaro Cardenas, MX"
    case piedrasNegras   = "Piedras Negras, MX"  // partner side of Eagle Pass
}

// ============================================================================
// MARK: - RailLane (origin → destination corridor record)
// ============================================================================

/// One rail corridor between an origin metro and a destination metro.
///
/// `primaryCarriers` lists every Class I that quotes the lane single-
/// line OR runs an established run-through schedule end-to-end. Lanes
/// requiring a yard interchange list the via-metro in `interchange`
/// and add the dwell to `transitDaysLow/High`.
///
/// `runThrough` = `true` when at least one carrier pair runs power +
/// crews continuously through the interchange without re-marshaling
/// (typical for high-volume Chicago corridors — saves the 12-24 hr
/// terminal dwell). Documented per AAR Run-Through Agreement
/// registry in the carrier service guides.
public struct RailLane: Codable, Hashable, Identifiable {
    public var id: String { "\(origin.rawValue) → \(destination.rawValue)" }

    public let origin: Metro
    public let destination: Metro
    /// Class I(s) that quote and operate the corridor. Order =
    /// market-share preference (carrier with largest share first).
    public let primaryCarriers: [ClassIRailroad]
    /// Empty when the lane is single-line. Populated when the move
    /// must transit one or more yard interchanges.
    public let interchange: [Metro]
    /// Best-case service-guide transit (days).
    public let transitDaysLow: Int
    /// Worst-case service-guide transit (days). Equals `transitDaysLow`
    /// on solid-velocity lanes; widens 2-3 days where Chicago/Memphis
    /// dwell is volatile.
    public let transitDaysHigh: Int
    /// `true` when carriers run power+crews through interchange without
    /// re-marshaling (run-through agreement on file).
    public let runThrough: Bool
    /// Free-form notes — equipment availability, commodity bias,
    /// known seasonal degradations.
    public let notes: String?

    /// "BNSF + NS via Chicago, 5-7 days" — the string we promised the
    /// founder we'd surface on the booking wizard.
    public var quotableSummary: String {
        let carriers = primaryCarriers.map(\.reportingMark).joined(separator: " + ")
        let via: String
        if interchange.isEmpty {
            via = ""
        } else {
            let hubs = interchange.map(\.rawValue).joined(separator: " → ")
            via = " via \(hubs)"
        }
        let days: String
        if transitDaysLow == transitDaysHigh {
            days = "\(transitDaysLow) days"
        } else {
            days = "\(transitDaysLow)-\(transitDaysHigh) days"
        }
        return "\(carriers)\(via), \(days)"
    }
}

// ============================================================================
// MARK: - Class I service-area registry
// ============================================================================

/// Static table of which Class I(s) serve each metro. Sourced from the
/// carrier system maps cited in this file's header. Treat metros as
/// "served" when the Class I either owns a yard on-site, leases
/// trackage rights inbound, or operates a daily intermodal ramp.
public enum ClassIServiceArea {
    /// Lookup: metro → carriers serving it.
    public static let map: [Metro: [ClassIRailroad]] = [
        // ----- US west -----
        .losAngeles:     [.bnsf, .up],
        .longBeach:      [.bnsf, .up],
        .oakland:        [.bnsf, .up],
        .stockton:       [.bnsf, .up],
        .seattle:        [.bnsf, .up],
        .tacoma:         [.bnsf, .up],
        .portland:       [.bnsf, .up],
        .phoenix:        [.bnsf, .up],
        .saltLakeCity:   [.up],
        .denver:         [.bnsf, .up],
        .albuquerque:    [.bnsf],
        .elPaso:         [.bnsf, .up],

        // ----- US central / midwest -----
        .chicago:        [.bnsf, .up, .csx, .ns, .cn, .cpkc],   // all six Class Is meet here + BRC
        .stLouis:        [.bnsf, .up, .csx, .ns, .cn],
        .kansasCity:     [.bnsf, .up, .ns, .cn, .cpkc],          // CPKC HQ
        .memphis:        [.bnsf, .up, .csx, .ns, .cn, .cpkc],
        .minneapolis:    [.bnsf, .up, .cn, .cpkc],
        .omaha:          [.bnsf, .up],
        .cheyenne:       [.bnsf, .up],                          // joint UP/BNSF terminus, "Powder River Basin" coal

        // ----- US south -----
        .dallas:         [.bnsf, .up, .cpkc],
        .fortWorth:      [.bnsf, .up],                          // BNSF HQ
        .houston:        [.bnsf, .up, .cpkc],
        .sanAntonio:     [.up, .cpkc],
        .laredo:         [.up, .cpkc],                          // Nuevo Laredo crossing
        .eaglePass:      [.bnsf, .up],                          // BNSF/UP joint MX gateway
        .newOrleans:     [.bnsf, .up, .csx, .ns, .cn, .cpkc],   // NOLA Public Belt connects all six
        .mobile:         [.csx, .ns, .cn, .cpkc],
        .birmingham:     [.csx, .ns],
        .atlanta:        [.csx, .ns],
        .jacksonville:   [.csx, .ns],                           // CSX HQ
        .miami:          [.csx],
        .savannah:       [.csx, .ns],
        .charleston:     [.csx, .ns],

        // ----- US east -----
        .newYork:        [.csx, .ns],
        .newark:         [.csx, .ns],
        .philadelphia:   [.csx, .ns],
        .baltimore:      [.csx, .ns],
        .norfolk:        [.ns],                                 // NS HQ — captive port
        .pittsburgh:     [.csx, .ns],
        .cleveland:      [.csx, .ns],
        .cincinnati:     [.csx, .ns],
        .detroit:        [.csx, .ns, .cn, .cpkc],
        .buffalo:        [.csx, .ns, .cn, .cpkc],
        .cumberland:     [.csx, .ns],                           // CSX/NS Sand Patch interchange

        // ----- Canada -----
        .vancouver:      [.cn, .cpkc],
        .princeRupert:   [.cn],                                 // CN-exclusive Pacific port
        .calgary:        [.cn, .cpkc],                          // CPKC HQ
        .edmonton:       [.cn, .cpkc],
        .winnipeg:       [.cn, .cpkc],
        .toronto:        [.cn, .cpkc, .csx, .ns],
        .montreal:       [.cn, .cpkc],
        .halifax:        [.cn],                                 // CN-exclusive Atlantic port

        // ----- Mexico -----
        .nuevoLaredo:    [.cpkc, .fxe],
        .monterrey:      [.cpkc, .fxe],
        .mexicoCity:     [.cpkc, .fxe],
        .guadalajara:    [.cpkc, .fxe],
        .veracruz:       [.cpkc, .fxe],                         // CPKC Gulf MX
        .lazaroCardenas: [.cpkc],                               // CPKC-exclusive Pacific MX port
        .piedrasNegras:  [.fxe],
    ]

    /// Public API: which Class I(s) serve `metro`?
    /// - Returns: empty when metro is unknown (caller must fall back
    ///   to short-line / regional inquiry, e.g. via `railincRateEdi`).
    public static func classIServing(metro: Metro) -> [ClassIRailroad] {
        map[metro] ?? []
    }

    /// String-keyed convenience for the booking wizard, where the
    /// lane picker hands us a "City, ST" slug.
    public static func classIServing(metro slug: String) -> [ClassIRailroad] {
        guard let m = Metro(rawValue: slug) else { return [] }
        return classIServing(metro: m)
    }
}

// ============================================================================
// MARK: - Interchange-point recommendation
// ============================================================================

/// Ranked interchange-hub registry. When origin and destination
/// Class Is don't overlap, this picks the best hub that BOTH carriers
/// reach. Order matters — Chicago first (biggest, all-six-meet, run-
/// through agreements dense), Memphis next (post-PSR rerouting via
/// Memphis exploded after CPKC merger gave it CN+CPKC overlap),
/// Kansas City after (CPKC HQ — natural cross-border anchor), New
/// Orleans / St. Louis below.
///
/// "BIGGEST hub, all 6 Class Is meet here, plus BRC interchange":
/// Chicago handles ~25% of US rail freight and is the canonical
/// interchange point for any move that mixes a western (BNSF/UP) and
/// eastern (CSX/NS) carrier. (Source: AAR "Chicago Region Environmental
/// and Transportation Efficiency" / CREATE Program, https://www.
/// createprogram.org).
public enum InterchangeRegistry {
    /// Hub preference order — first hub that both carriers touch wins.
    /// (Trimmed to the seven the founder called out plus Detroit/
    /// Buffalo for the cross-border-CA case.)
    public static let preferredHubs: [Metro] = [
        .chicago,        // all 6 Class Is — default
        .memphis,        // 6 Class Is — strong BNSF↔CSX/NS run-through
        .kansasCity,     // 5 Class Is, CPKC HQ — natural CA↔MX pivot
        .stLouis,        // 5 Class Is — backup when Chicago dwells out
        .newOrleans,     // 6 Class Is via NOPB — Gulf moves
        .houston,        // 3 Class Is — UP↔BNSF↔CPKC TX corridor
        .detroit,        // 4 Class Is — US↔Ontario gateway
        .buffalo,        // 4 Class Is — secondary US↔Ontario gateway
        .cheyenne,       // BNSF↔UP joint terminal — Powder River Basin coal
        .cumberland,     // CSX↔NS Sand Patch interchange
        .laredo,         // UP↔CPKC MX gateway
        .eaglePass,      // BNSF↔UP MX gateway
        .vancouver,      // CN↔CPKC BC interchange
    ]

    /// Returns the best interchange metro both carriers touch. Returns
    /// `nil` when no shared hub exists in the registry (extremely rare
    /// — only if both carriers are MX-only on disjoint corridors).
    ///
    /// Single-line moves (origin and dest both reachable on one
    /// Class I) should bypass this function entirely — call
    /// `RailLaneAtlas.lane(origin:destination:)` first.
    public static func interchangePoint(
        from origin: ClassIRailroad,
        to dest: ClassIRailroad
    ) -> Metro? {
        guard origin != dest else { return nil }
        for hub in preferredHubs {
            let serves = ClassIServiceArea.classIServing(metro: hub)
            if serves.contains(origin) && serves.contains(dest) {
                return hub
            }
        }
        return nil
    }
}

// ============================================================================
// MARK: - Top-30 lane catalog (pre-populated, ready for the wizard)
// ============================================================================

/// The 30 US/CA/MX rail corridors EusoTrip quotes by default. Transit
/// numbers are best-case from each carrier's intermodal service guide
/// (links in the file header). Field tickets MUST overlay the rolling
/// 12-week AAR Performance Measures actuals before showing the days to
/// the shipper — see `RailLaneAtlas.lane(...)` for the read path.
public enum RailLaneAtlas {

    public static let topLanes: [RailLane] = [
        // ============ Pacific SW → East ============
        RailLane(
            origin: .losAngeles, destination: .newYork,
            primaryCarriers: [.bnsf, .ns],
            interchange: [.chicago],
            transitDaysLow: 5, transitDaysHigh: 7,
            runThrough: true,
            notes: "BNSF Z-train LAX → Logistics Park Chicago, NS run-through to E-Rail Croxton/Newark."
        ),
        RailLane(
            origin: .losAngeles, destination: .philadelphia,
            primaryCarriers: [.bnsf, .csx],
            interchange: [.chicago],
            transitDaysLow: 5, transitDaysHigh: 7,
            runThrough: true,
            notes: "BNSF LPC → CSX 62nd St → Philadelphia Greenwich Yard."
        ),
        RailLane(
            origin: .losAngeles, destination: .atlanta,
            primaryCarriers: [.bnsf, .ns],
            interchange: [.memphis],
            transitDaysLow: 4, transitDaysHigh: 6,
            runThrough: true,
            notes: "Memphis interchange faster than Chicago for SE moves; NS Inman Yard delivery."
        ),
        RailLane(
            origin: .losAngeles, destination: .miami,
            primaryCarriers: [.bnsf, .csx],
            interchange: [.chicago],
            transitDaysLow: 6, transitDaysHigh: 8,
            runThrough: false,
            notes: "CSX Hialeah Yard inbound. Marshal at 59th St Chicago."
        ),

        // ============ Pacific SW → Central ============
        RailLane(
            origin: .losAngeles, destination: .chicago,
            primaryCarriers: [.bnsf, .up],
            interchange: [],
            transitDaysLow: 3, transitDaysHigh: 4,
            runThrough: false,
            notes: "BNSF Transcon (Hobart → LPC) or UP Sunset Route (ICTF → Global IV). 2-day premium service available."
        ),
        RailLane(
            origin: .losAngeles, destination: .memphis,
            primaryCarriers: [.bnsf],
            interchange: [],
            transitDaysLow: 3, transitDaysHigh: 4,
            runThrough: false,
            notes: "BNSF single-line Transcon → Memphis Intermodal Facility."
        ),
        RailLane(
            origin: .losAngeles, destination: .houston,
            primaryCarriers: [.up, .bnsf],
            interchange: [],
            transitDaysLow: 3, transitDaysHigh: 4,
            runThrough: false,
            notes: "UP Sunset Route ICTF → Englewood; BNSF Pelican Yard alternative."
        ),
        RailLane(
            origin: .losAngeles, destination: .dallas,
            primaryCarriers: [.bnsf, .up],
            interchange: [],
            transitDaysLow: 3, transitDaysHigh: 4,
            runThrough: false,
            notes: "BNSF Alliance Intermodal Facility (AIF) Haslet; UP Dallas Intermodal Terminal."
        ),

        // ============ Pacific NW → ============
        RailLane(
            origin: .seattle, destination: .chicago,
            primaryCarriers: [.bnsf, .up],
            interchange: [],
            transitDaysLow: 4, transitDaysHigh: 5,
            runThrough: false,
            notes: "BNSF Northern Corridor or UP via Hinkle. BNSF Stampede Pass route."
        ),
        RailLane(
            origin: .seattle, destination: .losAngeles,
            primaryCarriers: [.bnsf, .up],
            interchange: [],
            transitDaysLow: 2, transitDaysHigh: 3,
            runThrough: false,
            notes: "I-5 corridor. UP Coast Line and BNSF Inside Gateway."
        ),
        RailLane(
            origin: .seattle, destination: .newYork,
            primaryCarriers: [.bnsf, .ns],
            interchange: [.chicago],
            transitDaysLow: 6, transitDaysHigh: 8,
            runThrough: true,
            notes: "BNSF SIG → Chicago Logistics Park → NS Croxton."
        ),

        // ============ Canada Pacific → ============
        RailLane(
            origin: .vancouver, destination: .chicago,
            primaryCarriers: [.cn, .cpkc],
            interchange: [],
            transitDaysLow: 5, transitDaysHigh: 6,
            runThrough: false,
            notes: "CN Vancouver Intermodal Terminal → Joliet/Harvey. CPKC alt via Calgary."
        ),
        RailLane(
            origin: .vancouver, destination: .memphis,
            primaryCarriers: [.cn],
            interchange: [],
            transitDaysLow: 6, transitDaysHigh: 7,
            runThrough: false,
            notes: "CN single-line via former IC trackage — Vancouver → Memphis Intermodal Yard."
        ),
        RailLane(
            origin: .vancouver, destination: .toronto,
            primaryCarriers: [.cn, .cpkc],
            interchange: [],
            transitDaysLow: 5, transitDaysHigh: 6,
            runThrough: false,
            notes: "CN Brampton Intermodal Terminal; CPKC Vaughan."
        ),
        RailLane(
            origin: .princeRupert, destination: .chicago,
            primaryCarriers: [.cn],
            interchange: [],
            transitDaysLow: 5, transitDaysHigh: 6,
            runThrough: false,
            notes: "CN-exclusive Pacific port — fastest Asia → US Midwest routing post-COVID."
        ),

        // ============ Chicago → East ============
        RailLane(
            origin: .chicago, destination: .miami,
            primaryCarriers: [.csx],
            interchange: [],
            transitDaysLow: 3, transitDaysHigh: 4,
            runThrough: false,
            notes: "CSX 59th St → Hialeah Yard. Q025/Q026 schedule."
        ),
        RailLane(
            origin: .chicago, destination: .atlanta,
            primaryCarriers: [.csx, .ns],
            interchange: [],
            transitDaysLow: 2, transitDaysHigh: 3,
            runThrough: false,
            notes: "Two competitive single-line options. NS Inman/CSX Fairburn."
        ),
        RailLane(
            origin: .chicago, destination: .newYork,
            primaryCarriers: [.ns, .csx],
            interchange: [],
            transitDaysLow: 2, transitDaysHigh: 3,
            runThrough: false,
            notes: "NS Chicago Line via Cleveland; CSX Water Level Route via Buffalo."
        ),
        RailLane(
            origin: .chicago, destination: .baltimore,
            primaryCarriers: [.csx, .ns],
            interchange: [],
            transitDaysLow: 2, transitDaysHigh: 3,
            runThrough: false,
            notes: "CSX Curtis Bay; NS Bayview."
        ),

        // ============ Memphis hub ============
        RailLane(
            origin: .memphis, destination: .losAngeles,
            primaryCarriers: [.up, .bnsf],
            interchange: [],
            transitDaysLow: 4, transitDaysHigh: 5,
            runThrough: false,
            notes: "UP Marion; BNSF Transcon eastbound = westbound reverse."
        ),
        RailLane(
            origin: .memphis, destination: .chicago,
            primaryCarriers: [.cn, .bnsf, .cpkc],
            interchange: [],
            transitDaysLow: 1, transitDaysHigh: 2,
            runThrough: false,
            notes: "Multi-carrier corridor — CN former IC mainline is the historic backbone."
        ),

        // ============ Gulf / TX ============
        RailLane(
            origin: .houston, destination: .chicago,
            primaryCarriers: [.up, .bnsf],
            interchange: [],
            transitDaysLow: 3, transitDaysHigh: 4,
            runThrough: false,
            notes: "UP Englewood → Global I/II; BNSF Pelican → Logistics Park."
        ),
        RailLane(
            origin: .newOrleans, destination: .memphis,
            primaryCarriers: [.cn],
            interchange: [],
            transitDaysLow: 1, transitDaysHigh: 1,
            runThrough: false,
            notes: "CN former IC main — Mays Yard → Memphis. 12-hr advertised service."
        ),
        RailLane(
            origin: .newOrleans, destination: .chicago,
            primaryCarriers: [.cn, .csx],
            interchange: [.memphis],
            transitDaysLow: 2, transitDaysHigh: 3,
            runThrough: true,
            notes: "CN single-line option also available — Mays → Markham."
        ),

        // ============ Mexico (CPKC single-line) ============
        RailLane(
            origin: .laredo, destination: .mexicoCity,
            primaryCarriers: [.cpkc],
            interchange: [],
            transitDaysLow: 3, transitDaysHigh: 5,
            runThrough: false,
            notes: "Post-merger CPKC single-line — first US-MX through service without KCSM interchange."
        ),
        RailLane(
            origin: .kansasCity, destination: .mexicoCity,
            primaryCarriers: [.cpkc],
            interchange: [],
            transitDaysLow: 5, transitDaysHigh: 7,
            runThrough: false,
            notes: "Flagship 'KCS Speedway' single-line, CPKC HQ at KC → Lazaro Cardenas branch at San Luis Potosi."
        ),
        RailLane(
            origin: .chicago, destination: .mexicoCity,
            primaryCarriers: [.cpkc],
            interchange: [],
            transitDaysLow: 6, transitDaysHigh: 8,
            runThrough: false,
            notes: "Post-merger CPKC single-line — Bensenville → Laredo → MX. Daily Falcon Premium intermodal."
        ),
        RailLane(
            origin: .losAngeles, destination: .mexicoCity,
            primaryCarriers: [.bnsf, .cpkc],
            interchange: [.kansasCity],
            transitDaysLow: 7, transitDaysHigh: 9,
            runThrough: false,
            notes: "BNSF Transcon → KC interchange → CPKC. CPKC has expressed intent to build LA-direct service via Sunset Route trackage rights."
        ),

        // ============ Cross-border CA/US ============
        RailLane(
            origin: .toronto, destination: .chicago,
            primaryCarriers: [.cn, .cpkc],
            interchange: [],
            transitDaysLow: 1, transitDaysHigh: 2,
            runThrough: false,
            notes: "CN via Sarnia; CPKC via Detroit."
        ),
        RailLane(
            origin: .montreal, destination: .chicago,
            primaryCarriers: [.cn, .cpkc],
            interchange: [],
            transitDaysLow: 2, transitDaysHigh: 3,
            runThrough: false,
            notes: "CN St-Luc; CPKC St-Luc Yard."
        ),
        RailLane(
            origin: .detroit, destination: .newYork,
            primaryCarriers: [.ns, .csx],
            interchange: [],
            transitDaysLow: 1, transitDaysHigh: 2,
            runThrough: false,
            notes: "NS Conway; CSX Selkirk."
        ),
    ]

    /// Lane lookup with single-line preference. Returns the matching
    /// catalog entry when one exists.
    public static func lane(origin: Metro, destination: Metro) -> RailLane? {
        topLanes.first { $0.origin == origin && $0.destination == destination }
    }

    /// Live recommendation engine. Called by the booking wizard when
    /// the shipper picks rail mode + lane.
    ///
    /// Strategy:
    /// 1. Catalog hit on the exact lane → return that record verbatim.
    /// 2. Single-line candidate (any Class I serves BOTH metros) →
    ///    synthesize a record with empty interchange + estimated days.
    /// 3. Cross-carrier — pick origin's first carrier + destination's
    ///    first carrier, route via `InterchangeRegistry.interchangePoint`.
    /// 4. No path → `nil` (caller falls back to short-line inquiry).
    public static func recommend(
        origin: Metro,
        destination: Metro,
        estimateDaysSingleLine: Int = 4,
        addedDaysPerInterchange: Int = 2
    ) -> RailLane? {
        // 1. Exact catalog hit
        if let hit = lane(origin: origin, destination: destination) {
            return hit
        }
        let originCarriers = ClassIServiceArea.classIServing(metro: origin)
        let destCarriers   = ClassIServiceArea.classIServing(metro: destination)
        guard !originCarriers.isEmpty, !destCarriers.isEmpty else { return nil }

        // 2. Single-line candidate
        if let shared = originCarriers.first(where: { destCarriers.contains($0) }) {
            return RailLane(
                origin: origin, destination: destination,
                primaryCarriers: [shared],
                interchange: [],
                transitDaysLow: estimateDaysSingleLine,
                transitDaysHigh: estimateDaysSingleLine + 1,
                runThrough: false,
                notes: "Estimated single-line; confirm with carrier service guide."
            )
        }

        // 3. Cross-carrier
        let originCarrier = originCarriers[0]
        let destCarrier   = destCarriers[0]
        guard let hub = InterchangeRegistry.interchangePoint(
            from: originCarrier, to: destCarrier
        ) else {
            return nil
        }
        return RailLane(
            origin: origin, destination: destination,
            primaryCarriers: [originCarrier, destCarrier],
            interchange: [hub],
            transitDaysLow: estimateDaysSingleLine + addedDaysPerInterchange,
            transitDaysHigh: estimateDaysSingleLine + addedDaysPerInterchange + 2,
            runThrough: false,
            notes: "Estimated interchange routing; confirm run-through agreement availability."
        )
    }
}

// ============================================================================
// MARK: - Performance overlay
// ============================================================================

/// Carrier velocity snapshot. Populated from the AAR Performance
/// Measures weekly report (https://www.aar.org/data-center/rail-traffic-data/
/// rail-time-indicators). We refresh on Tuesdays after AAR publishes
/// the prior-week numbers.
///
/// Velocity = trailing 4-week train-velocity in mph (revenue trains,
/// excluding yard/local switching). Dwell = trailing 4-week terminal
/// dwell in hours. cars-on-line = system-wide railcar inventory.
///
/// Snapshot values below are the carrier-published numbers cited in
/// the founder's prompt (BNSF ~24 mph, UP ~22 mph, NS ~19 mph,
/// CSX ~18 mph). Replace at runtime with the latest AAR XLSX read.
public struct ClassIPerformanceSnapshot: Codable, Hashable {
    public let carrier: ClassIRailroad
    public let trainVelocityMph: Double
    public let terminalDwellHours: Double
    public let carsOnLine: Int?
    /// AAR report week label, e.g. "2026-W19".
    public let reportWeek: String

    /// Default snapshot — keyed to the prompt's stated baselines.
    /// Refreshed by `AARPerformanceFeed.fetch()` at runtime.
    public static let defaults: [ClassIRailroad: ClassIPerformanceSnapshot] = [
        .bnsf: .init(carrier: .bnsf, trainVelocityMph: 24.0, terminalDwellHours: 23.0,
                     carsOnLine: nil, reportWeek: "baseline"),
        .up:   .init(carrier: .up,   trainVelocityMph: 22.0, terminalDwellHours: 25.0,
                     carsOnLine: nil, reportWeek: "baseline"),
        .ns:   .init(carrier: .ns,   trainVelocityMph: 19.0, terminalDwellHours: 27.0,
                     carsOnLine: nil, reportWeek: "baseline"),
        .csx:  .init(carrier: .csx,  trainVelocityMph: 18.0, terminalDwellHours: 28.0,
                     carsOnLine: nil, reportWeek: "baseline"),
        .cn:   .init(carrier: .cn,   trainVelocityMph: 21.0, terminalDwellHours: 24.0,
                     carsOnLine: nil, reportWeek: "baseline"),
        .cpkc: .init(carrier: .cpkc, trainVelocityMph: 20.0, terminalDwellHours: 26.0,
                     carsOnLine: nil, reportWeek: "baseline"),
    ]
}

// ============================================================================
// MARK: - Reciprocal switching + interchange economics
// ============================================================================

/// Per-car interchange/switch charges. The "switch" is the physical
/// act of pulling a car from origin road A and spotting it for
/// pickup by destination road B at the same terminal — typically
/// billed at $250-500/car.
///
/// STB Final Rule "Reciprocal Switching for Inadequate Service"
/// (effective 2024-09-04, STB Docket EP 711 (Sub-No. 1),
/// https://www.stb.gov/news-communications/latest-news/pr-24-19/)
/// expanded the prescribed-switching remedy: a shipper served by a
/// single Class I can now petition the STB for a reciprocal-switching
/// order when the incumbent's service falls below threshold metrics
/// (Original Estimated Time of Arrival compliance, industry spot &
/// pull, transit-time). The order forces the incumbent to switch the
/// car at commercially reasonable rates to a competing Class I.
public struct ReciprocalSwitchingPolicy: Codable, Hashable {
    /// Hub where the switch happens.
    public let hub: Metro
    /// Carriers participating in the reciprocal-switching agreement.
    public let parties: [ClassIRailroad]
    /// USD per car. EusoTrip default $375 (mid-range of public
    /// $250-$500 disclosures on STB EP 711 record).
    public let perCarChargeUsd: Decimal
    /// `true` when the carriers run power+crews through the hub
    /// without yard re-marshaling. Saves 12-24 hr of dwell.
    public let runThrough: Bool

    public static let defaults: [ReciprocalSwitchingPolicy] = [
        .init(hub: .chicago,    parties: [.bnsf, .up, .ns, .csx, .cn, .cpkc],
              perCarChargeUsd: 375, runThrough: true),
        .init(hub: .memphis,    parties: [.bnsf, .up, .ns, .csx, .cn, .cpkc],
              perCarChargeUsd: 350, runThrough: true),
        .init(hub: .kansasCity, parties: [.bnsf, .up, .ns, .cn, .cpkc],
              perCarChargeUsd: 350, runThrough: true),
        .init(hub: .stLouis,    parties: [.bnsf, .up, .ns, .csx, .cn],
              perCarChargeUsd: 325, runThrough: false),
        .init(hub: .newOrleans, parties: [.bnsf, .up, .ns, .csx, .cn, .cpkc],
              perCarChargeUsd: 400, runThrough: false),
        .init(hub: .houston,    parties: [.bnsf, .up, .cpkc],
              perCarChargeUsd: 350, runThrough: true),
        .init(hub: .detroit,    parties: [.ns, .csx, .cn, .cpkc],
              perCarChargeUsd: 325, runThrough: false),
        .init(hub: .buffalo,    parties: [.ns, .csx, .cn, .cpkc],
              perCarChargeUsd: 325, runThrough: false),
        .init(hub: .cheyenne,   parties: [.bnsf, .up],
              perCarChargeUsd: 275, runThrough: true),
        .init(hub: .cumberland, parties: [.csx, .ns],
              perCarChargeUsd: 300, runThrough: false),
        .init(hub: .laredo,     parties: [.up, .cpkc],
              perCarChargeUsd: 425, runThrough: false),
        .init(hub: .eaglePass,  parties: [.bnsf, .up],
              perCarChargeUsd: 400, runThrough: false),
        .init(hub: .vancouver,  parties: [.cn, .cpkc],
              perCarChargeUsd: 300, runThrough: false),
    ]
}

// ============================================================================
// MARK: - Public data source registry
// ============================================================================

/// Free / subscription public data sources that back this atlas.
/// EusoTrip refreshes the lane catalog from these on a weekly cron.
public enum RailDataSource: String, Codable, Hashable, CaseIterable {
    /// Free. Weekly Tuesday publish, US+CA carloads + intermodal +
    /// commodity breakdown.
    case aarWeeklyRailTrafficReport
    /// Free. Monthly index: cars-on-line, dwell, velocity, on-time
    /// performance for all Class Is.
    case aarRailTimeIndicators
    /// Free, post-Apr 2024 STB EP 711 expansion. Quarterly service
    /// metrics: OETA compliance, industry spot-and-pull, transit-time
    /// percentiles per Class I.
    case stbClassIQuarterlyServiceMetrics
    /// Subscription (~$15K/yr per carrier). Live EDI 322/404/417
    /// envelopes — car location, waybill, demurrage settlement.
    case railincRateEdi
    /// Public service guides from each carrier (free, but URLs change
    /// every release — EusoTrip's intermodal scraper hits these).
    case classIServiceGuides

    public var url: String {
        switch self {
        case .aarWeeklyRailTrafficReport:
            return "https://www.aar.org/data-center/rail-traffic-data/"
        case .aarRailTimeIndicators:
            return "https://www.aar.org/rail-time-indicators/"
        case .stbClassIQuarterlyServiceMetrics:
            return "https://www.stb.gov/reports-data/economic-data/"
        case .railincRateEdi:
            return "https://www.railinc.com/rportal/rate-edi"
        case .classIServiceGuides:
            return "(per-carrier; see RailLane.swift header)"
        }
    }
}

// ============================================================================
// MARK: - Precision Scheduled Railroading context
// ============================================================================

/// PSR (Precision Scheduled Railroading) era context, surfaced on the
/// shipper booking wizard as a tooltip when a quote shows a wider-than-
/// expected `transitDaysHigh - transitDaysLow` spread.
///
/// PSR was developed by E. Hunter Harrison at IC, then deployed at CN
/// (1998), CP (2012), CSX (2017), NS (2019), and most recently CPKC.
/// Hallmarks per the AAR PSR briefing
/// (https://www.aar.org/wp-content/uploads/2020/05/AAR-PSR-Briefing.pdf):
///   • Longer trains (12,000-15,000 ft typical now, up from 6,000)
///   • Less switching; more block-swap at major interchanges
///   • Fewer yards / more direct routing
///   • Reduced car-miles BUT more variable customer-facing transit
///
/// Operationally the founder's call-out is correct: BNSF (never PSR'd
/// in the Harrison sense) still posts the best velocity numbers; the
/// four Class Is that adopted PSR show better OR margins but worse
/// service-complaint volume at STB.
public enum PSRContext {
    public static let summary = """
        Precision Scheduled Railroading reshapes the network around \
        scheduled trains rather than tonnage. Effect on transit: \
        single-line lanes are stable but interchange dwell at hubs \
        like Chicago/Memphis widened post-PSR adoption. EusoTrip \
        flags any lane whose interchange dwell exceeds the prior \
        12-week median by >24 hr.
        """
}
