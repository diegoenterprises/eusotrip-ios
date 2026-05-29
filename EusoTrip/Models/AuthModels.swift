//
//  AuthModels.swift
//  EusoTrip — Codable shapes for auth.login / auth.me / registration.*
//
//  Backend authority:
//    frontend/server/routers.ts
//      auth.login            (publicProcedure.mutation)
//      auth.me               (publicProcedure.query)
//      auth.logout           (publicProcedure.mutation)
//      auth.forgotPassword   (publicProcedure.mutation)
//      auth.resetPassword    (publicProcedure.mutation)
//
//    frontend/server/routers/registration.ts
//      registration.registerDriver / registerShipper / registerCatalyst /
//      registerBroker / registerDispatch / registerEscort /
//      registerTerminalManager / registerComplianceOfficer /
//      registerSafetyManager / verifyEmail / resendVerification
//

import Foundation

// MARK: - Role

/// Mirrors EusoTrip backend role enum (see _core/auth.ts testUsers map).
enum EusoRole: String, CaseIterable, Codable, Hashable, Identifiable {
    case driver        = "DRIVER"
    case shipper       = "SHIPPER"
    case catalyst      = "CATALYST"       // "Carrier" in user-facing copy
    case broker        = "BROKER"
    case dispatch      = "DISPATCH"
    case escort        = "ESCORT"
    case terminal      = "TERMINAL_MANAGER"
    case compliance    = "COMPLIANCE_OFFICER"
    case safety        = "SAFETY_MANAGER"
    case admin         = "ADMIN"
    case superAdmin    = "SUPER_ADMIN"
    case factoring     = "FACTORING"

    // Rail
    case railShipper   = "RAIL_SHIPPER"
    case railCatalyst  = "RAIL_CATALYST"
    case railDispatch  = "RAIL_DISPATCHER"
    case railEngineer  = "RAIL_ENGINEER"
    case railConductor = "RAIL_CONDUCTOR"
    case railBroker    = "RAIL_BROKER"

    // Vessel
    case vesselShipper  = "VESSEL_SHIPPER"
    case vesselOperator = "VESSEL_OPERATOR"
    case portMaster     = "PORT_MASTER"
    case shipCaptain    = "SHIP_CAPTAIN"
    case vesselBroker   = "VESSEL_BROKER"
    case customsBroker  = "CUSTOMS_BROKER"

    var id: String { rawValue }

    /// User-facing display name.
    var displayName: String {
        switch self {
        case .driver:        return "Driver"
        case .shipper:       return "Shipper"
        case .catalyst:      return "Carrier"
        case .broker:        return "Broker"
        case .dispatch:      return "Dispatch"
        case .escort:        return "Escort"
        case .terminal:      return "Terminal Manager"
        case .compliance:    return "Compliance Officer"
        case .safety:        return "Safety Manager"
        case .admin:         return "Admin"
        case .superAdmin:    return "Super Admin"
        case .factoring:     return "Factoring"
        case .railShipper:   return "Rail Shipper"
        case .railCatalyst:  return "Rail Carrier"
        case .railDispatch:  return "Rail Dispatcher"
        case .railEngineer:  return "Rail Engineer"
        case .railConductor: return "Rail Conductor"
        case .railBroker:    return "Rail Broker"
        case .vesselShipper: return "Vessel Shipper"
        case .vesselOperator:return "Vessel Operator"
        case .portMaster:    return "Port Master"
        case .shipCaptain:   return "Ship Captain"
        case .vesselBroker:  return "Vessel Broker"
        case .customsBroker: return "Customs Broker"
        }
    }

    /// Short tagline shown on the role picker.
    var tagline: String {
        switch self {
        case .driver:   return "I drive loads. HOS, DVIR, pickup, POD."
        case .shipper:  return "I ship freight. Post loads, pick carriers."
        case .catalyst: return "I'm a carrier. Book loads, dispatch my fleet."
        case .broker:   return "I broker freight. Match shippers to carriers."
        case .dispatch: return "I dispatch trucks. Assign drivers, run the board."
        case .escort:   return "I escort oversize / hazmat loads."
        case .terminal: return "I run a terminal / yard / dock."
        case .compliance:return "I own compliance, FMCSA, audits."
        case .safety:   return "I own safety, incidents, training."
        default:        return displayName
        }
    }

    var iconSystemName: String {
        switch self {
        case .driver:    return "steeringwheel"
        case .shipper:   return "shippingbox"
        case .catalyst:  return "truck.box.fill"
        case .broker:    return "arrow.triangle.branch"
        case .dispatch:  return "dot.radiowaves.left.and.right"
        case .escort:    return "shield.lefthalf.filled"
        case .terminal:  return "building.2.crop.circle"
        case .compliance:return "checkmark.shield.fill"
        case .safety:    return "cross.case.fill"
        default:         return "person.crop.circle"
        }
    }

    /// The full 24-role roster the mobile sign-up picker surfaces —
    /// full parity with every `/register/{role}` path on the web
    /// (source: `frontend/client/src/pages/Register.tsx`). Rail +
    /// vessel + factoring + super-admin roles are included even
    /// though their backend procs haven't shipped yet; the picker
    /// presents them the same way the web does, and
    /// `CreateAccountView` gates the actual form behind
    /// `isSignupImplemented` so an unimplemented role lands on a
    /// "coming soon" waitlist card instead of failing silently.
    ///
    /// ADMIN is included because the backend's `registerAdmin`
    /// rejects every request without a SUPER_ADMIN-issued invite
    /// code, so shipping the form is safe even on App Store builds:
    /// an attacker can't self-provision without the code.
    static var primarySignupRoles: [EusoRole] {
        // Truck (12)
        [.driver, .catalyst, .shipper, .broker,
         .dispatch, .escort,
         .terminal, .compliance, .safety,
         .admin, .superAdmin, .factoring,
         // Rail (6)
         .railShipper, .railCatalyst, .railDispatch,
         .railEngineer, .railConductor, .railBroker,
         // Vessel (6)
         .vesselShipper, .vesselOperator, .portMaster,
         .shipCaptain, .vesselBroker, .customsBroker]
    }

    /// True when the server's `registration.register{Role}` proc is
    /// wired and the iOS RegistrationViewModel has a matching submit
    /// path. All 24 roles now have server procs (the 14 rail /
    /// vessel / factoring / super-admin procs landed on 2026-04-24
    /// using `createSimpleRoleUser` as a baseline pattern over the
    /// same metadata / notifications / gamification rails the
    /// original 10 use). Kept as an explicit property rather than
    /// hardcoding `true` everywhere so a future role-specific
    /// requirement (e.g., a 3rd-party license lookup) can gate just
    /// that role's form without touching every other screen.
    var isSignupImplemented: Bool { true }

    /// Transport modes this role can register against. Mirrors the web
    /// `REGISTRATION_ROLES[].modes` array in `frontend/client/src/pages/Register.tsx`.
    var modes: Set<TransportMode> {
        switch self {
        case .driver, .catalyst, .broker, .dispatch, .escort, .shipper:
            return [.truck]
        case .terminal, .compliance, .safety, .admin, .superAdmin, .factoring:
            return [.truck, .rail, .vessel]
        case .customsBroker:
            return [.truck, .vessel]
        case .railShipper, .railCatalyst, .railDispatch,
             .railEngineer, .railConductor, .railBroker:
            return [.rail]
        case .vesselShipper, .vesselOperator, .portMaster,
             .shipCaptain, .vesselBroker:
            return [.vessel]
        }
    }

    /// Requirements shown under each role card (first 3 shown + "+N more").
    var requirements: [String] {
        switch self {
        case .driver:        return ["CDL (Class A/B)", "Medical Certificate", "Hazmat/TWIC", "TSA Background"]
        case .catalyst:      return ["USDOT Number", "MC Authority", "Hazmat Authority", "Insurance ($1M+)"]
        case .shipper:       return ["PHMSA Registration", "EPA ID (if applicable)", "Insurance Certificate"]
        case .broker:        return ["Broker Authority", "Surety Bond ($75K)", "Insurance"]
        case .dispatch:      return ["Associated with Catalyst", "Hazmat Training (if applicable)"]
        case .escort:        return ["State Certifications", "Vehicle Insurance", "Equipment Requirements"]
        case .terminal:      return ["Facility EPA ID", "SPCC Plan", "State Permits"]
        case .compliance:    return ["Associated with Company", "Compliance Training"]
        case .safety:        return ["Associated with Company", "Safety Certifications"]
        case .admin:         return ["Invitation Code Required"]
        case .factoring:     return ["State Lender License", "Bank Partner", "UCC-1 Filings"]
        case .railShipper:   return ["STB Registration", "Insurance Certificate"]
        case .railCatalyst:  return ["STB Docket", "FRA Certificate", "Operating Authority"]
        case .railDispatch:  return ["FRA Dispatcher Cert", "Associated with Railroad"]
        case .railEngineer:  return ["Engineer Cert (49 CFR 240)", "Medical Fitness", "Rules Qualification"]
        case .railConductor: return ["Conductor Cert (49 CFR 242)", "Medical Fitness", "Rules Qualification"]
        case .railBroker:    return ["IMC Registration", "Surety Bond", "Insurance"]
        case .vesselShipper: return ["FMC Registration", "Insurance Certificate"]
        case .vesselOperator:return ["FMC License/Bond", "USCG Documentation", "ISM DOC"]
        case .portMaster:    return ["MTSA Security Plan", "TWIC", "Port Authority License"]
        case .shipCaptain:   return ["USCG License (MMC)", "STCW Certification", "TWIC", "Medical Certificate"]
        case .vesselBroker:  return ["FMC License", "Surety Bond", "Insurance"]
        case .customsBroker: return ["CBP Customs Broker License", "National Permit", "Surety Bond"]
        default:             return []
        }
    }

    /// Regulatory bodies shown under each role card.
    var regulations: [String] {
        switch self {
        case .driver:        return ["FMCSA", "TSA", "DOT"]
        case .catalyst:      return ["FMCSA", "PHMSA", "DOT 49 CFR"]
        case .shipper:       return ["PHMSA", "EPA RCRA", "DOT 49 CFR"]
        case .broker:        return ["FMCSA", "PHMSA"]
        case .dispatch:      return ["FMCSA"]
        case .escort:        return ["State DOT", "FHWA"]
        case .terminal:      return ["EPA", "OSHA", "EIA", "State DEQ"]
        case .compliance:    return ["Internal"]
        case .safety:        return ["FMCSA", "OSHA"]
        case .admin:         return ["Internal"]
        case .factoring:     return ["State Lending", "UCC Article 9"]
        case .railShipper:   return ["STB", "FRA", "DOT 49 CFR"]
        case .railCatalyst:  return ["STB", "FRA", "AAR"]
        case .railDispatch:  return ["FRA", "49 CFR Part 241"]
        case .railEngineer:  return ["FRA", "49 CFR Part 240"]
        case .railConductor: return ["FRA", "49 CFR Part 242"]
        case .railBroker:    return ["STB", "FRA"]
        case .vesselShipper: return ["FMC", "CBP", "USCG"]
        case .vesselOperator:return ["FMC", "USCG", "IMO"]
        case .portMaster:    return ["USCG", "MTSA", "CBP"]
        case .shipCaptain:   return ["USCG", "STCW", "IMO"]
        case .vesselBroker:  return ["FMC", "CBP"]
        case .customsBroker: return ["CBP", "FMC", "19 CFR"]
        default:             return []
        }
    }

    /// One-line description shown on each role card.
    var shortDescription: String {
        switch self {
        case .driver:        return "CDL holders — all endorsements including hazmat, tanker, doubles/triples"
        case .catalyst:      return "Trucking companies hauling all freight including hazmat, tanker, flatbed, dry van"
        case .shipper:       return "Companies shipping freight — oil, chemicals, dry goods, agriculture, and more"
        case .broker:        return "Freight brokers arranging transportation across all commodity types"
        case .dispatch:      return "Dispatchers and coordinators managing loads"
        case .escort:        return "Pilot/escort vehicle operators for oversized loads"
        case .terminal:      return "Terminal and warehouse facility managers — oil, chemical, dry bulk, intermodal"
        case .compliance:    return "Regulatory compliance specialists"
        case .safety:        return "Safety program managers"
        case .admin:         return "Platform administrators (by invitation only)"
        case .factoring:     return "Invoice factoring & ABL lenders for freight"
        case .railShipper:   return "Companies shipping freight by rail — bulk, intermodal, unit trains"
        case .railCatalyst:  return "Class I, II, III railroads and short lines"
        case .railDispatch:  return "Train dispatchers coordinating rail movements"
        case .railEngineer:  return "Locomotive engineers — certified under 49 CFR Part 240"
        case .railConductor: return "Train conductors — certified under 49 CFR Part 242"
        case .railBroker:    return "Intermodal marketing companies and rail freight brokers"
        case .vesselShipper: return "Companies shipping freight by ocean — containerized, bulk, breakbulk"
        case .vesselOperator:return "VOCC and NVOCC operators — ocean freight carriers"
        case .portMaster:    return "Port authorities and terminal operators"
        case .shipCaptain:   return "Licensed mariners — STCW certified masters"
        case .vesselBroker:  return "Ocean freight forwarders and vessel brokers"
        case .customsBroker: return "Licensed customs brokers — CBP entry processing"
        default:             return displayName
        }
    }

    var isInviteOnly: Bool { self == .admin }

    /// All roles exposed on the multi-modal registration page.
    static var allSignupRoles: [EusoRole] {
        [.shipper, .catalyst, .broker, .driver, .dispatch, .escort,
         .terminal, .compliance, .safety, .admin,
         .railShipper, .railCatalyst, .railDispatch,
         .railEngineer, .railConductor, .railBroker,
         .vesselShipper, .vesselOperator, .portMaster,
         .shipCaptain, .vesselBroker, .customsBroker, .factoring]
    }
}

// MARK: - Registration taxonomy (country + mode)

/// Country options on the multi-modal registration wizard.
enum RegistrationCountry: String, CaseIterable, Identifiable, Hashable {
    case us = "US"
    case ca = "CA"
    case mx = "MX"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .us: return "United States"
        case .ca: return "Canada"
        case .mx: return "Mexico"
        }
    }

    /// Short regulatory blurb shown under each country card.
    var regulatoryBlurb: String {
        switch self {
        case .us: return "FMCSA / DOT / FRA / USCG regulated operations"
        case .ca: return "Transport Canada / TDG / Railway Safety Act"
        case .mx: return "SCT / NOM / Ley de Navegación"
        }
    }

    /// Simple flag emoji used as a fallback when no SVG is bundled.
    var flagEmoji: String {
        switch self {
        case .us: return "🇺🇸"
        case .ca: return "🇨🇦"
        case .mx: return "🇲🇽"
        }
    }
}

// 2026-05-17 — The registration-wizard `TransportMode` enum was
// merged into the canonical 4-case enum in
// `Models/Multimodal/MultiModalCore.swift`. Registration-specific
// surfaces (longform displayName / tagline / iconSystemName) live in
// the extension below so the auth flow keeps its copy unchanged.
extension TransportMode {
    /// Long-form registration-wizard display name (vs the terser
    /// `displayName` used in the Post-a-Load picker).
    var registrationDisplayName: String {
        switch self {
        case .truck:  return "Trucking"
        case .rail:   return "Rail"
        case .vessel: return "Vessel / Maritime"
        case .barge:  return "Barge / Inland Waterway"
        }
    }

    /// Marketing-grade tagline shown under each mode on the
    /// registration screen.
    var tagline: String {
        switch self {
        case .truck:  return "Highway freight & hazmat transport"
        case .rail:   return "Railroad freight & intermodal operations"
        case .vessel: return "Ocean & inland waterway freight"
        case .barge:  return "Inland barge transport & inland tow"
        }
    }

    /// Backwards-compat alias for the older `iconSystemName` property.
    /// New call sites should prefer `sfSymbol` defined on the
    /// canonical enum.
    var iconSystemName: String { sfSymbol }

    /// Backwards-compat alias matching the uppercase raw value the
    /// registration backend expects (TRUCK / RAIL / VESSEL / BARGE).
    /// Server-side `users.transportModes` JSON column stores uppercase
    /// canonical strings; this property emits in that form. New
    /// load-side serializations use the lowercase `rawValue`.
    var apiUppercase: String { rawValue.uppercased() }
}

// MARK: - AuthUser

struct AuthUser: Codable, Hashable, Identifiable {
    let id: String
    let email: String
    let role: String
    let name: String?
    let companyId: String?

    /// RIOS Axis O — the integration profile-adaptation envelope folded by the
    /// server's `auth.me` round-trip. Mirrors the web client exactly: the same
    /// `profileAdaptation` the web consumes is decoded here so iOS re-composes
    /// menus / capability gates / role surfaces from one source of truth.
    /// Optional so the app decodes cleanly against servers that predate the fold.
    let profileAdaptation: ProfileAdaptation?

    /// Parsed role, defaulting to .shipper if backend returns something unexpected.
    var roleEnum: EusoRole {
        EusoRole(rawValue: role) ?? .shipper
    }

    /// "Marcus"
    var firstName: String {
        (name ?? "").split(separator: " ").first.map(String.init) ?? (name ?? "")
    }

    // MARK: RIOS Axis O — capability / surface gates (mirror the web feature gates)

    /// True when a connected integration grants this capability flag.
    func hasCapability(_ capability: String) -> Bool {
        profileAdaptation?.capabilities.contains(capability) ?? false
    }

    /// True when a connected integration grants scoped access to a role surface
    /// (e.g. "FUEL_BUYER", "BULK_LIQUID_OPERATOR").
    func hasSurface(_ surface: String) -> Bool {
        profileAdaptation?.roleSurfaces.contains(surface) ?? false
    }

    /// True when a connected integration unlocked this dashboard widget.
    func hasDashboardWidget(_ id: String) -> Bool {
        profileAdaptation?.dashboardWidgets.contains(id) ?? false
    }

    /// Extra menu items injected by connected integrations (empty when none).
    var integrationMenuItems: [ProfileAdaptation.MenuItem] {
        profileAdaptation?.menuItems ?? []
    }
}

// MARK: - ProfileAdaptation (RIOS Axis O)

/// What the user's product becomes once integrations are connected. Decoded
/// verbatim from `auth.me`'s `profileAdaptation` field — identical shape to the
/// web client's consumer so both platforms gate features the same way.
struct ProfileAdaptation: Codable, Hashable {
    struct MenuItem: Codable, Hashable, Identifiable {
        /// Stable identity for SwiftUI ForEach — path is unique per injected item.
        var id: String { path }
        let label: String
        let path: String
        let icon: String
    }

    let menuItems: [MenuItem]
    let dashboardWidgets: [String]
    let capabilities: [String]
    let profileFields: [String]
    let roleSurfaces: [String]

    private enum CodingKeys: String, CodingKey {
        case menuItems, dashboardWidgets, capabilities, profileFields, roleSurfaces
    }

    /// Tolerant decode: any field the server omits decodes to an empty array,
    /// so a partial envelope never fails the whole `auth.me` decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menuItems = (try? c.decode([MenuItem].self, forKey: .menuItems)) ?? []
        dashboardWidgets = (try? c.decode([String].self, forKey: .dashboardWidgets)) ?? []
        capabilities = (try? c.decode([String].self, forKey: .capabilities)) ?? []
        profileFields = (try? c.decode([String].self, forKey: .profileFields)) ?? []
        roleSurfaces = (try? c.decode([String].self, forKey: .roleSurfaces)) ?? []
    }

    /// Memberwise init retained for previews / tests / synthesized encoding.
    init(menuItems: [MenuItem] = [], dashboardWidgets: [String] = [],
         capabilities: [String] = [], profileFields: [String] = [],
         roleSurfaces: [String] = []) {
        self.menuItems = menuItems
        self.dashboardWidgets = dashboardWidgets
        self.capabilities = capabilities
        self.profileFields = profileFields
        self.roleSurfaces = roleSurfaces
    }
}

// MARK: - Login

/// Response from `auth.login`.  On success: `{success:true, user:AuthUser}`.
/// On 2FA required: `{success:false, requiresTwoFactor:true, method:"totp|sms", message:String}`.
struct LoginResponse: Codable {
    let success: Bool
    let user: AuthUser?
    let requiresTwoFactor: Bool?
    let method: String?
    let message: String?
}

// MARK: - Forgot / Reset

struct GenericMessageResponse: Codable {
    let success: Bool
    let message: String?
}

// MARK: - Registration (shared envelope across all register* mutations)

struct RegistrationResponse: Codable {
    let success: Bool?
    let userId: Int?
    let companyId: Int?
    let driverId: Int?
    let message: String?
    let emailSent: Bool?
}
