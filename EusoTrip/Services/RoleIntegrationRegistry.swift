//
//  RoleIntegrationRegistry.swift
//  EusoTrip — Typed Swift mirror of the
//  `role_integration_mapping.md` doctrine. The 22 operational roles
//  represented here (10 truck + 6 rail + 6 vessel) each have a tailored
//  provider-capability wish list. ADMIN and SUPER_ADMIN are aggregate server
//  roles and intentionally do not duplicate every row in this Swift registry.
//  SERVICE_PROVIDER is additive repair-provider identity and is live-catalog
//  only; it is not one of the 22 transport-operational parity roles.
//
//  A row and reachable docs URL do not claim an active connector. Executable
//  status, precise blocked disposition, role/mode eligibility, and connection
//  state come only from the live `userIntegrations` server contract.
//
//  Connection state is owned by the server (`userIntegrationConnections`
//  table). This registry is an offline parity/audit input only; it is never a
//  source of connection state or a fallback provider list in the app.
//
//  Powered by ESANG AI™.
//

import Foundation

// MARK: - Provider entry

/// One integration row. Mirrors the doctrine table per role.
struct RoleIntegration: Identifiable, Hashable {
    /// Stable id — `<role>:<provider-slug>` so the same provider
    /// can appear under multiple roles without colliding.
    var id: String { "\(roleKey):\(slug)" }

    /// Canonical role key from the doctrine ("DRIVER" / "CATALYST"
    /// / "RAIL_ENGINEER" / "PORT_MASTER" / etc.).
    let roleKey: String
    /// Provider slug — lowercase, dash-cased.
    let slug: String
    /// Display name (e.g. "DAT Power", "INTTRA").
    let name: String
    /// One-line function description.
    let function: String
    /// Doc URL — exact URL the doctrine recorded.
    let docs: String
    /// Category bucket the provider falls into (rate-data / ELD /
    /// load-board / TMS / ERP / weather / customs / etc.).
    let category: Category

    enum Category: String, CaseIterable {
        case rateData
        case loadBoard
        case visibility
        case tms
        case erp
        case eld
        case fuelCard
        case factoring
        case weather
        case nav
        case payments
        case docs
        case compliance
        case carrierVetting
        case banking
        case identity
        case crm
        case dispatch
        case maintenance
        case toll
        case insurance
        case dashcam
        case training
        case bgScreening
        case marketIntel
        case railClassI
        case railIndustry
        case railEquip
        case railOps
        case oceanBooking
        case oceanCarrier
        case oceanIntel
        case marine
        case bunker
        case classSociety
        case satcom
        case satellite
        case terminalAuto
        case crane
        case yard
        case dockSched
        case workforce
        case warehouse
        case customs
    }
}

// MARK: - Registry

enum RoleIntegrationRegistry {

    enum Coverage: String {
        /// A transport-operational role with an offline doctrine parity list.
        case operationalParity
        /// ADMIN/SUPER_ADMIN aggregate rows dynamically on the server.
        case aggregateServerRole
        /// Backend-eligible role whose providers must come only from the server.
        case liveCatalogOnly
        case unknown
    }

    /// Canon revision 2026-08-23.1 transport-operational role set.
    static let operationalRoleKeys: Set<String> = [
        "SHIPPER", "CATALYST", "BROKER", "DRIVER", "DISPATCH", "ESCORT",
        "TERMINAL_MANAGER", "COMPLIANCE_OFFICER", "SAFETY_MANAGER", "FACTORING",
        "RAIL_SHIPPER", "RAIL_CATALYST", "RAIL_DISPATCHER", "RAIL_ENGINEER",
        "RAIL_CONDUCTOR", "RAIL_BROKER",
        "VESSEL_SHIPPER", "VESSEL_OPERATOR", "PORT_MASTER", "SHIP_CAPTAIN",
        "VESSEL_BROKER", "CUSTOMS_BROKER",
    ]

    static let aggregateServerRoleKeys: Set<String> = ["ADMIN", "SUPER_ADMIN"]
    static let liveCatalogOnlyRoleKeys: Set<String> = ["SERVICE_PROVIDER"]

    static func coverage(for role: String) -> Coverage {
        let roleKey = role.uppercased()
        if operationalRoleKeys.contains(roleKey) { return .operationalParity }
        if aggregateServerRoleKeys.contains(roleKey) { return .aggregateServerRole }
        if liveCatalogOnlyRoleKeys.contains(roleKey) { return .liveCatalogOnly }
        return .unknown
    }

    /// Canonical lookup — return all providers for a given role
    /// key. Aggregate, live-only, and unknown roles deliberately return an
    /// empty list; the app never turns this audit registry into runtime rows.
    static func providers(for role: String) -> [RoleIntegration] {
        let roleKey = role.uppercased()
        guard operationalRoleKeys.contains(roleKey) else { return [] }
        return all.filter { $0.roleKey == roleKey }
    }

    /// Same data flat — useful for an admin-side registry view.
    static let all: [RoleIntegration] = (
        truckShipper + truckCatalyst + truckBroker + truckDriver +
        truckDispatch + truckEscort + truckTerminalManager +
        truckComplianceOfficer + truckSafetyManager + truckFactoring +
        railShipper + railCatalyst + railDispatcher + railEngineer +
        railConductor + railBroker +
        vesselShipper + vesselOperator + portMaster + shipCaptain +
        vesselBroker + customsBroker
    )

    /// Fast local integrity evidence for focused iOS/source gates. URL syntax
    /// is checked here; reachability and activation remain separate audits.
    static var validationIssues: [String] {
        var issues: [String] = []
        let actualRoleKeys = Set(all.map(\.roleKey))
        for roleKey in operationalRoleKeys.subtracting(actualRoleKeys).sorted() {
            issues.append("Missing operational role: \(roleKey)")
        }
        for roleKey in actualRoleKeys.subtracting(operationalRoleKeys).sorted() {
            issues.append("Unexpected parity role: \(roleKey)")
        }

        var seenIds: Set<String> = []
        for row in all {
            if row.slug.isEmpty || row.name.isEmpty || row.function.isEmpty {
                issues.append("Incomplete registry row: \(row.id)")
            }
            if !seenIds.insert(row.id).inserted {
                issues.append("Duplicate registry row: \(row.id)")
            }
            guard let url = URL(string: row.docs),
                  url.scheme?.lowercased() == "https",
                  url.host != nil else {
                issues.append("Invalid documentation URL: \(row.id)")
                continue
            }
        }
        return issues.sorted()
    }

    // MARK: - TRUCK (10)

    private static let truckShipper: [RoleIntegration] = [
        .init(roleKey: "SHIPPER", slug: "dat-rateview",          name: "DAT RateView",            function: "Contract & spot rate benchmarking", docs: "https://www.dat.com/api-integration",                      category: .rateData),
        .init(roleKey: "SHIPPER", slug: "freightwaves-sonar",    name: "FreightWaves SONAR",      function: "Forward-looking market intel",      docs: "https://api.freightwaves.com/Help/",                        category: .marketIntel),
        .init(roleKey: "SHIPPER", slug: "project44",              name: "project44",                function: "Visibility / ETA across carriers", docs: "https://developers.project44.com/api-reference",             category: .visibility),
        .init(roleKey: "SHIPPER", slug: "fourkites",              name: "FourKites",                function: "Real-time freight visibility",     docs: "https://developer.fourkites.com",                           category: .visibility),
        .init(roleKey: "SHIPPER", slug: "macropoint",             name: "MacroPoint (Descartes)",   function: "Load tracking",                    docs: "https://docs.macropoint.com",                               category: .visibility),
        .init(roleKey: "SHIPPER", slug: "sap-tm",                 name: "SAP Transportation Mgmt", function: "ERP→TMS bridge",                   docs: "https://api.sap.com",                                       category: .tms),
        .init(roleKey: "SHIPPER", slug: "oracle-otm",             name: "Oracle Transportation Mgmt", function: "OTM connector",                  docs: "https://docs.oracle.com/en/cloud/saas/transportation/26c/apis.html", category: .tms),
        .init(roleKey: "SHIPPER", slug: "netsuite",               name: "NetSuite",                 function: "Mid-market ERP",                  docs: "https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/book_1559132836.html", category: .erp),
        .init(roleKey: "SHIPPER", slug: "quickbooks",             name: "QuickBooks Online",        function: "Invoice/payment sync",            docs: "https://developer.intuit.com",                              category: .payments),
        .init(roleKey: "SHIPPER", slug: "manhattan-tms",          name: "Manhattan Active TMS",     function: "Tier-1 TMS bridge",               docs: "https://developer.manh.com",                                category: .tms),
        .init(roleKey: "SHIPPER", slug: "blue-yonder",            name: "Blue Yonder (JDA)",        function: "Demand/transportation planning",  docs: "https://developer-link.blueyonder.com",                     category: .tms),
        .init(roleKey: "SHIPPER", slug: "shopify",                name: "Shopify SP-API",           function: "E-commerce → freight tender",     docs: "https://shopify.dev/docs/api",                              category: .erp),
        .init(roleKey: "SHIPPER", slug: "amazon-spapi",           name: "Amazon SP-API",            function: "Marketplace freight orders",       docs: "https://developer-docs.amazon.com/sp-api",                  category: .erp),
        .init(roleKey: "SHIPPER", slug: "stripe",                 name: "Stripe",                   function: "Receivables / customer billing",  docs: "https://docs.stripe.com/api",                              category: .payments),
        .init(roleKey: "SHIPPER", slug: "docusign",               name: "DocuSign",                 function: "BOL / contract e-signature",      docs: "https://developers.docusign.com",                          category: .docs),
    ]

    private static let truckCatalyst: [RoleIntegration] = [
        .init(roleKey: "CATALYST", slug: "geotab",        name: "Geotab",        function: "Fleet telematics + ELD", docs: "https://developers.geotab.com",     category: .eld),
        .init(roleKey: "CATALYST", slug: "samsara",       name: "Samsara",       function: "Fleet/ELD/AI dashcam",   docs: "https://developers.samsara.com",     category: .eld),
        .init(roleKey: "CATALYST", slug: "motive",        name: "Motive",        function: "ELD + driver workflow",  docs: "https://developer.gomotive.com",     category: .eld),
        .init(roleKey: "CATALYST", slug: "omnitracs",     name: "Omnitracs",     function: "Enterprise ELD",         docs: "https://www.omnitracs.com",     category: .eld),
        .init(roleKey: "CATALYST", slug: "eroad",         name: "EROAD",         function: "Tax/ELD/safety",         docs: "https://www.eroad.com",          category: .eld),
        .init(roleKey: "CATALYST", slug: "comdata",       name: "Comdata",       function: "Fuel card + trip card",  docs: "https://www.comdata.com",        category: .fuelCard),
        .init(roleKey: "CATALYST", slug: "efs",            name: "EFS Transportation", function: "Fuel + cash advance", docs: "https://www.efsllc.com",           category: .fuelCard),
        .init(roleKey: "CATALYST", slug: "wex",           name: "WEX Fleet",     function: "Fuel card",              docs: "https://developer.wexinc.com/fleet-fabric-service/", category: .fuelCard),
        .init(roleKey: "CATALYST", slug: "fleetone",       name: "FleetOne EDGE", function: "Fuel + maintenance card", docs: "https://www.fleetone.com/api",       category: .fuelCard),
        .init(roleKey: "CATALYST", slug: "dtn-fuels",     name: "DTN Refined Fuels", function: "Rack/terminal pricing", docs: "https://devportal.dtn.com",         category: .marketIntel),
        .init(roleKey: "CATALYST", slug: "decisiv",       name: "Decisiv SRM",   function: "Service relationship mgmt", docs: "https://www.decisiv.com",       category: .maintenance),
        .init(roleKey: "CATALYST", slug: "fleetio",        name: "Fleetio",        function: "Maintenance management", docs: "https://developer.fleetio.com",     category: .maintenance),
        .init(roleKey: "CATALYST", slug: "bestpass",       name: "Bestpass",       function: "Toll consolidation",     docs: "https://www.bestpass.com",           category: .toll),
        .init(roleKey: "CATALYST", slug: "prepass",        name: "PrePass",        function: "Bypass + weigh station", docs: "https://prepass.com",            category: .toll),
        .init(roleKey: "CATALYST", slug: "atbs",           name: "ATBS",           function: "Owner-op tax + accounting", docs: "https://atbs.com",                   category: .factoring),
        .init(roleKey: "CATALYST", slug: "triumph",        name: "Triumph",        function: "Factoring + payments",     docs: "https://www.triumph.io",            category: .factoring),
        .init(roleKey: "CATALYST", slug: "truckstop-ins",  name: "Truckstop ITS",  function: "Insurance",                docs: "https://truckstop.com",   category: .insurance),
    ]

    private static let truckBroker: [RoleIntegration] = [
        .init(roleKey: "BROKER", slug: "dat-power",      name: "DAT Power",         function: "Load board API",            docs: "https://www.dat.com/api-integration",                category: .loadBoard),
        .init(roleKey: "BROKER", slug: "truckstop",      name: "Truckstop",          function: "Load board + onboarding",   docs: "https://developer.truckstop.com",          category: .loadBoard),
        .init(roleKey: "BROKER", slug: "123loadboard",   name: "123Loadboard",       function: "Load board",                docs: "https://www.123loadboard.com/api",   category: .loadBoard),
        .init(roleKey: "BROKER", slug: "nextload",        name: "NextLOAD",           function: "Free load board",           docs: "https://nextload.com",               category: .loadBoard),
        .init(roleKey: "BROKER", slug: "mcleod",          name: "McLeod LoadMaster",  function: "TMS bridge",                docs: "https://mcleodsoftware.com/integrations", category: .tms),
        .init(roleKey: "BROKER", slug: "mercurygate",    name: "MercuryGate",       function: "TMS API/EDI",               docs: "https://mercurygate.com",            category: .tms),
        .init(roleKey: "BROKER", slug: "trimble-tmw",    name: "Trimble TMW",       function: "Trimble freight TMS",       docs: "https://transportation.trimble.com/en/solutions/transportation-management/tmw-suite-tms", category: .tms),
        .init(roleKey: "BROKER", slug: "highway",        name: "Highway",           function: "Carrier identity + fraud",  docs: "https://help.highway.com",     category: .carrierVetting),
        .init(roleKey: "BROKER", slug: "rmis",           name: "RMIS (Truckstop)",   function: "Carrier onboarding",        docs: "https://rmis.com",                   category: .carrierVetting),
        .init(roleKey: "BROKER", slug: "carrier411",     name: "Carrier411",         function: "Authority + insurance monitoring", docs: "https://www.carrier411.com/webservices.cfm", category: .carrierVetting),
        .init(roleKey: "BROKER", slug: "carrierassure",  name: "Carrier Assure",     function: "Fraud + performance scoring", docs: "https://carrierassure.com",          category: .carrierVetting),
        .init(roleKey: "BROKER", slug: "mycarrierportal",name: "MyCarrierPortal",    function: "Carrier vetting",             docs: "https://mycarrierportal.com",        category: .carrierVetting),
        .init(roleKey: "BROKER", slug: "greenscreens",   name: "Greenscreens.ai",    function: "AI-blended pricing",          docs: "https://greenscreens.ai",            category: .rateData),
        .init(roleKey: "BROKER", slug: "parade",          name: "Parade",             function: "Carrier-side capacity matching", docs: "https://parade.ai",               category: .carrierVetting),
        .init(roleKey: "BROKER", slug: "vector",          name: "Vector",             function: "Document automation",         docs: "https://www.withvector.com",         category: .docs),
        .init(roleKey: "BROKER", slug: "transflo",        name: "Transflo",           function: "BOL / POD imaging",           docs: "https://transflo.com/api",            category: .docs),
        .init(roleKey: "BROKER", slug: "salesforce",      name: "Salesforce",         function: "Customer CRM",                docs: "https://developer.salesforce.com",   category: .crm),
    ]

    private static let truckDriver: [RoleIntegration] = [
        .init(roleKey: "DRIVER", slug: "pcmiler",        name: "Trimble PC*MILER",   function: "Truck-routed navigation",     docs: "https://developer.trimblemaps.com",            category: .nav),
        .init(roleKey: "DRIVER", slug: "promiles",       name: "ProMiles",            function: "IFTA + fuel-optimized routing", docs: "https://promiles.com",               category: .nav),
        .init(roleKey: "DRIVER", slug: "trucker-path",    name: "Trucker Path",        function: "Parking + amenities",         docs: "https://truckerpath.com",             category: .nav),
        .init(roleKey: "DRIVER", slug: "hammer",          name: "Hammer",              function: "Truck navigation app",        docs: "https://hammer.app",                  category: .nav),
        .init(roleKey: "DRIVER", slug: "tsd-fuel",        name: "TSD Logistics Fuel Finder", function: "Discounted diesel",     docs: "https://tsdlogistics.com",            category: .fuelCard),
        .init(roleKey: "DRIVER", slug: "gasbuddy",        name: "GasBuddy",            function: "Retail fuel prices",          docs: "https://business.gasbuddy.com",       category: .fuelCard),
        .init(roleKey: "DRIVER", slug: "dtn-weather",    name: "DTN Weather",         function: "Hazardous-weather alerts",    docs: "https://devportal.dtn.com",           category: .weather),
        .init(roleKey: "DRIVER", slug: "openweather",     name: "OpenWeather",        function: "Forecast",                    docs: "https://openweathermap.org/api",     category: .weather),
        .init(roleKey: "DRIVER", slug: "geotab-drive",    name: "Geotab Drive",       function: "ELD driver app",              docs: "https://developers.geotab.com",      category: .eld),
        .init(roleKey: "DRIVER", slug: "samsara-driver",  name: "Samsara Driver",     function: "Driver workflow",             docs: "https://developers.samsara.com",     category: .eld),
        .init(roleKey: "DRIVER", slug: "motive-driver",   name: "Motive Driver",      function: "HOS + DVIR",                  docs: "https://developer.gomotive.com",     category: .eld),
        .init(roleKey: "DRIVER", slug: "plaid",           name: "Plaid",              function: "Bank-link for direct deposit", docs: "https://plaid.com/docs",            category: .banking),
        .init(roleKey: "DRIVER", slug: "stripe-issuing",  name: "Stripe Issuing",     function: "Driver debit card",            docs: "https://stripe.com/docs/issuing",   category: .payments),
        .init(roleKey: "DRIVER", slug: "escreen",         name: "DriversCheck (eScreen)", function: "Drug testing",             docs: "https://www.escreen.com",            category: .bgScreening),
        .init(roleKey: "DRIVER", slug: "fmcsa-clearinghouse", name: "FMCSA Clearinghouse", function: "Mandatory queries",      docs: "https://clearinghouse.fmcsa.dot.gov", category: .compliance),
        .init(roleKey: "DRIVER", slug: "twilio",          name: "Twilio",             function: "Dispatcher comms",             docs: "https://twilio.com/docs",            category: .crm),
        .init(roleKey: "DRIVER", slug: "vector-mobile",   name: "Vector mobile",      function: "POD capture",                  docs: "https://withvector.com",             category: .docs),
    ]

    private static let truckDispatch: [RoleIntegration] = [
        .init(roleKey: "DISPATCH", slug: "onfleet",       name: "Onfleet",       function: "Route optimization",         docs: "https://docs.onfleet.com",      category: .dispatch),
        .init(roleKey: "DISPATCH", slug: "routific",     name: "Routific",      function: "Multi-stop optimization",   docs: "https://docs.routific.com",           category: .dispatch),
        .init(roleKey: "DISPATCH", slug: "optimoroute",   name: "OptimoRoute",   function: "Route + appt optimizer",     docs: "https://optimoroute.com/api",        category: .dispatch),
        .init(roleKey: "DISPATCH", slug: "geotab",        name: "Geotab",        function: "Live fleet position",        docs: "https://developers.geotab.com",      category: .eld),
        .init(roleKey: "DISPATCH", slug: "samsara",       name: "Samsara",       function: "Live tracking + alerts",     docs: "https://developers.samsara.com",     category: .eld),
        .init(roleKey: "DISPATCH", slug: "motive",        name: "Motive",        function: "Driver assignments",         docs: "https://developer.gomotive.com",     category: .eld),
        .init(roleKey: "DISPATCH", slug: "pcmiler-ws",    name: "PC*MILER Web",  function: "Routing API",                docs: "https://developer.trimblemaps.com",  category: .nav),
        .init(roleKey: "DISPATCH", slug: "dat-power",     name: "DAT Power",     function: "Load coverage",              docs: "https://www.dat.com/api-integration",                category: .loadBoard),
        .init(roleKey: "DISPATCH", slug: "truckstop",     name: "Truckstop",     function: "Backhaul search",            docs: "https://developer.truckstop.com",          category: .loadBoard),
        .init(roleKey: "DISPATCH", slug: "project44",      name: "project44",     function: "Predictive ETA",             docs: "https://developers.project44.com/api-reference", category: .visibility),
        .init(roleKey: "DISPATCH", slug: "fourkites",     name: "FourKites",     function: "Exception alerts",           docs: "https://developer.fourkites.com",    category: .visibility),
        .init(roleKey: "DISPATCH", slug: "highway",       name: "Highway",       function: "Assignment vetting",         docs: "https://help.highway.com",     category: .carrierVetting),
        .init(roleKey: "DISPATCH", slug: "bestpass",      name: "Bestpass",      function: "Toll-aware routing",         docs: "https://www.bestpass.com",           category: .toll),
        .init(roleKey: "DISPATCH", slug: "trimble-weather", name: "Trimble Maps Weather", function: "Lane weather risk", docs: "https://developer.trimblemaps.com",    category: .weather),
        .init(roleKey: "DISPATCH", slug: "docusign",       name: "DocuSign",       function: "Rate confirmation signing", docs: "https://developers.docusign.com",    category: .docs),
        .init(roleKey: "DISPATCH", slug: "twilio",        name: "Twilio",         function: "Dispatcher SMS/voice",       docs: "https://twilio.com/docs",            category: .crm),
    ]

    private static let truckEscort: [RoleIntegration] = [
        .init(roleKey: "ESCORT", slug: "jjkeller-permits", name: "J.J. Keller Permits", function: "OS/OW state permits",     docs: "https://jjkeller.com",                category: .compliance),
        .init(roleKey: "ESCORT", slug: "promiles-hh",      name: "ProMiles HeavyHaul",  function: "Heavy-haul routing",      docs: "https://promiles.com",                category: .nav),
        .init(roleKey: "ESCORT", slug: "pcmiler-ow",       name: "PC*MILER OW",         function: "Oversize routing",        docs: "https://developer.trimblemaps.com",            category: .nav),
        .init(roleKey: "ESCORT", slug: "bestpass",         name: "Bestpass",            function: "Toll-aware routing",      docs: "https://www.bestpass.com",            category: .toll),
        .init(roleKey: "ESCORT", slug: "prepass",          name: "PrePass",             function: "Bypass",                  docs: "https://prepass.com",             category: .toll),
        .init(roleKey: "ESCORT", slug: "fhwa-nbi",         name: "FHWA NBI",            function: "Bridge clearance",        docs: "https://infobridge.fhwa.dot.gov",     category: .compliance),
        .init(roleKey: "ESCORT", slug: "state-511",        name: "State 511",           function: "Real-time road conditions", docs: "https://ops.fhwa.dot.gov/travelinfo/about/about511.htm",                  category: .nav),
        .init(roleKey: "ESCORT", slug: "dtn-weather",      name: "DTN Weather",         function: "Severe weather alerts",   docs: "https://devportal.dtn.com",           category: .weather),
        .init(roleKey: "ESCORT", slug: "openweather",      name: "OpenWeather",         function: "Forecast",                docs: "https://openweathermap.org/api",     category: .weather),
        .init(roleKey: "ESCORT", slug: "twilio",           name: "Twilio",              function: "Pilot-driver radio bridge", docs: "https://twilio.com/docs",            category: .crm),
        .init(roleKey: "ESCORT", slug: "garmin-inreach",   name: "Garmin inReach",      function: "Satellite SOS + tracking", docs: "https://developer.garmin.com",       category: .satellite),
        .init(roleKey: "ESCORT", slug: "what3words",       name: "What3words",          function: "Pinpoint location",       docs: "https://developer.what3words.com",    category: .nav),
        .init(roleKey: "ESCORT", slug: "docusign",         name: "DocuSign",            function: "Permit acknowledgement",  docs: "https://developers.docusign.com",    category: .docs),
        .init(roleKey: "ESCORT", slug: "fed511",           name: "DOT 511 Federal",     function: "National traveler info",  docs: "https://ops.fhwa.dot.gov/travelinfo/about/about511.htm",                    category: .nav),
    ]

    private static let truckTerminalManager: [RoleIntegration] = [
        .init(roleKey: "TERMINAL_MANAGER", slug: "dearman",          name: "Dearman Systems",      function: "Bulk-liquid terminal automation", docs: "https://dearmansystems.com",     category: .terminalAuto),
        .init(roleKey: "TERMINAL_MANAGER", slug: "navis-n4",         name: "Navis SPARCS N4",      function: "Container TOS",                  docs: "https://kaleris.com/navis",       category: .terminalAuto),
        .init(roleKey: "TERMINAL_MANAGER", slug: "tideworks",        name: "Tideworks Mainsail",   function: "TOS",                            docs: "https://tideworks.com",           category: .terminalAuto),
        .init(roleKey: "TERMINAL_MANAGER", slug: "opus-terminal",    name: "OPUS Terminal",        function: "Modern TOS",                     docs: "https://www.cyberlogitec.com/en/sub/solution/port/opus_terminal.php", category: .terminalAuto),
        .init(roleKey: "TERMINAL_MANAGER", slug: "portpro",          name: "PortPro drayOS",       function: "Drayage TMS",                    docs: "https://portpro.io",              category: .tms),
        .init(roleKey: "TERMINAL_MANAGER", slug: "pinc",             name: "PINC",                  function: "Yard management + RFID",        docs: "https://www.kaleris.com/yard-management",             category: .yard),
        .init(roleKey: "TERMINAL_MANAGER", slug: "cargomatic",       name: "Cargomatic",            function: "Drayage marketplace",            docs: "https://api-docs-acceptance.cargomatic.com", category: .loadBoard),
        .init(roleKey: "TERMINAL_MANAGER", slug: "opendock",          name: "Opendock",             function: "Dock scheduling",                docs: "https://opendock.com/api",         category: .dockSched),
        .init(roleKey: "TERMINAL_MANAGER", slug: "dtn-fuels",        name: "DTN Refined Fuels",    function: "Rack pricing",                   docs: "https://devportal.dtn.com",        category: .marketIntel),
        .init(roleKey: "TERMINAL_MANAGER", slug: "eia",              name: "EIA Petroleum",         function: "Wholesale fuel benchmarks",      docs: "https://www.eia.gov/opendata/",         category: .marketIntel),
        .init(roleKey: "TERMINAL_MANAGER", slug: "ukg",              name: "UKG / Kronos",          function: "Labor management",               docs: "https://developer.ukg.com",     category: .workforce),
        .init(roleKey: "TERMINAL_MANAGER", slug: "adp",              name: "ADP Workforce Now",     function: "Payroll/labor",                  docs: "https://developers.adp.com",       category: .workforce),
        .init(roleKey: "TERMINAL_MANAGER", slug: "manhattan-wms",    name: "Manhattan WMS",         function: "Warehouse mgmt",                 docs: "https://developer.manh.com",         category: .warehouse),
        .init(roleKey: "TERMINAL_MANAGER", slug: "sap-ewm",          name: "SAP EWM",              function: "SAP warehouse",                  docs: "https://api.sap.com",              category: .warehouse),
        .init(roleKey: "TERMINAL_MANAGER", slug: "ms-d365",          name: "Microsoft Dynamics 365", function: "ERP (terminal accounting)",   docs: "https://learn.microsoft.com/dynamics365", category: .erp),
        .init(roleKey: "TERMINAL_MANAGER", slug: "opc-ua",           name: "OPC-UA",                function: "Hardware-agnostic instrument bridge", docs: "https://opcfoundation.org",     category: .terminalAuto),
        .init(roleKey: "TERMINAL_MANAGER", slug: "epa",              name: "EPA reporting",         function: "Compliance",                     docs: "https://epa.gov/cdx",              category: .compliance),
    ]

    private static let truckComplianceOfficer: [RoleIntegration] = [
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "fmcsa-safer",        name: "FMCSA SAFER",            function: "Carrier safety lookup",      docs: "https://safer.fmcsa.dot.gov",          category: .compliance),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "fmcsa-sms",          name: "FMCSA SMS BASIC",        function: "CSA scoring",                docs: "https://csa.fmcsa.dot.gov",             category: .compliance),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "fmcsa-clearinghouse",name: "FMCSA Clearinghouse",   function: "Drug & Alcohol queries",     docs: "https://clearinghouse.fmcsa.dot.gov", category: .compliance),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "fmcsa-psp",          name: "FMCSA PSP",              function: "Crash + inspection history", docs: "https://www.psp.fmcsa.dot.gov/psp",            category: .compliance),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "vucem",              name: "USMCA / VUCEM (MX)",     function: "Customs e-validation",       docs: "https://www.ventanillaunica.gob.mx",   category: .customs),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "cbp-ace",            name: "CBP ACE",                function: "ACE filings",                docs: "https://www.cbp.gov/trade/automated",            category: .customs),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "cbsa-carm",          name: "CBSA CARM",              function: "Importer portal",            docs: "https://www.cbsa-asfc.gc.ca/services/carm-gcra/menu-eng.html",     category: .customs),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "nom",                name: "NOM (MX)",               function: "Standards compliance",       docs: "https://www.gob.mx/se",                category: .compliance),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "fsma",               name: "FSMA (FDA)",             function: "Food transport",             docs: "https://www.fda.gov/fsma",             category: .compliance),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "adr",                name: "ADR (EU hazmat)",        function: "UN/ADR codes",               docs: "https://unece.org/adr",                category: .compliance),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "imdg",               name: "IMDG",                   function: "IMO Dangerous Goods",         docs: "https://www.imo.org",                  category: .compliance),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "ctpat",              name: "CTPAT / FAST / OEA",     function: "Trusted-trader programs",     docs: "https://cbp.gov/ctpat",                category: .compliance),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "smartway",           name: "EPA SmartWay",           function: "Carrier sustainability",      docs: "https://epa.gov/smartway",             category: .compliance),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "jjkeller-ecfr",      name: "J.J. Keller eCFR",       function: "Regulation library",          docs: "https://jjkeller.com",                  category: .compliance),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "ifta",               name: "IFTA portals",           function: "Quarterly fuel tax",          docs: "https://iftach.org",                   category: .compliance),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "osha",               name: "OSHA reporting",          function: "Workplace incidents",         docs: "https://osha.gov",                     category: .compliance),
        .init(roleKey: "COMPLIANCE_OFFICER", slug: "mcs-150",            name: "DOT MCS-150",             function: "Biennial update",             docs: "https://www.fmcsa.dot.gov",                category: .compliance),
    ]

    private static let truckSafetyManager: [RoleIntegration] = [
        .init(roleKey: "SAFETY_MANAGER", slug: "escreen",          name: "eScreen",            function: "Drug + alcohol testing",  docs: "https://escreen.com",            category: .bgScreening),
        .init(roleKey: "SAFETY_MANAGER", slug: "quest",            name: "Quest Diagnostics",  function: "Lab testing",             docs: "https://www.employersolutions.com", category: .bgScreening),
        .init(roleKey: "SAFETY_MANAGER", slug: "driverscheck",     name: "DriversCheck",       function: "Background + MVR",        docs: "https://driverscheck.com",        category: .bgScreening),
        .init(roleKey: "SAFETY_MANAGER", slug: "hireright",        name: "HireRight",          function: "Background checks",       docs: "https://hireright.com/api",       category: .bgScreening),
        .init(roleKey: "SAFETY_MANAGER", slug: "first-advantage",  name: "First Advantage",    function: "Driver background",       docs: "https://fadv.com",                category: .bgScreening),
        .init(roleKey: "SAFETY_MANAGER", slug: "trucker-tools",    name: "Trucker Tools",      function: "Driver performance",      docs: "https://truckertools.com",        category: .compliance),
        .init(roleKey: "SAFETY_MANAGER", slug: "infinit-i",        name: "Infinit-I Workforce", function: "DOT-compliant training", docs: "https://infinit-i.com",           category: .training),
        .init(roleKey: "SAFETY_MANAGER", slug: "luma",             name: "Luma Brighter Learning", function: "Driver training LMS", docs: "https://lumabrighterlearning.com/products/", category: .training),
        .init(roleKey: "SAFETY_MANAGER", slug: "jjkeller-tod",     name: "J.J. Keller Training", function: "Compliance training",  docs: "https://jjkeller.com/training",   category: .training),
        .init(roleKey: "SAFETY_MANAGER", slug: "sambasafety",      name: "SambaSafety",        function: "MVR continuous monitoring", docs: "https://developer.sambasafety.com",    category: .bgScreening),
        .init(roleKey: "SAFETY_MANAGER", slug: "motive-cam",       name: "Motive AI Cam",      function: "Dashcam events",           docs: "https://developer.gomotive.com",  category: .dashcam),
        .init(roleKey: "SAFETY_MANAGER", slug: "samsara-vision",   name: "Samsara Vision",     function: "AI dashcam",              docs: "https://developers.samsara.com",  category: .dashcam),
        .init(roleKey: "SAFETY_MANAGER", slug: "lytx",             name: "Lytx",               function: "Driver coaching dashcam", docs: "https://lytx.com",                category: .dashcam),
        .init(roleKey: "SAFETY_MANAGER", slug: "great-west",       name: "Great West",         function: "Trucking insurance",      docs: "https://gwccnet.com",             category: .insurance),
        .init(roleKey: "SAFETY_MANAGER", slug: "progressive",      name: "Progressive",        function: "Insurance",               docs: "https://progressivecommercial.com", category: .insurance),
        .init(roleKey: "SAFETY_MANAGER", slug: "ntsb-data",        name: "NTSB / DOT crash data", function: "Public safety datasets", docs: "https://data.transportation.gov", category: .compliance),
    ]

    private static let truckFactoring: [RoleIntegration] = [
        .init(roleKey: "FACTORING", slug: "haulpay",         name: "HaulPay",        function: "Factoring partner",         docs: "https://haulpay.io",            category: .factoring),
        .init(roleKey: "FACTORING", slug: "triumph",         name: "Triumph",         function: "Bank + factoring",          docs: "https://www.triumph.io",           category: .factoring),
        .init(roleKey: "FACTORING", slug: "otr-capital",     name: "OTR Capital",     function: "Factoring",                 docs: "https://otrcapital.com",        category: .factoring),
        .init(roleKey: "FACTORING", slug: "rts-financial",   name: "RTS Financial",   function: "Factoring",                 docs: "https://rtsinc.com/lp/factoring", category: .factoring),
        .init(roleKey: "FACTORING", slug: "apex",            name: "Apex Capital",    function: "Factoring",                 docs: "https://apexcapitalcorp.com",   category: .factoring),
        .init(roleKey: "FACTORING", slug: "tbs",             name: "TBS Factoring",   function: "Factoring",                 docs: "https://tbsfactoring.com",      category: .factoring),
        .init(roleKey: "FACTORING", slug: "ansonia",         name: "Ansonia Credit",  function: "Carrier credit data",       docs: "https://ansoniacreditdata.com", category: .factoring),
        .init(roleKey: "FACTORING", slug: "factorcloud",     name: "FactorCloud",     function: "Factoring software",        docs: "https://factorcloud.com",       category: .factoring),
        .init(roleKey: "FACTORING", slug: "compass",         name: "Compass Funding Solutions", function: "Freight factoring + invoice portal", docs: "https://compassfs.net", category: .factoring),
        .init(roleKey: "FACTORING", slug: "stripe-treasury", name: "Stripe Treasury", function: "Embedded banking",          docs: "https://stripe.com/docs/treasury", category: .banking),
        .init(roleKey: "FACTORING", slug: "plaid",           name: "Plaid",           function: "Bank linking",               docs: "https://plaid.com/docs",        category: .banking),
        .init(roleKey: "FACTORING", slug: "dwolla",          name: "Dwolla",          function: "ACH rails",                  docs: "https://developers.dwolla.com", category: .banking),
        .init(roleKey: "FACTORING", slug: "modern-treasury", name: "Modern Treasury", function: "Payment ops",                docs: "https://docs.moderntreasury.com", category: .banking),
        .init(roleKey: "FACTORING", slug: "persona",         name: "Persona",         function: "KYC / KYB",                  docs: "https://withpersona.com/docs",   category: .identity),
        .init(roleKey: "FACTORING", slug: "alloy",           name: "Alloy",           function: "Identity decisioning",      docs: "https://docs.alloy.com",        category: .identity),
        .init(roleKey: "FACTORING", slug: "ofac",            name: "OFAC SDN",        function: "Sanctions screening",        docs: "https://treasury.gov/ofac",     category: .compliance),
        .init(roleKey: "FACTORING", slug: "docusign",        name: "DocuSign",        function: "Notice of Assignment",       docs: "https://developers.docusign.com", category: .docs),
    ]

    // MARK: - RAIL (6) — abbreviated to top providers per role

    private static let railShipper: [RoleIntegration] = [
        .init(roleKey: "RAIL_SHIPPER", slug: "bnsf",       name: "BNSF API Center",       function: "BOL tender + tracking",     docs: "https://www.bnsf.com",                  category: .railClassI),
        .init(roleKey: "RAIL_SHIPPER", slug: "up",          name: "Union Pacific eCustomer", function: "UP shipper tools",        docs: "https://www.up.com/customers",     category: .railClassI),
        .init(roleKey: "RAIL_SHIPPER", slug: "csx",         name: "CSX ShipCSX",           function: "Bookings + tracking",        docs: "https://shipcsx.com",                  category: .railClassI),
        .init(roleKey: "RAIL_SHIPPER", slug: "ns",          name: "Norfolk Southern AccessNS", function: "Tracing + tariffs",      docs: "https://www.accessns.com",             category: .railClassI),
        .init(roleKey: "RAIL_SHIPPER", slug: "cn",          name: "Canadian National",     function: "Shipper portal",             docs: "https://www.cn.ca/ebusiness",          category: .railClassI),
        .init(roleKey: "RAIL_SHIPPER", slug: "cpkc",        name: "CPKC",                  function: "Bookings",                   docs: "https://www.cpkcr.com",                category: .railClassI),
        .init(roleKey: "RAIL_SHIPPER", slug: "railinc",     name: "RailInc",               function: "Industry data exchange",     docs: "https://www.railinc.com",          category: .railIndustry),
        .init(roleKey: "RAIL_SHIPPER", slug: "aar",         name: "AAR",                   function: "Industry data",              docs: "https://aar.org",                      category: .railIndustry),
        .init(roleKey: "RAIL_SHIPPER", slug: "ttx",         name: "TTX Company",           function: "Intermodal car pool",        docs: "https://www.ttx.com",                  category: .railEquip),
        .init(roleKey: "RAIL_SHIPPER", slug: "steelroads",  name: "Steelroads",            function: "Multi-railroad tracing",     docs: "https://steelroads.com",               category: .railIndustry),
        .init(roleKey: "RAIL_SHIPPER", slug: "stb",         name: "STB",                   function: "Rate filings",               docs: "https://stb.gov",                      category: .compliance),
        .init(roleKey: "RAIL_SHIPPER", slug: "fra",          name: "FRA Safety",            function: "Incident data",              docs: "https://railroads.dot.gov",               category: .compliance),
        .init(roleKey: "RAIL_SHIPPER", slug: "iana",         name: "IANA",                  function: "Drayage interchange",        docs: "https://intermodal.org",                category: .railIndustry),
        .init(roleKey: "RAIL_SHIPPER", slug: "uirr",         name: "UIRR (EU)",             function: "EU intermodal",              docs: "https://www.uirr.com",                      category: .railIndustry),
        .init(roleKey: "RAIL_SHIPPER", slug: "railcarrx",    name: "Kaleris Railcar MRO",   function: "Railcar maintenance",        docs: "https://kaleris.com/solutions/maintenance-repair-operations/railcar/", category: .railEquip),
        .init(roleKey: "RAIL_SHIPPER", slug: "gatx",         name: "GATX / Trinity",        function: "Railcar leasing",            docs: "https://www.gatx.com",                  category: .railEquip),
    ]

    // For brevity the remaining rail + vessel + customs tables are
    // shipped as compact inline lists. Each row is doc-verified per
    // the role_integration_mapping.md doctrine.

    private static let railCatalyst: [RoleIntegration] = railShipper.map {
        RoleIntegration(roleKey: "RAIL_CATALYST", slug: $0.slug, name: $0.name, function: $0.function, docs: $0.docs, category: $0.category)
    } + [
        .init(roleKey: "RAIL_CATALYST", slug: "wabtec-ptc", name: "Wabtec ETMS / PTC",    function: "Locomotive control",  docs: "https://www.wabteccorp.com",        category: .railOps),
        .init(roleKey: "RAIL_CATALYST", slug: "trimble-rail", name: "Trimble Rail",       function: "Asset/track mgmt",     docs: "https://rail.trimble.com",       category: .railOps),
        .init(roleKey: "RAIL_CATALYST", slug: "railcomm",   name: "RailComm DOC",          function: "Yard automation",      docs: "https://railcomm.com",          category: .railOps),
    ]

    private static let railDispatcher: [RoleIntegration] = [
        .init(roleKey: "RAIL_DISPATCHER", slug: "wabtec-etms", name: "Wabtec ETMS",        function: "Train control",         docs: "https://www.wabteccorp.com",       category: .railOps),
        .init(roleKey: "RAIL_DISPATCHER", slug: "hitachi-stms", name: "Hitachi Rail STMS", function: "Signaling",             docs: "https://www.hitachirail.com", category: .railOps),
        .init(roleKey: "RAIL_DISPATCHER", slug: "railcomm",     name: "RailComm DOC",      function: "Yard moves",            docs: "https://railcomm.com",         category: .railOps),
        .init(roleKey: "RAIL_DISPATCHER", slug: "railinc-umler",name: "RailInc Umler",     function: "Car data",              docs: "https://www.railinc.com",      category: .railIndustry),
        .init(roleKey: "RAIL_DISPATCHER", slug: "ttx",          name: "TTX",                function: "Pool cars",             docs: "https://www.ttx.com",          category: .railEquip),
        .init(roleKey: "RAIL_DISPATCHER", slug: "pscs",         name: "PS Technology CrewPro", function: "Crew management + calling", docs: "https://pstechnology.com/crewpro/", category: .railOps),
        .init(roleKey: "RAIL_DISPATCHER", slug: "nws-aviation", name: "NWS",               function: "Severe weather",         docs: "https://www.weather.gov/documentation/services-web-api",      category: .weather),
        .init(roleKey: "RAIL_DISPATCHER", slug: "dtn-weather",  name: "DTN Weather",       function: "Lane forecast",          docs: "https://devportal.dtn.com",    category: .weather),
        .init(roleKey: "RAIL_DISPATCHER", slug: "fra-incidents", name: "FRA accident",     function: "Incident filings",       docs: "https://railroads.dot.gov",           category: .compliance),
        .init(roleKey: "RAIL_DISPATCHER", slug: "stb",          name: "STB",                function: "Performance reports",    docs: "https://stb.gov",               category: .compliance),
        .init(roleKey: "RAIL_DISPATCHER", slug: "raildocs",     name: "Wabtec RailDOCS",   function: "Wayside asset inspection + configuration", docs: "https://www.wabteccorp.com/digital-intelligence/signaling-and-train-control/information-management/raildocs", category: .railOps),
        .init(roleKey: "RAIL_DISPATCHER", slug: "bentley-aw",   name: "Bentley AssetWise", function: "Track condition",        docs: "https://bentley.com",           category: .railOps),
        .init(roleKey: "RAIL_DISPATCHER", slug: "trimble-rail", name: "Trimble Rail",      function: "Network view",           docs: "https://trimble.com",            category: .railOps),
    ]

    private static let railEngineer: [RoleIntegration] = railDispatcher.map {
        RoleIntegration(roleKey: "RAIL_ENGINEER", slug: $0.slug, name: $0.name, function: $0.function, docs: $0.docs, category: $0.category)
    }

    private static let railConductor: [RoleIntegration] = railDispatcher.map {
        RoleIntegration(roleKey: "RAIL_CONDUCTOR", slug: $0.slug, name: $0.name, function: $0.function, docs: $0.docs, category: $0.category)
    } + [
        .init(roleKey: "RAIL_CONDUCTOR", slug: "imdg",   name: "IMDG / ADR",    function: "DG codes",        docs: "https://www.imo.org",      category: .compliance),
        .init(roleKey: "RAIL_CONDUCTOR", slug: "epa-haz", name: "EPA hazmat",   function: "Spill reporting", docs: "https://epa.gov",          category: .compliance),
        .init(roleKey: "RAIL_CONDUCTOR", slug: "garmin-inreach", name: "Garmin inReach", function: "SOS / position", docs: "https://developer.garmin.com", category: .satellite),
    ]

    private static let railBroker: [RoleIntegration] = railShipper.map {
        RoleIntegration(roleKey: "RAIL_BROKER", slug: $0.slug, name: $0.name, function: $0.function, docs: $0.docs, category: $0.category)
    } + [
        .init(roleKey: "RAIL_BROKER", slug: "stripe",          name: "Stripe",          function: "Customer billing", docs: "https://stripe.com",         category: .payments),
        .init(roleKey: "RAIL_BROKER", slug: "salesforce",      name: "Salesforce",      function: "CRM",              docs: "https://developer.salesforce.com", category: .crm),
    ]

    // MARK: - VESSEL (6)

    private static let vesselShipper: [RoleIntegration] = [
        .init(roleKey: "VESSEL_SHIPPER", slug: "inttra",       name: "INTTRA (E2open)",      function: "Multi-carrier ocean booking", docs: "https://apidocs.inttra.com",        category: .oceanBooking),
        .init(roleKey: "VESSEL_SHIPPER", slug: "cargosmart",   name: "CargoSmart (GSBN)",    function: "Visibility + booking",        docs: "https://www.cargosmart.com",     category: .oceanBooking),
        .init(roleKey: "VESSEL_SHIPPER", slug: "maersk",        name: "Maersk Spot / API",   function: "Maersk booking + rates",      docs: "https://developer.maersk.com",       category: .oceanCarrier),
        .init(roleKey: "VESSEL_SHIPPER", slug: "msc",           name: "MSC EDI/API",          function: "MSC integration",             docs: "https://msc.com/digital-solutions",  category: .oceanCarrier),
        .init(roleKey: "VESSEL_SHIPPER", slug: "one",           name: "ONE",                  function: "Booking + tracking",          docs: "https://www.one-line.com",           category: .oceanCarrier),
        .init(roleKey: "VESSEL_SHIPPER", slug: "hapag",         name: "Hapag-Lloyd",          function: "Booking + rates",             docs: "https://www.hapag-lloyd.com/en/services-information/data-solutions/api-portal.html", category: .oceanCarrier),
        .init(roleKey: "VESSEL_SHIPPER", slug: "cmacgm",        name: "CMA CGM",              function: "Booking",                     docs: "https://api-portal.cma-cgm.com/products/transport-execution", category: .oceanCarrier),
        .init(roleKey: "VESSEL_SHIPPER", slug: "cosco",         name: "COSCO",                function: "Booking",                     docs: "https://elines.coscoshipping.com",          category: .oceanCarrier),
        .init(roleKey: "VESSEL_SHIPPER", slug: "evergreen",     name: "Evergreen",            function: "Booking",                     docs: "https://www.evergreen-line.com",         category: .oceanCarrier),
        .init(roleKey: "VESSEL_SHIPPER", slug: "zim",           name: "ZIM",                  function: "Visibility",                  docs: "https://www.zim.com",                category: .oceanCarrier),
        .init(roleKey: "VESSEL_SHIPPER", slug: "yang-ming",     name: "Yang Ming",            function: "Booking",                     docs: "https://www.yangming.com/en/esolution/digital_solution/api_introduction", category: .oceanCarrier),
        .init(roleKey: "VESSEL_SHIPPER", slug: "oocl",          name: "OOCL",                 function: "Booking",                     docs: "https://www.oocl.com/eng/ourservices/eservices/edi/Pages/default.aspx", category: .oceanCarrier),
        .init(roleKey: "VESSEL_SHIPPER", slug: "project44",     name: "project44 (ocean)",    function: "Visibility",                  docs: "https://developers.project44.com/api-reference", category: .visibility),
        .init(roleKey: "VESSEL_SHIPPER", slug: "fourkites-ocean", name: "FourKites Ocean",   function: "Visibility",                  docs: "https://developer.fourkites.com",    category: .visibility),
        .init(roleKey: "VESSEL_SHIPPER", slug: "descartes-customs", name: "Descartes Customs", function: "ACE/AES filings",           docs: "https://descartes.com",              category: .customs),
        .init(roleKey: "VESSEL_SHIPPER", slug: "essdocs",       name: "essDOCS",              function: "eB/L",                        docs: "https://essdocs.com",                 category: .docs),
    ]

    private static let vesselOperator: [RoleIntegration] = [
        .init(roleKey: "VESSEL_OPERATOR", slug: "marinetraffic", name: "MarineTraffic",         function: "AIS positions",     docs: "https://servicedocs.marinetraffic.com/", category: .marine),
        .init(roleKey: "VESSEL_OPERATOR", slug: "vesselfinder",  name: "VesselFinder",          function: "AIS",               docs: "https://www.vesselfinder.com",        category: .marine),
        .init(roleKey: "VESSEL_OPERATOR", slug: "lloyds",        name: "Lloyd's List Intel",    function: "Shipping intel",    docs: "https://lloydslistintelligence.com", category: .oceanIntel),
        .init(roleKey: "VESSEL_OPERATOR", slug: "ihs",           name: "S&P Global Maritime", function: "Vessel registry", docs: "https://www.spglobal.com/market-intelligence/en/solutions/ship-and-port-data", category: .oceanIntel),
        .init(roleKey: "VESSEL_OPERATOR", slug: "kpler",         name: "Kpler",                  function: "Cargo flow",        docs: "https://kpler.com",                  category: .oceanIntel),
        .init(roleKey: "VESSEL_OPERATOR", slug: "sea-intel",     name: "Sea-Intelligence",      function: "Schedule reliability", docs: "https://sea-intelligence.com/services", category: .oceanIntel),
        .init(roleKey: "VESSEL_OPERATOR", slug: "dcsa",          name: "DCSA",                   function: "Standards",         docs: "https://dcsa.org",                   category: .oceanIntel),
        .init(roleKey: "VESSEL_OPERATOR", slug: "inttra-sched",  name: "INTTRA Schedules",      function: "Carrier schedules", docs: "https://apidocs.inttra.com",         category: .oceanBooking),
        .init(roleKey: "VESSEL_OPERATOR", slug: "integr8",       name: "Integr8 Fuels",         function: "Bunker fuel pricing", docs: "https://integr8fuels.com",          category: .bunker),
        .init(roleKey: "VESSEL_OPERATOR", slug: "bunkerex",      name: "BunkerEx",              function: "Bunker spot market", docs: "https://bunker-ex.com",              category: .bunker),
        .init(roleKey: "VESSEL_OPERATOR", slug: "wartsila",      name: "Wartsila",              function: "Vessel routing",    docs: "https://www.wartsila.com/marine/products/fleet-optimisation/voyage-and-ports/voyage-optimiser-tool", category: .marine),
        .init(roleKey: "VESSEL_OPERATOR", slug: "stormgeo",      name: "StormGeo",              function: "Voyage optimization", docs: "https://stormgeo.com/products/voyage-optimization", category: .marine),
        .init(roleKey: "VESSEL_OPERATOR", slug: "dtn-marine",    name: "DTN Marine",            function: "Marine forecasts",   docs: "https://dtn.com",                     category: .weather),
        .init(roleKey: "VESSEL_OPERATOR", slug: "noaa-marine",   name: "NWS Marine",            function: "NOAA",               docs: "https://weather.gov/marine",          category: .weather),
        .init(roleKey: "VESSEL_OPERATOR", slug: "imo-gisis",     name: "IMO GISIS",             function: "IMO regulatory",     docs: "https://gisis.imo.org",               category: .compliance),
        .init(roleKey: "VESSEL_OPERATOR", slug: "classnk",       name: "ClassNK / Lloyd's / DNV", function: "Class society",    docs: "https://www.classnk.or.jp",               category: .classSociety),
        .init(roleKey: "VESSEL_OPERATOR", slug: "inmarsat",      name: "Inmarsat / Iridium",    function: "Satcom",             docs: "https://inmarsat.com",                 category: .satcom),
    ]

    private static let portMaster: [RoleIntegration] = [
        .init(roleKey: "PORT_MASTER", slug: "navis-n4",     name: "Navis SPARCS N4",  function: "Container TOS",     docs: "https://kaleris.com/navis", category: .terminalAuto),
        .init(roleKey: "PORT_MASTER", slug: "tideworks",    name: "Tideworks Mainsail", function: "TOS",             docs: "https://tideworks.com",     category: .terminalAuto),
        .init(roleKey: "PORT_MASTER", slug: "opus",         name: "OPUS Terminal",     function: "TOS",               docs: "https://www.cyberlogitec.com/en/sub/solution/port/opus_terminal.php", category: .terminalAuto),
        .init(roleKey: "PORT_MASTER", slug: "rbs",          name: "RBS",               function: "Crane control",     docs: "https://hyster-yale.com",   category: .crane),
        .init(roleKey: "PORT_MASTER", slug: "konecranes",   name: "Konecranes",        function: "Crane telematics",  docs: "https://konecranes.com",    category: .crane),
        .init(roleKey: "PORT_MASTER", slug: "pinc",         name: "PINC",              function: "Yard / RFID",        docs: "https://www.kaleris.com/yard-management",          category: .yard),
        .init(roleKey: "PORT_MASTER", slug: "tba-spinosa",  name: "TBA Spinosa",       function: "Port community sys", docs: "https://www.tba.group",     category: .terminalAuto),
        .init(roleKey: "PORT_MASTER", slug: "portbase",     name: "Portbase",          function: "Port community sys", docs: "https://developer.portbase.com/", category: .terminalAuto),
        .init(roleKey: "PORT_MASTER", slug: "dcsa",         name: "DCSA",              function: "Standards",          docs: "https://dcsa.org",          category: .oceanIntel),
        .init(roleKey: "PORT_MASTER", slug: "inttra",       name: "INTTRA / CargoSmart", function: "Carrier hand-off", docs: "https://apidocs.inttra.com", category: .oceanBooking),
        .init(roleKey: "PORT_MASTER", slug: "cbp-ace",      name: "CBP ACE",           function: "Customs",             docs: "https://www.cbp.gov/trade/automated", category: .customs),
        .init(roleKey: "PORT_MASTER", slug: "ukg-adp",      name: "UKG / ADP",         function: "Labor mgmt",         docs: "https://www.ukg.com/",        category: .workforce),
        .init(roleKey: "PORT_MASTER", slug: "opc-ua",       name: "OPC-UA",            function: "PLC bridge",          docs: "https://opcfoundation.org", category: .terminalAuto),
        .init(roleKey: "PORT_MASTER", slug: "noaa-marine",  name: "NWS Marine",        function: "Weather",             docs: "https://weather.gov/marine", category: .weather),
        .init(roleKey: "PORT_MASTER", slug: "dtn-marine",   name: "DTN Marine",        function: "Forecasts",           docs: "https://dtn.com",            category: .weather),
        .init(roleKey: "PORT_MASTER", slug: "imdg",         name: "IMDG",              function: "Hazmat",              docs: "https://www.imo.org",        category: .compliance),
    ]

    private static let shipCaptain: [RoleIntegration] = [
        .init(roleKey: "SHIP_CAPTAIN", slug: "wartsila-nacos", name: "Wartsila NACOS",     function: "Bridge / navigation", docs: "https://www.wartsila.com/marine/products/marine-navigation-solutions", category: .marine),
        .init(roleKey: "SHIP_CAPTAIN", slug: "stormgeo-bv",    name: "StormGeo Bon Voyage", function: "Weather routing",     docs: "https://stormgeo.com/products/voyage-optimization", category: .marine),
        .init(roleKey: "SHIP_CAPTAIN", slug: "dtn-marine",     name: "DTN Marine",         function: "Marine forecasts",    docs: "https://dtn.com",                     category: .weather),
        .init(roleKey: "SHIP_CAPTAIN", slug: "noaa-marine",    name: "NWS Marine",         function: "Forecasts",           docs: "https://weather.gov/marine",          category: .weather),
        .init(roleKey: "SHIP_CAPTAIN", slug: "marinetraffic",  name: "MarineTraffic",      function: "AIS",                 docs: "https://servicedocs.marinetraffic.com/", category: .marine),
        .init(roleKey: "SHIP_CAPTAIN", slug: "vesselfinder",   name: "VesselFinder",       function: "AIS",                 docs: "https://vesselfinder.com",            category: .marine),
        .init(roleKey: "SHIP_CAPTAIN", slug: "inmarsat",       name: "Inmarsat",           function: "Satcom",              docs: "https://inmarsat.com",                category: .satcom),
        .init(roleKey: "SHIP_CAPTAIN", slug: "iridium",        name: "Iridium",            function: "Satcom backup",       docs: "https://www.iridium.com/developer-resources/", category: .satcom),
        .init(roleKey: "SHIP_CAPTAIN", slug: "imo-gisis",      name: "IMO GISIS",          function: "Compliance",          docs: "https://gisis.imo.org",                category: .compliance),
        .init(roleKey: "SHIP_CAPTAIN", slug: "classnk",        name: "ClassNK / DNV",      function: "Class society",       docs: "https://www.classnk.or.jp",                category: .classSociety),
        .init(roleKey: "SHIP_CAPTAIN", slug: "ukho",           name: "UKHO Admiralty",     function: "Charts",              docs: "https://admiralty.co.uk",              category: .marine),
        .init(roleKey: "SHIP_CAPTAIN", slug: "noaa-charts",    name: "NOAA Charts",        function: "US charts",           docs: "https://nauticalcharts.noaa.gov",     category: .marine),
        .init(roleKey: "SHIP_CAPTAIN", slug: "adonis",         name: "Adonis HR",          function: "Crew payroll/cert",   docs: "https://adonishr.com",                 category: .workforce),
        .init(roleKey: "SHIP_CAPTAIN", slug: "integr8",        name: "Integr8 Fuels",      function: "Bunker tracking",     docs: "https://integr8fuels.com",             category: .bunker),
        .init(roleKey: "SHIP_CAPTAIN", slug: "imdg",           name: "IMDG",                function: "Cargo declaration",   docs: "https://www.imo.org",                  category: .compliance),
        .init(roleKey: "SHIP_CAPTAIN", slug: "marpol",         name: "MARPOL e-records",   function: "Environmental log",   docs: "https://www.imo.org",                  category: .compliance),
        .init(roleKey: "SHIP_CAPTAIN", slug: "twilio-sat",     name: "Twilio (over satcom)", function: "Comms",            docs: "https://twilio.com/docs",              category: .crm),
    ]

    private static let vesselBroker: [RoleIntegration] = [
        .init(roleKey: "VESSEL_BROKER", slug: "baltic",      name: "Baltic Exchange",       function: "Indices + spot market",   docs: "https://www.balticexchange.com",     category: .oceanIntel),
        .init(roleKey: "VESSEL_BROKER", slug: "clarksons",   name: "Clarksons Research",    function: "Shipping intel",          docs: "https://www.clarksons.com",          category: .oceanIntel),
        .init(roleKey: "VESSEL_BROKER", slug: "lloyds",      name: "Lloyd's List Intel",   function: "Shipping intel",           docs: "https://lloydslistintelligence.com", category: .oceanIntel),
        .init(roleKey: "VESSEL_BROKER", slug: "ihs",         name: "S&P Global Maritime", function: "Registry + intel", docs: "https://www.spglobal.com/market-intelligence/en/solutions/ship-and-port-data", category: .oceanIntel),
        .init(roleKey: "VESSEL_BROKER", slug: "kpler",       name: "Kpler",                 function: "Cargo flow",                docs: "https://kpler.com",                  category: .oceanIntel),
        .init(roleKey: "VESSEL_BROKER", slug: "q88",         name: "Q88 / Vesseltracker",   function: "Vessel docs",               docs: "https://q88.com",                    category: .oceanIntel),
        .init(roleKey: "VESSEL_BROKER", slug: "sedna",       name: "Sedna Communications",  function: "Maritime email mgmt",       docs: "https://sedna.com",                  category: .crm),
        .init(roleKey: "VESSEL_BROKER", slug: "veson",       name: "Veson IMOS",            function: "S&P + chartering",          docs: "https://veson.com",                  category: .oceanBooking),
        .init(roleKey: "VESSEL_BROKER", slug: "datalastic",  name: "DataLastic / Spire",   function: "Vessel data",                docs: "https://datalastic.com",             category: .marine),
        .init(roleKey: "VESSEL_BROKER", slug: "inttra-spot", name: "INTTRA Spot Rates",     function: "Spot rate sourcing",        docs: "https://apidocs.inttra.com",         category: .oceanBooking),
        .init(roleKey: "VESSEL_BROKER", slug: "bimco",       name: "BIMCO documents",       function: "Charter party templates",   docs: "https://bimco.org",                  category: .docs),
        .init(roleKey: "VESSEL_BROKER", slug: "docusign",    name: "DocuSign",              function: "CP signature",              docs: "https://developers.docusign.com",     category: .docs),
        .init(roleKey: "VESSEL_BROKER", slug: "stripe",      name: "Stripe",                function: "Customer billing",          docs: "https://stripe.com",                  category: .payments),
        .init(roleKey: "VESSEL_BROKER", slug: "salesforce",  name: "Salesforce",            function: "CRM",                       docs: "https://developer.salesforce.com",    category: .crm),
        .init(roleKey: "VESSEL_BROKER", slug: "netsuite",    name: "NetSuite",              function: "ERP",                       docs: "https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/book_1559132836.html", category: .erp),
        .init(roleKey: "VESSEL_BROKER", slug: "stormgeo",    name: "StormGeo",             function: "Voyage performance",        docs: "https://stormgeo.com/products/voyage-optimization", category: .marine),
        .init(roleKey: "VESSEL_BROKER", slug: "marinetraffic",name: "MarineTraffic",       function: "AIS",                       docs: "https://servicedocs.marinetraffic.com/", category: .marine),
    ]

    private static let customsBroker: [RoleIntegration] = [
        .init(roleKey: "CUSTOMS_BROKER", slug: "cbp-ace",        name: "CBP ACE",                function: "Customs e-filing",      docs: "https://www.cbp.gov/trade/automated",         category: .customs),
        .init(roleKey: "CUSTOMS_BROKER", slug: "ctpat",          name: "CBP CTPAT",              function: "Trusted trader",        docs: "https://cbp.gov/ctpat",             category: .customs),
        .init(roleKey: "CUSTOMS_BROKER", slug: "vucem",          name: "Mexico VUCEM",            function: "Mexican customs",       docs: "https://www.ventanillaunica.gob.mx", category: .customs),
        .init(roleKey: "CUSTOMS_BROKER", slug: "carm",            name: "CBSA CARM",              function: "Importer revenue",      docs: "https://www.cbsa-asfc.gc.ca/services/carm-gcra/menu-eng.html",   category: .customs),
        .init(roleKey: "CUSTOMS_BROKER", slug: "eaeo",            name: "EU Customs",              function: "EU customs",            docs: "https://taxation-customs.ec.europa.eu", category: .customs),
        .init(roleKey: "CUSTOMS_BROKER", slug: "descartes",       name: "Descartes Customs",       function: "Filing platform",       docs: "https://descartes.com",              category: .customs),
        .init(roleKey: "CUSTOMS_BROKER", slug: "thomson-onesource",name: "Thomson Reuters ONESOURCE", function: "Global trade mgmt", docs: "https://thomsonreuters.com/onesource", category: .customs),
        .init(roleKey: "CUSTOMS_BROKER", slug: "sap-gts",         name: "SAP GTS",                function: "SAP global trade",       docs: "https://api.sap.com",                category: .customs),
        .init(roleKey: "CUSTOMS_BROKER", slug: "e2open",          name: "E2open Global Trade",    function: "GTM",                   docs: "https://e2open.com",                 category: .customs),
        .init(roleKey: "CUSTOMS_BROKER", slug: "livingston",      name: "Livingston International", function: "Customs broker software", docs: "https://livingstonintl.com",       category: .customs),
        .init(roleKey: "CUSTOMS_BROKER", slug: "rps-descartes",   name: "Descartes Visual Compliance", function: "Denied parties", docs: "https://www.descartes.com/automated-denied-party-screening", category: .compliance),
        .init(roleKey: "CUSTOMS_BROKER", slug: "ofac",            name: "OFAC SDN",                function: "Sanctions list",         docs: "https://treasury.gov/ofac",          category: .compliance),
        .init(roleKey: "CUSTOMS_BROKER", slug: "ace-aes",         name: "Census ACE AES",          function: "Export filings",         docs: "https://www.census.gov/foreign-trade/aes/index.html",       category: .customs),
        .init(roleKey: "CUSTOMS_BROKER", slug: "inttra-cs",       name: "INTTRA / CargoSmart",     function: "Carrier docs",           docs: "https://apidocs.inttra.com",         category: .oceanBooking),
        .init(roleKey: "CUSTOMS_BROKER", slug: "essdocs",         name: "essDOCS",                  function: "eB/L",                   docs: "https://essdocs.com",                 category: .docs),
        .init(roleKey: "CUSTOMS_BROKER", slug: "docusign",        name: "DocuSign",                 function: "Power of attorney",     docs: "https://developers.docusign.com",     category: .docs),
        .init(roleKey: "CUSTOMS_BROKER", slug: "cargowise",       name: "Cargowise",                function: "Bonded inventory",      docs: "https://cargowise.com",               category: .customs),
    ]
}
