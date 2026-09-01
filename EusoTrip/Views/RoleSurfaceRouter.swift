//
//  RoleSurfaceRouter.swift
//  EusoTrip — production role-aware top-level router.
//
//  Replaces the previous Driver-only hardcoded `driverSurface` branch in
//  ContentView. After sign-in, `session.user.roleEnum` decides which
//  surface renders. Each role lands on its own real Home screen with
//  RBAC enforcement (a Shipper user can only ever see Shipper screens,
//  a Driver user can only ever see Driver screens, etc.).
//
//  `RoleSurfaceAssignment` exhaustively binds all 25 backend roles. Twenty-two
//  roles mount native role-owned surfaces; Safety Manager, Factoring and the
//  verified Zeun Service Provider are explicit App.tsx continuations until persona-correct native roots
//  exist. Shared rail/vessel registries are fenced again by each role's exact
//  `NativeModeRoleDefinition.allowedRoutes` catalog.
//
//  Every surface installs one stable Home/work/work/Me dock around ESANG and
//  owns its navigation stack. Cross-role notifications are accepted only when
//  the target is both registered and assigned to the signed-in role.
//

import SwiftUI
import SafariServices

// MARK: - Role surface router

/// One exhaustive assignment per backend role. Keeping this separate from the
/// view switch makes the 25-role contract machine-verifiable: adding an
/// `EusoRole` cannot silently inherit a family default or a different role's
/// dock. The raw value is deliberately unique even where two roles share a
/// proven native container (ADMIN / SUPER_ADMIN).
enum RoleSurfaceAssignment: String, CaseIterable {
    case driver = "DriverSurfaceHost"
    case shipper = "ShipperSurface"
    case catalyst = "CarrierSurface"
    case broker = "BrokerSurface"
    case dispatch = "DispatchSurface"
    case escort = "EscortSurface"
    case terminal = "TerminalSurface"
    case compliance = "ComplianceSurface"
    case safety = "WebContinuationSurface.SAFETY_MANAGER"
    case admin = "AdminSurface.ADMIN"
    case superAdmin = "AdminSurface.SUPER_ADMIN"
    case factoring = "WebContinuationSurface.FACTORING"
    case railShipper = "NativeModeRoleSurface.RAIL_SHIPPER"
    case railCatalyst = "NativeModeRoleSurface.RAIL_CATALYST"
    case railDispatch = "NativeModeRoleSurface.RAIL_DISPATCHER"
    case railEngineer = "RailEngineerSurface"
    case railConductor = "NativeModeRoleSurface.RAIL_CONDUCTOR"
    case railBroker = "NativeModeRoleSurface.RAIL_BROKER"
    case vesselShipper = "VesselShipperSurface"
    case vesselOperator = "VesselOperatorSurface"
    case portMaster = "NativeModeRoleSurface.PORT_MASTER"
    case shipCaptain = "NativeModeRoleSurface.SHIP_CAPTAIN"
    case vesselBroker = "NativeModeRoleSurface.VESSEL_BROKER"
    case customsBroker = "NativeModeRoleSurface.CUSTOMS_BROKER"
    case serviceProvider = "WebContinuationSurface.SERVICE_PROVIDER"

    static func forRole(_ role: EusoRole) -> RoleSurfaceAssignment {
        switch role {
        case .driver: return .driver
        case .shipper: return .shipper
        case .catalyst: return .catalyst
        case .broker: return .broker
        case .dispatch: return .dispatch
        case .escort: return .escort
        case .terminal: return .terminal
        case .compliance: return .compliance
        case .safety: return .safety
        case .admin: return .admin
        case .superAdmin: return .superAdmin
        case .factoring: return .factoring
        case .railShipper: return .railShipper
        case .railCatalyst: return .railCatalyst
        case .railDispatch: return .railDispatch
        case .railEngineer: return .railEngineer
        case .railConductor: return .railConductor
        case .railBroker: return .railBroker
        case .vesselShipper: return .vesselShipper
        case .vesselOperator: return .vesselOperator
        case .portMaster: return .portMaster
        case .shipCaptain: return .shipCaptain
        case .vesselBroker: return .vesselBroker
        case .customsBroker: return .customsBroker
        case .serviceProvider: return .serviceProvider
        }
    }

    var isContinuation: Bool {
        switch self {
        case .safety, .factoring, .serviceProvider:
            return true
        case .driver, .shipper, .catalyst, .broker, .dispatch, .escort,
             .terminal, .compliance, .admin, .superAdmin, .railShipper,
             .railCatalyst, .railDispatch, .railEngineer, .railConductor,
             .railBroker, .vesselShipper, .vesselOperator, .portMaster,
             .shipCaptain, .vesselBroker, .customsBroker:
            return false
        }
    }
}

struct RoleSurfaceRouter: View {
    @EnvironmentObject var session: EusoTripSession
    let palette: Theme.Palette

    var body: some View {
        // `session.user` is non-nil whenever `phase == .signedIn` (set
        // together in `EusoTripSession.signIn` / `bootstrap` /
        // `signInDemo`). AppRoot guards on phase before mounting
        // ContentView, but we still resolve defensively here so a
        // race between sign-out and a stale render doesn't fall back
        // to Driver-by-accident.
        let role = session.user?.roleEnum ?? .driver

        switch RoleSurfaceAssignment.forRole(role) {
        case .driver:
            // The Driver surface lives inside ContentView because it
            // owns the `nav: DriverNavController`, `trip:
            // DriverTripController`, sheet presentations, and orb
            // state machine. The router is the entry point; the
            // actual surface is constructed by ContentView when the
            // role resolves to .driver.
            DriverSurfaceHost(palette: palette)

        case .shipper:
            ShipperSurface(palette: palette)

        case .catalyst:
            CarrierSurface(palette: palette)

        case .broker:
            BrokerSurface(palette: palette)

        case .dispatch:
            // Dispatch has 13 native iOS files (Dpch700-Dpch712) —
            // surface landed natively 2026-05-01 with the design-
            // token normalization + unshelf of 702-712.
            DispatchSurface(palette: palette)

        case .escort:
            EscortSurface(palette: palette)

        case .terminal:
            TerminalSurface(palette: palette)

        case .compliance:
            // Compliance has 3 native iOS files (900-902) — surfaces
            // landed natively 2026-05-01 with the resurrection of the
            // previously-shelved 901/902 + addition of `.compliance`
            // to the chrome registry.
            ComplianceSurface(palette: palette)
        case .safety:
            WebContinuationSurface(role: role, palette: palette)

        case .admin:
            AdminSurface(palette: palette)

        case .superAdmin:
            AdminSurface(palette: palette)

        case .factoring:
            WebContinuationSurface(role: role, palette: palette)

        case .railShipper:
            NativeModeRoleSurface(definition: .railShipper, palette: palette)

        case .railCatalyst:
            NativeModeRoleSurface(definition: .railCatalyst, palette: palette)

        case .railDispatch:
            NativeModeRoleSurface(definition: .railDispatch, palette: palette)

        case .railEngineer:
            RailEngineerSurface(palette: palette)

        case .railConductor:
            NativeModeRoleSurface(definition: .railConductor, palette: palette)

        case .railBroker:
            NativeModeRoleSurface(definition: .railBroker, palette: palette)

        case .vesselShipper:
            VesselShipperSurface(palette: palette)

        case .vesselOperator:
            VesselOperatorSurface(palette: palette)

        case .portMaster:
            NativeModeRoleSurface(definition: .portMaster, palette: palette)

        case .shipCaptain:
            NativeModeRoleSurface(definition: .shipCaptain, palette: palette)

        case .vesselBroker:
            NativeModeRoleSurface(definition: .vesselBroker, palette: palette)

        case .customsBroker:
            NativeModeRoleSurface(definition: .customsBroker, palette: palette)

        case .serviceProvider:
            WebContinuationSurface(role: role, palette: palette)
        }
    }
}

// MARK: - Canonical role docks

/// Typed four-destination contracts installed by every native role surface.
/// `Shell` owns the rendering, so child screens and reused cross-mode screens
/// cannot replace a role's primary navigation or inherit another role's dock.
enum RoleDockCatalog {
    static func driver(active: String, select: @escaping (String) -> Void, openESang: @escaping () -> Void) -> RoleDockContract {
        .four(
            home: .init(destinationId: "home", label: "Home", systemImage: "house"),
            workOne: .init(destinationId: "trips", label: "Trips", systemImage: "truck.box"),
            workTwo: .init(destinationId: "loads", label: "Loads", systemImage: "shippingbox.fill"),
            me: .init(destinationId: "me", label: "Me", systemImage: "person"),
            active: active, select: select, openESang: openESang
        )
    }

    static func shipper(active: String, select: @escaping (String) -> Void, openESang: @escaping () -> Void) -> RoleDockContract {
        .four(
            home: .init(destinationId: "200", label: "Home", systemImage: "house"),
            workOne: .init(destinationId: "204", label: "Create Load", systemImage: "plus.rectangle.on.rectangle"),
            workTwo: .init(destinationId: "201", label: "Loads", systemImage: "shippingbox.fill"),
            me: .init(destinationId: "320", label: "Me", systemImage: "person"),
            active: active, select: select, openESang: openESang
        )
    }

    static func carrier(active: String, select: @escaping (String) -> Void, openESang: @escaping () -> Void) -> RoleDockContract {
        .four(
            home: .init(destinationId: "300", label: "Home", systemImage: "house"),
            workOne: .init(destinationId: "301", label: "Loads", systemImage: "shippingbox.fill"),
            workTwo: .init(destinationId: "304", label: "Drivers", systemImage: "person.3.fill"),
            me: .init(destinationId: "350", label: "Me", systemImage: "person"),
            active: active, select: select, openESang: openESang
        )
    }

    static func catalyst(active: String, select: @escaping (String) -> Void, openESang: @escaping () -> Void) -> RoleDockContract {
        .four(
            home: .init(destinationId: "500", label: "Home", systemImage: "house"),
            workOne: .init(destinationId: "501", label: "Matches", systemImage: "point.3.connected.trianglepath.dotted"),
            workTwo: .init(destinationId: "304", label: "Fleet", systemImage: "truck.box.fill"),
            me: .init(destinationId: "350", label: "Me", systemImage: "person"),
            active: active, select: select, openESang: openESang
        )
    }

    static func broker(active: String, select: @escaping (String) -> Void, openESang: @escaping () -> Void) -> RoleDockContract {
        .four(
            home: .init(destinationId: "400", label: "Home", systemImage: "house"),
            workOne: .init(destinationId: "401", label: "Tenders", systemImage: "doc.text.fill"),
            workTwo: .init(destinationId: "402b", label: "Carriers", systemImage: "truck.box.fill"),
            me: .init(destinationId: "404B", label: "Me", systemImage: "person"),
            active: active, select: select, openESang: openESang
        )
    }

    static func escort(active: String, select: @escaping (String) -> Void, openESang: @escaping () -> Void) -> RoleDockContract {
        .four(
            home: .init(destinationId: "600", label: "Home", systemImage: "house"),
            workOne: .init(destinationId: "601", label: "Assignments", systemImage: "shield.fill"),
            workTwo: .init(destinationId: "602", label: "Corridor", systemImage: "map.fill"),
            me: .init(destinationId: "620", label: "Me", systemImage: "person"),
            active: active, select: select, openESang: openESang
        )
    }

    static func terminal(active: String, select: @escaping (String) -> Void, openESang: @escaping () -> Void) -> RoleDockContract {
        .four(
            home: .init(destinationId: "700", label: "Home", systemImage: "house"),
            workOne: .init(destinationId: "701", label: "Movements", systemImage: "arrow.left.arrow.right"),
            workTwo: .init(destinationId: "702", label: "Yard", systemImage: "map.fill"),
            me: .init(destinationId: "703", label: "Me", systemImage: "person"),
            active: active, select: select, openESang: openESang
        )
    }

    static func admin(active: String, select: @escaping (String) -> Void, openESang: @escaping () -> Void) -> RoleDockContract {
        .four(
            home: .init(destinationId: "800", label: "Home", systemImage: "house"),
            workOne: .init(destinationId: "801", label: "Tickets", systemImage: "ticket.fill"),
            workTwo: .init(destinationId: "802", label: "Tenants", systemImage: "building.2.fill"),
            me: .init(destinationId: "804", label: "Me", systemImage: "person"),
            active: active, select: select, openESang: openESang
        )
    }

    static func compliance(active: String, select: @escaping (String) -> Void, openESang: @escaping () -> Void) -> RoleDockContract {
        .four(
            home: .init(destinationId: "900", label: "Home", systemImage: "house"),
            workOne: .init(destinationId: "901", label: "Drivers", systemImage: "person.3.fill"),
            workTwo: .init(destinationId: "902", label: "Audits", systemImage: "checkmark.shield.fill"),
            me: .init(destinationId: "903", label: "Me", systemImage: "person"),
            active: active, select: select, openESang: openESang
        )
    }

    static func dispatch(active: String, select: @escaping (String) -> Void, openESang: @escaping () -> Void) -> RoleDockContract {
        .four(
            home: .init(destinationId: "Disp400", label: "Home", systemImage: "house"),
            workOne: .init(destinationId: "Disp401", label: "Board", systemImage: "rectangle.split.3x1.fill"),
            workTwo: .init(destinationId: "Dpch721", label: "Comms", systemImage: "bubble.left.and.bubble.right.fill"),
            me: .init(destinationId: "Dpch713", label: "Me", systemImage: "person"),
            active: active, select: select, openESang: openESang
        )
    }

    static func railEngineer(active: String, select: @escaping (String) -> Void, openESang: @escaping () -> Void) -> RoleDockContract {
        .four(
            home: .init(destinationId: "Rail550", label: "Home", systemImage: "house"),
            workOne: .init(destinationId: "Rail551", label: "Shipments", systemImage: "train.side.front.car"),
            workTwo: .init(destinationId: "Rail552", label: "Compliance", systemImage: "checkmark.shield.fill"),
            me: .init(destinationId: "Rail556", label: "Me", systemImage: "person"),
            active: active, select: select, openESang: openESang
        )
    }

    static func vesselOperator(active: String, select: @escaping (String) -> Void, openESang: @escaping () -> Void) -> RoleDockContract {
        .four(
            home: .init(destinationId: "Vesl650", label: "Home", systemImage: "house"),
            workOne: .init(destinationId: "Vesl651", label: "Shipments", systemImage: "shippingbox.fill"),
            workTwo: .init(destinationId: "Vesl652", label: "Compliance", systemImage: "checkmark.shield.fill"),
            me: .init(destinationId: "Vesl656", label: "Me", systemImage: "person"),
            active: active, select: select, openESang: openESang
        )
    }

    static func vesselShipper(active: String, select: @escaping (String) -> Void, openESang: @escaping () -> Void) -> RoleDockContract {
        .four(
            home: .init(destinationId: "Vesl001", label: "Home", systemImage: "house"),
            workOne: .init(destinationId: "Vesl011", label: "Bookings", systemImage: "doc.text.fill"),
            workTwo: .init(destinationId: "Vesl012", label: "Track", systemImage: "location.fill"),
            me: .init(destinationId: "320", label: "Me", systemImage: "person"),
            active: active, select: select, openESang: openESang
        )
    }
}

// MARK: - Shared native rail / vessel role contracts

/// A role-specific shell over an existing native mode registry. These
/// definitions intentionally use only context-free roots whose initial load is
/// backed by a real server query. Record-detail screens that need an id are not
/// promoted to a dock destination with a sentinel id.
struct NativeModeRoleDefinition {
    enum Mode {
        case rail
        case vessel
    }

    let role: EusoRole
    let mode: Mode
    let registryRole: ProductionScreen.Role
    let home: RoleDockItem
    let workOne: RoleDockItem
    let workTwo: RoleDockItem
    let me: RoleDockItem
    let detailRoutes: Set<String>
    let screensWithOwnBack: Set<String>

    var dockItems: [RoleDockItem] { [home, workOne, workTwo, me] }
    var tabRoots: Set<String> { Set(dockItems.map(\.destinationId)) }
    var allowedRoutes: Set<String> {
        tabRoots.union(detailRoutes)
    }

    static let railShipper = Self(
        role: .railShipper,
        mode: .rail,
        registryRole: .railEngineer,
        home: .init(destinationId: "RoleRailShipperHome", label: "Home", systemImage: "house"),
        workOne: .init(destinationId: "Rail551", label: "Shipments", systemImage: "shippingbox.fill"),
        workTwo: .init(destinationId: "Rail639", label: "Network", systemImage: "point.3.connected.trianglepath.dotted"),
        me: .init(destinationId: "RoleRailShipperMe", label: "Me", systemImage: "person"),
        detailRoutes: [],
        screensWithOwnBack: []
    )

    static let railCatalyst = Self(
        role: .railCatalyst,
        mode: .rail,
        registryRole: .railEngineer,
        home: .init(destinationId: "RoleRailCatalystHome", label: "Home", systemImage: "house"),
        workOne: .init(destinationId: "Rail559", label: "Yards", systemImage: "square.grid.3x3.fill"),
        workTwo: .init(destinationId: "Rail552", label: "Compliance", systemImage: "checkmark.shield.fill"),
        me: .init(destinationId: "RoleRailCatalystMe", label: "Me", systemImage: "person"),
        detailRoutes: [],
        screensWithOwnBack: []
    )

    static let railDispatch = Self(
        role: .railDispatch,
        mode: .rail,
        registryRole: .railEngineer,
        home: .init(destinationId: "RoleRailDispatchHome", label: "Home", systemImage: "house"),
        workOne: .init(destinationId: "Rail555", label: "Consists", systemImage: "train.side.front.car"),
        workTwo: .init(destinationId: "Rail559", label: "Yards", systemImage: "square.grid.3x3.fill"),
        me: .init(destinationId: "RoleRailDispatchMe", label: "Me", systemImage: "person"),
        detailRoutes: [],
        screensWithOwnBack: []
    )

    static let railConductor = Self(
        role: .railConductor,
        mode: .rail,
        registryRole: .railEngineer,
        home: .init(destinationId: "RoleRailConductorHome", label: "Home", systemImage: "house"),
        workOne: .init(destinationId: "Rail554", label: "Duty", systemImage: "clock.fill"),
        workTwo: .init(destinationId: "Rail595", label: "Credentials", systemImage: "person.text.rectangle.fill"),
        me: .init(destinationId: "RoleRailConductorMe", label: "Me", systemImage: "person"),
        detailRoutes: [],
        screensWithOwnBack: []
    )

    static let railBroker = Self(
        role: .railBroker,
        mode: .rail,
        registryRole: .railEngineer,
        home: .init(destinationId: "RoleRailBrokerHome", label: "Home", systemImage: "house"),
        workOne: .init(destinationId: "Rail551", label: "Shipments", systemImage: "shippingbox.fill"),
        workTwo: .init(destinationId: "Rail639", label: "Network", systemImage: "point.3.connected.trianglepath.dotted"),
        me: .init(destinationId: "RoleRailBrokerMe", label: "Me", systemImage: "person"),
        detailRoutes: [],
        screensWithOwnBack: []
    )

    static let portMaster = Self(
        role: .portMaster,
        mode: .vessel,
        registryRole: .vesselOperator,
        home: .init(destinationId: "RolePortMasterHome", label: "Home", systemImage: "house"),
        workOne: .init(destinationId: "Vesl697", label: "Port Ops", systemImage: "ferry.fill"),
        workTwo: .init(destinationId: "Vesl686", label: "Directory", systemImage: "building.2.fill"),
        me: .init(destinationId: "RolePortMasterMe", label: "Me", systemImage: "person"),
        detailRoutes: ["Vesl661", "Vesl822"],
        screensWithOwnBack: []
    )

    static let shipCaptain = Self(
        role: .shipCaptain,
        mode: .vessel,
        registryRole: .vesselOperator,
        home: .init(destinationId: "RoleShipCaptainHome", label: "Home", systemImage: "house"),
        workOne: .init(destinationId: "Vesl660", label: "Position", systemImage: "location.fill"),
        workTwo: .init(destinationId: "Vesl711", label: "Crew", systemImage: "person.3.fill"),
        me: .init(destinationId: "RoleShipCaptainMe", label: "Me", systemImage: "person"),
        detailRoutes: ["Vesl654", "Vesl822"],
        screensWithOwnBack: ["Vesl654"]
    )

    static let vesselBroker = Self(
        role: .vesselBroker,
        mode: .vessel,
        registryRole: .vesselOperator,
        home: .init(destinationId: "RoleVesselBrokerHome", label: "Home", systemImage: "house"),
        workOne: .init(destinationId: "Vesl651", label: "Bookings", systemImage: "doc.text.fill"),
        workTwo: .init(destinationId: "Vesl686", label: "Ports", systemImage: "ferry.fill"),
        me: .init(destinationId: "RoleVesselBrokerMe", label: "Me", systemImage: "person"),
        detailRoutes: [],
        screensWithOwnBack: []
    )

    static let customsBroker = Self(
        role: .customsBroker,
        mode: .vessel,
        registryRole: .vesselOperator,
        home: .init(destinationId: "RoleCustomsBrokerHome", label: "Home", systemImage: "house"),
        workOne: .init(destinationId: "Vesl789", label: "Entries", systemImage: "doc.badge.clock"),
        workTwo: .init(destinationId: "Vesl814", label: "Filing", systemImage: "doc.badge.plus"),
        me: .init(destinationId: "RoleCustomsBrokerMe", label: "Me", systemImage: "person"),
        detailRoutes: [],
        screensWithOwnBack: []
    )
}

extension RoleDockCatalog {
    static func nativeModeRole(
        definition: NativeModeRoleDefinition,
        active: String,
        select: @escaping (String) -> Void,
        openESang: @escaping () -> Void
    ) -> RoleDockContract {
        .four(
            home: definition.home,
            workOne: definition.workOne,
            workTwo: definition.workTwo,
            me: definition.me,
            active: active,
            select: select,
            openESang: openESang
        )
    }
}

/// App.tsx-verified web destinations for roles that still have an
/// explicit continuation instead of a production-safe native surface.
struct WebRoleDockDefinition {
    let home: RoleDockItem
    let workOne: RoleDockItem
    let workTwo: RoleDockItem
    let me: RoleDockItem

    var items: [RoleDockItem] { [home, workOne, workTwo, me] }

    static func forRole(_ role: EusoRole) -> WebRoleDockDefinition {
        func item(_ path: String, _ label: String, _ icon: String) -> RoleDockItem {
            RoleDockItem(destinationId: path, label: label, systemImage: icon)
        }

        switch role {
        case .safety:
            return .init(
                home: item("/safety", "Home", "house"),
                workOne: item("/safety/incidents", "Incidents", "exclamationmark.triangle.fill"),
                workTwo: item("/safety/scores", "Scores", "checkmark.shield.fill"),
                me: item("/settings", "Me", "person")
            )
        case .factoring:
            return .init(
                home: item("/factoring", "Home", "house"),
                workOne: item("/factoring/invoices", "Invoices", "doc.text.fill"),
                workTwo: item("/factoring/funding", "Funding", "banknote.fill"),
                me: item("/factoring/settings", "Me", "person")
            )
        case .serviceProvider:
            return .init(
                home: item("/zeun/providers", "Home", "house"),
                workOne: item("/zeun/provider/work-orders", "Work", "wrench.and.screwdriver.fill"),
                workTwo: item("/zeun/provider/team", "Team", "person.3.fill"),
                me: item("/settings", "Me", "person")
            )
        case .driver, .shipper, .catalyst, .broker, .dispatch, .escort,
             .terminal, .compliance, .admin, .superAdmin, .railShipper,
             .railCatalyst, .railDispatch, .railEngineer, .railConductor,
             .railBroker, .vesselShipper, .vesselOperator, .portMaster,
             .shipCaptain, .vesselBroker, .customsBroker:
            preconditionFailure("\(role.rawValue) is assigned to a native role surface")
        }
    }

    /// Allow ESANG to open role-owned web routes without granting a role a
    /// cross-domain or cross-role navigation primitive. Final authorization is
    /// still enforced by App.tsx and the server; this is the client-side fence.
    func allows(path rawPath: String, for role: EusoRole) -> Bool {
        let path = Self.normalizedPath(rawPath)
        if items.contains(where: { $0.destinationId == path }) { return true }
        if ["/", "/profile", "/settings", "/messages", "/documents", "/esang"].contains(path) {
            return true
        }

        switch role {
        case .safety:
            return path.hasPrefix("/safety") || path.hasPrefix("/hazmat")
                || path == "/incidents" || path == "/training"
                || path == "/driver-health" || path == "/vehicle-safety"
        case .factoring:
            return path.hasPrefix("/factoring")
        case .serviceProvider:
            return path.hasPrefix("/zeun/providers") || path.hasPrefix("/zeun/provider")
        case .driver, .shipper, .catalyst, .broker, .dispatch, .escort,
             .terminal, .compliance, .admin, .superAdmin, .railShipper,
             .railCatalyst, .railDispatch, .railEngineer, .railConductor,
             .railBroker, .vesselShipper, .vesselOperator, .portMaster,
             .shipCaptain, .vesselBroker, .customsBroker:
            return false
        }
    }

    static func normalizedPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/" }
        if let url = URL(string: trimmed), url.scheme != nil {
            return normalizedPath(url.path)
        }
        var path = trimmed
        if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }
        if let fragment = path.firstIndex(of: "#") { path = String(path[..<fragment]) }
        if !path.hasPrefix("/") { path = "/" + path }
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path.lowercased()
    }
}

extension RoleDockCatalog {
    static func webContinuation(
        role: EusoRole,
        active: String,
        select: @escaping (String) -> Void,
        openESang: @escaping () -> Void
    ) -> RoleDockContract {
        let definition = WebRoleDockDefinition.forRole(role)
        return .four(
            home: definition.home,
            workOne: definition.workOne,
            workTwo: definition.workTwo,
            me: definition.me,
            active: active,
            select: select,
            openESang: openESang
        )
    }
}

// MARK: - Driver surface host

/// Defensive type used only to make `RoleSurfaceRouter`'s switch
/// exhaustive over `EusoRole`. **Never rendered in production** —
/// `ContentView` checks `session.user?.roleEnum == .driver` before
/// reaching the router and dispatches its own inline `driverSurface`
/// (which owns the Driver-specific `@StateObject`s, sheet
/// presenters, and orb state machine). If this view ever paints,
/// it indicates a routing bug; we surface a real diagnostic instead
/// of a silent blank.
struct DriverSurfaceHost: View {
    let palette: Theme.Palette
    var body: some View {
        Shell(theme: palette) {
            VStack(spacing: Space.s3) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(palette.textPrimary)
                Text("Driver routing fault")
                    .font(EType.h2)
                    .foregroundStyle(palette.textPrimary)
                Text("ContentView should have dispatched the Driver surface directly. Reaching `RoleSurfaceRouter` for `.driver` is a build-time wiring bug. File a defect.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.s5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } nav: { EmptyView() }
    }
}

// MARK: - Shipper routed-record resolvers

/// Normalizes opaque record identifiers arriving through NotificationCenter.
/// Route payloads are normally strings, but push/deep-link bridges may carry
/// integer primary keys. All actionable routed records reject empty and
/// non-positive identifiers before a destination screen is constructed.
enum ShipperRoutedRecordIdResolver {
    static func string(from raw: Any?) -> String? {
        let value: String
        switch raw {
        case let raw as String: value = raw
        case let raw as Int: value = String(raw)
        case let raw as Int64: value = String(raw)
        case let raw as UInt: value = String(raw)
        default: return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func positiveNumeric(_ raw: Any?) -> String? {
        guard let id = string(from: raw), let numericId = Int(id), numericId > 0 else {
            return nil
        }
        return id
    }

    /// RFP rows are emitted as `RFP-<positive id>` by rfpManager, while the
    /// same procedures also accept the underlying positive numeric string.
    static func rfp(_ raw: Any?) -> String? {
        guard let id = string(from: raw) else { return nil }
        if let numericId = Int(id), numericId > 0 { return id }

        let uppercased = id.uppercased()
        guard uppercased.hasPrefix("RFP-"),
              let numericId = Int(uppercased.dropFirst("RFP-".count)),
              numericId > 0 else {
            return nil
        }
        return id
    }
}

/// Honest terminal state for a routed detail that arrived without its record
/// identifier. The actionable body is never constructed in this branch.
struct ShipperRecordContextUnavailableScreen: View {
    let theme: Theme.Palette
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        Shell(theme: theme) {
            VStack {
                Spacer(minLength: Space.s6)
                EusoEmptyState(systemImage: systemImage, title: title, subtitle: subtitle)
                    .padding(.horizontal, Space.s4)
                Spacer(minLength: 96)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } nav: {
            shipperLifecycleNav()
        }
    }
}

// MARK: - Shipper load-id resolver (Emergency Wave I1)

/// The ONE normalization gate every shipper load-context nav entry
/// passes through before it can become `activeLoadId`. Kills the
/// raw-id family (282/316/327/333 posted `load_NNN`-form ids straight
/// out of server handles; `loads.getById` resolves "load_1077" via a
/// loadNumber lookup that never matches, returns `null` AS SUCCESS,
/// and 205 skeleton'd forever) and the `"0"` sentinel (server returns
/// null for id<=0 — same forever-skeleton).
///
///   • strips the `load_` prefix (case-insensitive)
///   • rejects empty / whitespace ids
///   • rejects non-positive numeric ids (the registry sentinel)
///   • rejects reserved action keywords ("search", "new", …) so a
///     `/shipper/loads/<keyword>` path can never become a bogus load
///     id → 205 → server null → forever-skeleton (founder "Load not
///     found" class; the 225 call-site was patched 2026-06-19 but the
///     resolver trap stayed open for every other caller)
///   • rejects ids that are NEITHER positive-numeric NOR a recognized
///     loadNumber form (`^LD-` / `^load_`) — a non-numeric, non-
///     loadNumber keyword has no chance of resolving server-side
///   • passes loadNumber forms ("LD-…") through untouched — the
///     server's resolveLoadId handles those via loadNumber lookup
enum ShipperLoadIdResolver {
    /// Reserved non-id action segments that can appear in a
    /// `/shipper/loads/<seg>` path. None of these is ever a load id —
    /// they are list-level actions (search/new/filter/…) whose
    /// destination is NOT a load-detail mount. Treated as "no id" so
    /// the caller falls back to the loads list (201) instead of
    /// mounting 205 on garbage.
    static let reservedSegments: Set<String> = [
        "search", "new", "filter", "map", "create", "import", "bulk",
    ]

    static func normalize(_ raw: Any?) -> String? {
        guard var id = ShipperRoutedRecordIdResolver.string(from: raw) else { return nil }
        // Reject reserved action keywords up front (case-insensitive),
        // before any prefix-stripping, so `/loads/search` etc. never
        // survive normalization.
        if reservedSegments.contains(id.lowercased()) { return nil }
        let hadLoadPrefix = id.lowercased().hasPrefix("load_")
        if hadLoadPrefix {
            id = String(id.dropFirst("load_".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !id.isEmpty else { return nil }
        // Numeric id: accept iff positive (the registry sentinel is 0).
        if let n = Int(id) { return n > 0 ? id : nil }
        // Non-numeric: only a recognized loadNumber form can resolve
        // server-side. Accept `LD-…` (canonical loadNumber) and the
        // `load_…`-prefixed form we just unwrapped. Anything else is a
        // stray keyword/garbage segment → reject so 205 never mounts.
        if hadLoadPrefix { return id }
        if id.uppercased().hasPrefix("LD-") { return id }
        return nil
    }
}

// MARK: - Shipper surface

/// Top-level Shipper container. Holds the currently-rendered shipper
/// screen ID, listens to `.eusoShipperNavSwap` for slot taps, and looks
/// up the matching screen out of `ScreenRegistry`. RBAC: only screens
/// where `role == .shipper` are accepted; an out-of-role notification
/// payload (e.g., a stale Driver screen ID) routes back to 200 home.
struct ShipperSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    /// Navigation stack — pushes on `eusoShipperNavSwap`, pops on
    /// `eusoShipperNavBack`. The four canonical bottom-nav tabs (200
    /// home / 201 loads / 204 create-load / 320 me-home) reset the
    /// stack to a single entry so tab-switching never strands the
    /// user inside a back-trail of an unrelated tab. The previous
    /// implementation used a single `currentScreenId` with no
    /// history, so leaf screens drilled from Me had no path back to
    /// the parent hub other than re-tapping the Me tab — which dumped
    /// the user on Me Home (320) instead of returning to the hub
    /// child they were viewing. Reported by founder 2026-05-04
    /// ("none of the menu items in 'Me' for shipper have a back
    /// button so you get stuck on the screen").
    @State private var screenStack: [String] = ["200"]
    @State private var showeSang: Bool = false
    @StateObject private var postLoadDraft = PostLoadDraft()
    @State private var activePostLoadDraftId: String? = nil

    /// Top of the navigation stack — the screen currently rendered.
    private var currentScreenId: String { screenStack.last ?? "200" }

    /// Bottom-nav tab roots. Pushing one of these collapses the stack
    /// to a single entry rather than appending — same semantics as
    /// UIKit's `UITabBarController` where switching tabs resets the
    /// per-tab back-stack.
    private static let tabRoots: Set<String> = ["200", "201", "204", "320"]
    /// Captured from `.eusoShipperLoadOpen` / `.eusoShipperLoadOpenMap`
    /// / `.eusoShipperSettlementOpenLoad` notification userInfo. When
    /// non-nil and the current screen is 205 / 222 / 261, we construct
    /// that screen with the real loadId instead of a registry sentinel.
    @State private var activeLoadId: String? = nil
    /// Captured from the 380 RFP inbox when it routes to 381. A bare 381
    /// navigation clears this value so an earlier RFP can never leak into it.
    @State private var activeRfpId: String? = nil
    /// Captured from 434 Partner Detail when it routes to 435. This is the
    /// partner whose real agreement rows (and agreement ids) may be signed.
    @State private var activeAgreementPartnerId: String? = nil
    /// Captured from the 424→425 handoff (`.eusoShipperNavSwap` with
    /// `userInfo["product"]`). When non-nil and the current screen is
    /// 425, we construct `PortIntelligenceScreen(product:)` so Port
    /// Intelligence opens pre-filled with the SpectraMatch grade and
    /// auto-searches. Overwritten on every 425 swap (nil when absent)
    /// so a stale grade never leaks into a later bare open.
    @State private var activePortIntelProduct: String? = nil
    /// Captured from 392→393 search handoff. The registry mounts 393
    /// with an empty sentinel for preview/recovery, so the live query
    /// must travel through the Shipper surface state just like loadId
    /// and Port Intelligence product context do.
    @State private var activeSearchQuery: String? = nil
    /// Set when an action triggers SFSafariViewController to open a
    /// web continuation (load edit, settlement approve flow, etc.).
    /// Cleared when the sheet dismisses.
    @State private var webContinuationURL: URL? = nil

    /// The single generic detail layer pushed in-stack via the shared
    /// `\.rolePushDetail` (aliased to `\.shipperPushDetail` for the four
    /// converted Shipper screens). Sheet→push, NAV remediation
    /// 2026-05-30 — generalized to `RoleDetailPush` so every surface
    /// shares one mechanism. When non-nil it renders ABOVE the current
    /// screen, slid in from the trailing edge with a `BespokeBackBar`.
    /// `.eusoShipperNavBack` clears this first (if present) before
    /// popping `screenStack`, so one back gesture pops one level whether
    /// it's a detail or a registry screen.
    @State private var pushedDetail: RoleDetailPush? = nil

    private var current: ProductionScreen {
        // Record-context destinations always receive the payload captured for
        // this route. Their screen wrappers independently fail closed when the
        // value is nil or invalid, so the registry can never create an
        // actionable surface with a sentinel id.
        if currentScreenId == "261" {
            let loadId = activeLoadId
            return ProductionScreen(id: "261",
                                    title: "Shipper · Bidding Live Feed",
                                    role: .shipper) { p in
                AnyView(BiddingLiveFeedScreen(theme: p, loadId: loadId))
            }
        }
        if currentScreenId == "381" {
            let rfpId = activeRfpId
            return ProductionScreen(id: "381",
                                    title: "Shipper · RFP Detail",
                                    role: .shipper) { p in
                AnyView(RfpDetailScreen(theme: p, rfpId: rfpId))
            }
        }
        if currentScreenId == "435" {
            let partnerId = activeAgreementPartnerId
            return ProductionScreen(id: "435",
                                    title: "Shipper · Partner Agreements",
                                    role: .shipper) { p in
                AnyView(PartnerAgreementsScreen(theme: p, partnerId: partnerId))
            }
        }
        // Detail screens with a captured loadId override the registry
        // sentinel so the screen renders the real load. This is how
        // load-row taps from 200/201/203 carry into 205.
        if let id = activeLoadId {
            switch currentScreenId {
            case "205":
                return ProductionScreen(id: "205",
                                        title: "Shipper · Load Detail",
                                        role: .shipper) { p in
                    AnyView(ShipperLoadDetailScreen(
                        theme: p,
                        loadId: id,
                        previewLoadNumber: nil,
                        previewLane: nil
                    ))
                }
            case "222":
                return ProductionScreen(id: "222",
                                        title: "Shipper · Live Tracking",
                                        role: .shipper) { p in
                    AnyView(ShipperScreenWrap(palette: p, currentSlot: .loads) {
                        ShipperLiveTracking()
                    })
                }
            default: break
            }
        }
        // 424→425 handoff (Emergency Wave I2): a captured product
        // grade overrides the registry's bare 425 so Port
        // Intelligence mounts pre-filled with the SpectraMatch best
        // match and auto-searches. Same override mechanism 205/222
        // use for activeLoadId.
        if currentScreenId == "425",
           let grade = activePortIntelProduct, !grade.isEmpty {
            return ProductionScreen(id: "425",
                                    title: "Shipper · Port Intelligence",
                                    role: .shipper) { p in
                AnyView(PortIntelligenceScreen(theme: p, product: grade))
            }
        }
        if currentScreenId == "393" {
            return ProductionScreen(id: "393",
                                    title: "Shipper · Search Results",
                                    role: .shipper) { p in
                AnyView(SearchResultsScreen(theme: p, query: activeSearchQuery ?? ""))
            }
        }
        if let postLoadScreen = postLoadWizardScreen {
            return postLoadScreen
        }
        // 200 (Home) is the canonical fallback. RBAC is also enforced
        // here — if for any reason the registry is missing 200 (build
        // mistake), we fall through to a hard error surface rather
        // than silently rendering a Driver screen.
        return ScreenRegistry.forRole(.shipper).first { $0.id == currentScreenId }
            ?? ScreenRegistry.forRole(.shipper).first { $0.id == "200" }
            ?? ScreenRegistry.forRole(.shipper).first
            ?? ProductionScreen(id: "200",
                                title: "Shipper · Home",
                                role: .shipper) { p in
                                    AnyView(ShipperHomeScreen(theme: p))
                                }
    }

    private var roleDock: RoleDockContract {
        RoleDockCatalog.shipper(
            active: screenStack.first ?? "200",
            select: { destination in
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) {
                    pushOrTab(destination)
                }
            },
            openESang: { showeSang = true }
        )
    }

    var body: some View {
        // Body kept short to dodge SwiftUI's "compiler unable to
        // type-check this expression in reasonable time" timeout —
        // the surface previously chained 26+ modifiers on a single
        // expression which exceeds the type-checker's tractable
        // budget. Heavy work (back overlay, environment injections,
        // 15 onReceive subscribers, sheets) is split into private
        // ViewModifier types below.
        current.view(palette)
            .id(currentIdentity)
            .eusoRefreshSurface("shipper:\(currentIdentity)")
            .transition(.opacity)
            .modifier(ShipperBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId
            ))
            // Generic sheet→push detail layer (slides in over the
            // current screen, BespokeBackBar on top). Sits ABOVE the
            // back overlay so the floating circle never shows under a
            // pushed detail. Injects `\.rolePushDetail` for screens
            // (aliased to `\.shipperPushDetail` for the four converted
            // Shipper screens). Shared primitive — RoleDetailLayer.
            .modifier(RoleDetailLayer(
                pushedDetail: $pushedDetail,
                palette: palette,
                onBack: {
                    NotificationCenter.default.post(
                        name: .eusoShipperNavBack, object: nil)
                }
            ))
            .modifier(ShipperEnvInjections())
            .environment(\.roleDockContract, roleDock)
            .modifier(ShipperNotificationListeners(
                screenStack: $screenStack,
                activeLoadId: $activeLoadId,
                activeRfpId: $activeRfpId,
                activeAgreementPartnerId: $activeAgreementPartnerId,
                activePortIntelProduct: $activePortIntelProduct,
                activeSearchQuery: $activeSearchQuery,
                activePostLoadDraftId: $activePostLoadDraftId,
                showeSang: $showeSang,
                webContinuationURL: $webContinuationURL,
                pushedDetail: $pushedDetail,
                pushOrTab: pushOrTab,
                popOne: popOne,
                resetPostLoadDraft: { postLoadDraft.reset() },
                applyIndustryWorkflow: { postLoadDraft.applyIndustryWorkflow($0) },
                handleMeAction: handleShipperMeAction
            ))
            .sheet(item: Binding<ShipperWebContinuationItem?>(
                get: { webContinuationURL.map(ShipperWebContinuationItem.init) },
                set: { webContinuationURL = $0?.url }
            )) { ident in
                SafariContinuationView(url: ident.url)
                    .ignoresSafeArea()
                    .eusoRefreshSurface("modal:web-continuation:shipper")
            }
            // ASC AOd5xzXVfU6CF6hyijTDwgk (build 712): present as a full-
            // screen cover, not a page sheet. The page-sheet peek band let
            // the presenting load screen's scheduleRow labels render behind
            // the status bar (overlapping text in the upper corners). The
            // coach sheet ships its own close "xmark", so nothing is lost
            // by dropping the drag-to-dismiss grabber.
            .fullScreenCover(isPresented: $showeSang) {
                ShippereSangCoachSheet()
                    .environment(\.palette, palette)
                    .environmentObject(session)
                    // Wire ESANG autopilot actions into the Shipper push-
                    // nav surface. Without this the Shipper coach sheet
                    // parsed nothing and every spoken/typed command was a
                    // no-op (E1/E2). The resolver maps server SPA paths
                    // (`/shipper/loads`, `/shipper/settlements`, …) onto
                    // the shipper screen registry and posts the matching
                    // `.eusoShipperNavSwap` so navigation actually lands.
                    .environment(\.esangActionHandler) { action in
                        eSangRoleDispatcher.dispatch(
                            action,
                            role: session.user?.roleEnum ?? .shipper,
                            dismissSheet: { showeSang = false })
                    }
            }
    }

    private var currentIdentity: String {
        switch currentScreenId {
        case "261":
            return "shipper-261-\(activeLoadId ?? "__missing")"
        case "381":
            return "shipper-381-\(activeRfpId ?? "__missing")"
        case "435":
            return "shipper-435-\(activeAgreementPartnerId ?? "__missing")"
        case "393":
            return "shipper-393-\(activeSearchQuery ?? "__empty")"
        default:
            return "shipper-\(currentScreenId)"
        }
    }

    /// Routes a `MeAction.fire(key)` from any Shipper screen to its
    /// real action. The audit identified 11 keys that posted with
    /// no subscriber — every one of them now resolves either to an
    /// in-app deep-link, a sheet open, or a web continuation. Per
    /// [feedback_no_dead_buttons]: if a CTA's full backend wave
    /// hasn't shipped yet, it still fires through here and lands
    /// the user somewhere useful instead of dropping the tap.
    private func handleShipperMeAction(key: String, userInfo: [AnyHashable: Any]) {
        switch key {
        // In-app deep-links
        case "shipper.partner.detail":
            // Emergency Wave I1 — this used to write the partnerId /
            // catalystId into `activeLoadId`. Nothing consumed it
            // (281 has no `current` override), so the only effect was
            // LOAD-context pollution: a numeric partner id parked in
            // `activeLoadId` mounts 205/222 with the WRONG load on
            // any later swap that doesn't carry its own loadId.
            // Partner ids never enter the load context.
            withAnimation(.easeInOut(duration: 0.22)) {
                pushOrTab("281")
            }
        case "shipper.allocation.detail":
            withAnimation(.easeInOut(duration: 0.22)) {
                pushOrTab("230b")
            }
        case "shipper.bol.preview", "shipper.document.preview":
            if let urlStr = userInfo["url"] as? String,
               let url = URL(string: urlStr) {
                webContinuationURL = url
            } else {
                withAnimation(.easeInOut(duration: 0.22)) {
                    pushOrTab("226")
                }
            }

        // Native screens for actions that previously force-routed to the
        // web. Founder direction 2026-05-04: "we built all these screens
        // plus the logic" — the web fallback was masking shipped iOS
        // surfaces. Each native screen is registered for shipper role
        // (see ContentView ScreenRegistry); RoleAccess.canRender keeps
        // the routes RBAC-safe.
        case "shipper.agreement.create", "shipper.agreement.openOnWeb":
            withAnimation(.easeInOut(duration: 0.22)) {
                pushOrTab("223")  // Shipper · Agreements
            }
        case "shipper.allocation.create":
            withAnimation(.easeInOut(duration: 0.22)) {
                pushOrTab("229")  // Shipper · Allocations
            }
        case "shipper.partner.invite":
            withAnimation(.easeInOut(duration: 0.22)) {
                pushOrTab("224")  // Shipper · Partner Directory (invite)
            }
        case "shipper.recurring.schedule":
            withAnimation(.easeInOut(duration: 0.22)) {
                pushOrTab("221")  // Shipper · Recurring Loads
            }
        case "shipper.document.upload":
            withAnimation(.easeInOut(duration: 0.22)) {
                pushOrTab("226")  // Shipper · Document Center
            }
        case "shipper.settlement.openOnWeb":
            withAnimation(.easeInOut(duration: 0.22)) {
                pushOrTab("206")  // Shipper · Settlements
            }

        default:
            // Non-shipper.* keys (e.g., driver.*) belong to other
            // surfaces — silent default; the post is still valid
            // for any other listener subscribed in parallel.
            break
        }
    }

    // MARK: - Navigation stack helpers

    /// Push a screen id onto the stack, OR collapse to a tab root.
    /// Bottom-nav tab roots (200/201/204/320) reset the stack to a
    /// single entry — same semantics as a UITabBarController where
    /// switching tabs clears the per-tab back-trail. Re-tapping the
    /// current tab is a no-op so duplicate entries don't accumulate.
    private func pushOrTab(_ id: String) {
        if Self.tabRoots.contains(id) {
            screenStack = [id]
            return
        }
        if screenStack.last == id { return }   // dedupe consecutive
        screenStack.append(id)
    }

    /// Pop one entry off the stack. Never pops below the tab root —
    /// the back overlay is hidden when stack count == 1, but defend
    /// against rogue `.eusoShipperNavBack` posts anyway.
    private func popOne() {
        if screenStack.count > 1 {
            screenStack.removeLast()
        }
    }

    private var postLoadWizardScreen: ProductionScreen? {
        let draft = postLoadDraft
        let resumeDraftId = activePostLoadDraftId
        switch currentScreenId {
        case "250":
            return ProductionScreen(id: "250", title: "Shipper · Post Load · Lane", role: .shipper) { p in
                AnyView(PostLoadStep1LaneScreen(theme: p, draft: draft, resumeDraftId: resumeDraftId))
            }
        case "251":
            return ProductionScreen(id: "251", title: "Shipper · Post Load · Equipment", role: .shipper) { p in
                AnyView(PostLoadStep2EquipmentScreen(theme: p, draft: draft))
            }
        case "252":
            return ProductionScreen(id: "252", title: "Shipper · Post Load · Pricing", role: .shipper) { p in
                AnyView(PostLoadStep3PricingScreen(theme: p, draft: draft))
            }
        case "253":
            return ProductionScreen(id: "253", title: "Shipper · Post Load · Review", role: .shipper) { p in
                AnyView(PostLoadStep4ReviewScreen(theme: p, draft: draft))
            }
        case "254":
            return ProductionScreen(id: "254", title: "Shipper · Post Load · Success", role: .shipper) { p in
                AnyView(PostLoadSuccessScreen(theme: p, draft: draft))
            }
        case "255":
            return ProductionScreen(id: "255", title: "Shipper · Post Load · Multi-Stop", role: .shipper) { p in
                AnyView(PostLoadMultiStopScreen(theme: p, draft: draft))
            }
        case "256":
            return ProductionScreen(id: "256", title: "Shipper · Post Load · Address", role: .shipper) { p in
                AnyView(PostLoadAddressPickerScreen(theme: p, draft: draft))
            }
        case "257":
            return ProductionScreen(id: "257", title: "Shipper · Post Load · Hazmat", role: .shipper) { p in
                AnyView(PostLoadHazmatSubformScreen(theme: p, draft: draft))
            }
        case "258":
            return ProductionScreen(id: "258", title: "Shipper · Post Load · Reefer", role: .shipper) { p in
                AnyView(PostLoadReeferSubformScreen(theme: p, draft: draft))
            }
        case "259":
            return ProductionScreen(id: "259", title: "Shipper · Post Load · Templates", role: .shipper) { p in
                AnyView(PostLoadTemplatesScreen(theme: p, draft: draft))
            }
        default:
            return nil
        }
    }
}

// MARK: - ShipperSurface modifier groups
//
// SwiftUI's type-checker times out around 15+ generic modifiers on a
// single expression. Splitting the surface chain into named
// ViewModifier types keeps each chain ≤ ~7 modifiers — well within
// the type-checker's reliable budget — without changing semantics.

/// No-op pass-through. The surface previously rendered a translucent
/// back-arrow pill at top:56 — but every Me hub child screen
/// (320a-g) already paints its own "← Me" affordance in its header
/// row, so the overlay collided with the page subtitle (founder
/// screenshot 2026-05-04). Leaf screens reachable below the hub
/// children either have their own back affordance or land via
/// notification posts that pop the stack programmatically. If a
/// future leaf screen needs an extra back hit-target, give it its
/// own header back row — keeping the overlay path off avoids the
/// double-button collision.
private struct ShipperBackOverlay: ViewModifier {
    @Environment(\.eusoRoleDetailPresented) private var detailPresented
    let stackDepth: Int
    /// Screens that ship their own header back chevron — suppressing the
    /// surface overlay for these prevents the double-back collision the
    /// founder flagged 2026-04-30. Every other pushed screen gets the
    /// overlay so leaves like 222 Live Tracking, 226 Document Center,
    /// 106 EusoTickets, 064 Haul Leaderboard never strand the user.
    private static let screensWithOwnBack: Set<String> = [
        // 320 hub family draws its own "< Me" chevron in the header
        "320a", "320b", "320c", "320d", "320e", "320f", "320g",
        // Post-Load wizard has its own < chevron next to the title.
        // 2026-06-03 — "250" REMOVED: 250_PostLoadStep1Lane draws NO chevron
        // of its own (only "Multi-stop"/"Continue" CTAs), so suppressing the
        // surface overlay stranded it with zero back affordance (BLOCKER).
        // 204/251/252/253 do draw their own Back, so they stay suppressed.
        "204", "251", "252", "253",
        // Hub roots have no parent to return to
        "200", "201", "320",
        // 205 Shipper Load Detail draws its own < chevron next to the
        // lane title; suppress the surface overlay to avoid the
        // double-back collision.
        "205",
        // Detail / leaf screens that ship a header back chevron of
        // their own (audit 2026-05-05). Suppressing surface overlay
        // here prevents the floating circle from overlapping the
        // screen's own chevron.
        //
        // Founder bug 2026-05-22: 228/229/230/230b were in this list
        // but DON'T actually draw a header back chevron — they were
        // false-positive matches (229's "chevron.left" is its
        // date-picker prev-day arrow, not a nav back). With suppression
        // they had NO back button at all, matching the founder's
        // "ALLOCATION HAS NO BACK BUTTON" report. Removed; the
        // safeAreaInset-banded surface back now renders for them
        // without overlapping content.
        "227",
        // Founder back-button audit 2026-05-08 — 203 (Bids) draws its
        // own header chevron (backRow → posts .eusoShipperLoadOpen to
        // return to the load) AND was getting the floating overlay on
        // top. Listed here so only the in-screen back renders.
        //
        // Back-button reconciliation 2026-06-02: 223 (Agreements) was
        // ALSO listed here on the same audit, but its `topBar`
        // renders NO back affordance at all (verified — eyebrow +
        // counter only; the arrow.left.arrow.right is a swap-endpoints
        // glyph, chevron.right a row disclosure). It is reachable at
        // depth > 1 via the Me-hub agreement actions and the
        // `shipper/agreements` deep-link, so suppressing the surface
        // chevron STRANDED it (same false-positive class as the
        // 228/229/230 removal above). Removed so the safeAreaInset
        // surface back renders.
        "203",
    ]

    let currentScreenId: String

    func body(content: Content) -> some View {
        // 2026-05-22 founder ask — the back chevron was rendered as
        // an .overlay(alignment: .topLeading) on top of the screen
        // content, which obscured the eyebrow text on every Shipper
        // sub-page (Analytics / Live Tracking / Settlements / Reports
        // / Sustainability / Wallet / Allocations / …). Moving the
        // overlay to a `.safeAreaInset(edge: .top)` band gives the
        // chevron its own non-overlapping header strip that pushes
        // screen content down — eyebrow + title now paint cleanly
        // below the back affordance.
        content.safeAreaInset(edge: .top, spacing: 0) {
            if stackDepth > 1, !Self.screensWithOwnBack.contains(currentScreenId) {
                HStack(spacing: 0) {
                    Button {
                        NotificationCenter.default.post(
                            name: .eusoShipperNavBack, object: nil
                        )
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.55), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .modifier(EusoEdgeSwipeBack(
            isEnabled: stackDepth > 1 && !detailPresented,
            onBack: {
                NotificationCenter.default.post(
                    name: .eusoShipperNavBack, object: nil
                )
            }
        ))
    }
}

// NOTE: the former private `ShipperDetailLayer` was promoted to the
// shared `RoleDetailLayer` in `Theme/Components/RoleDetailPush.swift`
// (NAV remediation 2026-05-30 generalization). The Shipper surface now
// applies `RoleDetailLayer` directly (see body above) with an `onBack`
// closure that posts `.eusoShipperNavBack`. One implementation, app-wide.

/// Three environment overrides applied in sequence:
///   • driverNavHandler = nil — masks the inherited driver handler so
///     bottom-nav slots route to ShipperNavDispatcher.
///   • shipperNavHandler — direct in-process tab dispatch.
///   • openURL — `app.eusotrip.com/shipper/*` deep-links re-route to
///     the matching native screen (`ShipperWebToNativeMap`).
private struct ShipperEnvInjections: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler) { label in
                ShipperNavDispatcher.handle(label)
            }
            .environment(\.openURL, OpenURLAction { url in
                if let id = ShipperWebToNativeMap.screenId(for: url) {
                    // Emergency Wave I1 — the "load"→"205" alias used
                    // to swap to 205 WITHOUT ever setting the load
                    // context, mounting the registry sentinel. Route
                    // load-detail deep-links through the load-open
                    // path (which captures activeLoadId via the one
                    // resolver gate); a load deep-link with no
                    // resolvable id falls back to the loads list —
                    // never a bare 205.
                    if id == "205" {
                        if let lid = ShipperLoadIdResolver.normalize(
                            ShipperWebToNativeMap.loadId(for: url)) {
                            NotificationCenter.default.post(
                                name: .eusoShipperLoadOpen, object: nil,
                                userInfo: ["loadId": lid]
                            )
                        } else {
                            NotificationCenter.default.post(
                                name: .eusoShipperNavSwap, object: nil,
                                userInfo: ["screenId": "201"]
                            )
                        }
                        return .handled
                    }
                    NotificationCenter.default.post(
                        name: .eusoShipperNavSwap, object: nil,
                        userInfo: ["screenId": id]
                    )
                    return .handled
                }
                return .systemAction
            })
    }
}

/// All 15 NotificationCenter subscribers the surface listens to —
/// nav swaps, back, avatar-pick, ESANG sheet, load-create / browse-
/// carriers / load-list / load-open / load-open-map / settlement-
/// open-load / post-load-dismiss / esang-open / load-message-esang /
/// load-open-on-web / load-cancel / me-action-fired. Re-exposes
/// state via @Binding so the surface keeps owning truth.
private struct ShipperNotificationListeners: ViewModifier {
    @Binding var screenStack: [String]
    @Binding var activeLoadId: String?
    @Binding var activeRfpId: String?
    @Binding var activeAgreementPartnerId: String?
    @Binding var activePortIntelProduct: String?
    @Binding var activeSearchQuery: String?
    @Binding var activePostLoadDraftId: String?
    @Binding var showeSang: Bool
    @Binding var webContinuationURL: URL?
    @Binding var pushedDetail: RoleDetailPush?
    let pushOrTab: (String) -> Void
    let popOne: () -> Void
    let resetPostLoadDraft: () -> Void
    let applyIndustryWorkflow: (IndustryWorkflowHandoff) -> Void
    let handleMeAction: (String, [AnyHashable: Any]) -> Void

    func body(content: Content) -> some View {
        content
            .modifier(ShipperNavReceivers(
                screenStack: $screenStack,
                activeLoadId: $activeLoadId,
                activeRfpId: $activeRfpId,
                activeAgreementPartnerId: $activeAgreementPartnerId,
                activePortIntelProduct: $activePortIntelProduct,
                activeSearchQuery: $activeSearchQuery,
                activePostLoadDraftId: $activePostLoadDraftId,
                showeSang: $showeSang,
                pushedDetail: $pushedDetail,
                pushOrTab: pushOrTab,
                popOne: popOne,
                resetPostLoadDraft: resetPostLoadDraft,
                applyIndustryWorkflow: applyIndustryWorkflow
            ))
            .modifier(ShipperLoadReceivers(
                screenStack: $screenStack,
                activeLoadId: $activeLoadId,
                showeSang: $showeSang,
                webContinuationURL: $webContinuationURL,
                pushOrTab: pushOrTab,
                handleMeAction: handleMeAction
            ))
    }
}

/// Half 1 — nav-class subscribers. Limit to ≤ 7 receivers to keep the
/// type-checker happy.
private struct ShipperNavReceivers: ViewModifier {
    @Binding var screenStack: [String]
    @Binding var activeLoadId: String?
    @Binding var activeRfpId: String?
    @Binding var activeAgreementPartnerId: String?
    @Binding var activePortIntelProduct: String?
    @Binding var activeSearchQuery: String?
    @Binding var activePostLoadDraftId: String?
    @Binding var showeSang: Bool
    @Binding var pushedDetail: RoleDetailPush?
    let pushOrTab: (String) -> Void
    let popOne: () -> Void
    let resetPostLoadDraft: () -> Void
    let applyIndustryWorkflow: (IndustryWorkflowHandoff) -> Void

    private static let postLoadWizardIds: Set<String> = [
        "250", "251", "252", "253", "254", "255", "256", "257", "258", "259",
    ]

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                // `_logout` is a synthetic screenId posted by the Me
                // hub Sign-out cell. Forward to the global logout
                // notification — `EusoTripApp` listens and calls
                // `session.signOut()`. Without this intercept the
                // RBAC `canRender` check below fails (no registered
                // screen named "_logout") and the user landed on
                // Home instead of being signed out.
                if id == "_logout" {
                    NotificationCenter.default.post(name: Notification.Name("eusoLogoutRequested"), object: nil)
                    return
                }
                guard RoleAccess.canRender(role: .shipper, screenId: id) else {
                    screenStack = ["200"]
                    return
                }
                // Emergency Wave I1 — load-context capture. 282/316/
                // 327/333 post NavSwap with screenId "205" + a loadId
                // payload that was previously DROPPED here, so 205
                // mounted on the registry sentinel and skeleton'd
                // forever. Every id passes the one resolver gate
                // (strips `load_NNN`, rejects the `"0"` sentinel).
                if id == "205" || id == "222" {
                    if let lid = ShipperLoadIdResolver.normalize(
                        note.userInfo?["loadId"]) {
                        activeLoadId = lid
                    }
                }
                // 261/381/435 are actionable record details. Assign the
                // normalized optional on every target swap (including nil)
                // so a payload-less route fails closed instead of reusing the
                // record from a previous visit.
                if id == "261" {
                    activeLoadId = ShipperLoadIdResolver.normalize(note.userInfo?["loadId"])
                }
                if id == "381" {
                    activeRfpId = ShipperRoutedRecordIdResolver.rfp(note.userInfo?["rfpId"])
                }
                if id == "435" {
                    activeAgreementPartnerId = ShipperRoutedRecordIdResolver.positiveNumeric(
                        note.userInfo?["partnerId"]
                    )
                }
                // Wave I2 — 424→425 grade handoff. Overwritten on
                // every 425 swap (nil when absent) so a stale grade
                // never leaks into a later bare open.
                if id == "425" {
                    activePortIntelProduct = note.userInfo?["product"] as? String
                }
                if id == "393" {
                    let rawQuery = note.userInfo?["query"] as? String
                    let cleaned = rawQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
                    activeSearchQuery = (cleaned?.isEmpty == false) ? cleaned : nil
                } else {
                    activeSearchQuery = nil
                }
                if id == "250" {
                    let lastScreen = screenStack.last
                    if let handoff = note.userInfo?["industryWorkflow"] as? IndustryWorkflowHandoff {
                        activePostLoadDraftId = nil
                        resetPostLoadDraft()
                        applyIndustryWorkflow(handoff)
                    } else if let rawDraftId = note.userInfo?["draftId"] as? String,
                       !rawDraftId.isEmpty {
                        if activePostLoadDraftId != rawDraftId {
                            resetPostLoadDraft()
                        }
                        activePostLoadDraftId = rawDraftId
                    } else if (note.userInfo?["freshDraft"] as? Bool) == true
                        || !(lastScreen.map(Self.postLoadWizardIds.contains) ?? false) {
                        activePostLoadDraftId = nil
                        resetPostLoadDraft()
                    }
                } else if !Self.postLoadWizardIds.contains(id) {
                    activePostLoadDraftId = nil
                }
                // Any explicit screen swap leaves the generic detail
                // layer behind — clear it so a stale detail never paints
                // over a freshly-swapped screen.
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperNavBack)) { _ in
                // Detail layer takes priority: one back gesture pops one
                // level. If a generic sheet→push detail is showing, slide
                // it back out; only when no detail is up do we pop the
                // registry `screenStack`.
                if pushedDetail != nil {
                    withAnimation(.easeInOut(duration: 0.28)) { pushedDetail = nil }
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) { popOne() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShippereSangTapped)) { _ in
                showeSang = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperLoadCreate)) { _ in
                guard RoleAccess.canRender(role: .shipper, screenId: "204") else { return }
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab("204") }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperBrowseCarriers)) { _ in
                guard RoleAccess.canRender(role: .shipper, screenId: "224") else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    // 224 is NOT a tab root — it APPENDS, so a 205/222
                    // drilled beneath stays on the stack. Clearing the
                    // load context here (the old behavior) meant the
                    // back gesture popped onto a 205 whose loadId was
                    // gone → registry sentinel → forever-skeleton.
                    // Only clear once no load-context screen remains.
                    pushOrTab("224")
                    clearLoadContextIfUnreferenced()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperLoadListOpen)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) {
                    pushOrTab("201")
                    clearLoadContextIfUnreferenced()
                }
            }
    }

    /// Emergency Wave I1 — `activeLoadId` may only be cleared when no
    /// load-context screen (205 load detail / 222 live tracking / 261 bids)
    /// remains anywhere on the nav stack. Tab-root pushes collapse the
    /// stack so the clear proceeds; appending pushes keep the drilled
    /// detail alive underneath and the context with it.
    private func clearLoadContextIfUnreferenced() {
        if !screenStack.contains(where: { $0 == "205" || $0 == "222" || $0 == "261" }) {
            activeLoadId = nil
        }
    }
}

/// Half 2 — load-context + ESANG + MeAction subscribers. Same ≤ 7
/// budget per modifier.
private struct ShipperLoadReceivers: ViewModifier {
    @Binding var screenStack: [String]
    @Binding var activeLoadId: String?
    @Binding var showeSang: Bool
    @Binding var webContinuationURL: URL?
    let pushOrTab: (String) -> Void
    let handleMeAction: (String, [AnyHashable: Any]) -> Void

    func body(content: Content) -> some View {
        content
            // Emergency Wave I1 — every load-open entry passes the ONE
            // `ShipperLoadIdResolver` gate: `load_NNN` handles open the
            // same detail as numeric ids, and a sentinel/empty id can
            // never mount a 205 (the registry placeholder renders the
            // honest "select a load" state instead of a fake detail).
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperLoadOpen)) { note in
                guard let id = ShipperLoadIdResolver.normalize(
                    note.userInfo?["loadId"] as? String) else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    activeLoadId = id
                    pushOrTab("205")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperLoadOpenMap)) { note in
                guard RoleAccess.canRender(role: .shipper, screenId: "222") else { return }
                if let id = ShipperLoadIdResolver.normalize(
                    note.userInfo?["loadId"] as? String) {
                    activeLoadId = id
                }
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab("222") }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperSettlementOpenLoad)) { note in
                guard let id = ShipperLoadIdResolver.normalize(
                    note.userInfo?["loadId"] as? String) else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    activeLoadId = id
                    pushOrTab("205")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperPostLoadDismiss)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) {
                    // Collapse FIRST, clear SECOND — the load context
                    // may only drop once no 205/222 remains mounted.
                    // (Wave I1: clearing while a 205 was still on the
                    // stack re-rendered it on the registry sentinel.)
                    screenStack = ["200"]
                    activeLoadId = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShippereSangOpen)) { _ in
                showeSang = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperLoadMessageeSang)) { _ in
                showeSang = true
            }
            .modifier(ShipperWebContReceivers(
                webContinuationURL: $webContinuationURL,
                handleMeAction: handleMeAction
            ))
    }
}

/// Tail subscribers — load-open-on-web, load-cancel, MeAction. Split
/// out so `ShipperLoadReceivers` stays ≤ 7 chained `onReceive` calls.
private struct ShipperWebContReceivers: ViewModifier {
    @Binding var webContinuationURL: URL?
    let handleMeAction: (String, [AnyHashable: Any]) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperLoadOpenOnWeb)) { note in
                let id = (note.userInfo?["loadId"] as? String) ?? ""
                let action = (note.userInfo?["action"] as? String) ?? ""
                let path: String
                switch action {
                case "counter-all":
                    let amt = (note.userInfo?["amount"] as? String) ?? ""
                    path = "loads/\(id)/bids?action=counter-all&amount=\(amt)"
                case "settlement-approve-all": path = "settlements?action=approve-all"
                case "settlement.openOnWeb":   path = "settlements"
                case "agreement.openOnWeb":    path = "agreements"
                default:                       path = id.isEmpty ? "loads" : "loads/\(id)"
                }
                webContinuationURL = URL(string: "https://app.eusotrip.com/\(path)")
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperLoadCancelRequested)) { note in
                let id = (note.userInfo?["loadId"] as? String) ?? ""
                webContinuationURL = URL(string: "https://app.eusotrip.com/loads/\(id)?action=cancel")
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoMeActionFired)) { note in
                guard let key = note.object as? String else { return }
                handleMeAction(key, note.userInfo ?? [:])
            }
    }
}

// MARK: - Shipper web→native deep-link mapper

/// Maps `https://app.eusotrip.com/shipper/...` deep-link URLs to the
/// shipper-role screen ID that handles the same surface natively. Used
/// by `ShipperSurface`'s `\.openURL` interceptor to keep taps in-app
/// when a native equivalent ships, while letting non-shipper URLs
/// (PDF documents, Stripe checkout, mailto:, App Store, help articles)
/// fall through to `SFSafariViewController` / system handlers.
///
/// Returning `nil` means "no native route — open the URL via the
/// default system action." That preserves every legitimate web
/// continuation; only the shipper deep-links that mask shipped iOS
/// surfaces get redirected.
enum ShipperWebToNativeMap {

    /// Single source of truth for shipper deep-link → screen ID
    /// mapping. Path patterns are matched against `URLComponents.path`
    /// after stripping the leading slash. Trailing path segments are
    /// ignored (the resource id is opaque to this mapper — the
    /// destination screen reads its own id from notification userInfo
    /// when it needs one).
    static func screenId(for url: URL) -> String? {
        // Only intercept shipper deep-links on the canonical app
        // host. PDFs, Stripe redirects, mailto, etc. should bypass
        // this mapper entirely.
        guard let host = url.host,
              host == "app.eusotrip.com" || host == "eusotrip.com" else {
            return nil
        }
        let segments = url.pathComponents.filter { $0 != "/" }

        // Wallet pickup credential — `/wallet/credential/<loadId>` is
        // the canonical web-parity surface for the same EusoWallet
        // pickup card the iOS shipper sees on screen 239. Universal
        // Link routing pulls iOS users into the native wallet.
        if segments.first == "wallet",
           segments.count >= 3,
           segments[1] == "credential" {
            return "239"
        }

        guard segments.first == "shipper", segments.count >= 2 else {
            return nil
        }
        switch segments[1] {
        case "allocations":           return "229"
        case "agreements":            return "223"
        case "agreement":             return "223"
        case "partner-directory":     return "224"
        case "partners":              return "224"
        case "partner":               return "434"
        case "recurring-loads",
             "recurring":             return "221"
        case "documents",
             "document-center":       return "226"
        // `/shipper/settlements` (bare / list) → 206. But
        // `/shipper/settlements/<id>/documents/<doc>` is a REAL document
        // (POD / rate-conf / invoice / lumper / detention / receipt) —
        // a PDF/web resource that must open in the browser/QuickLook,
        // NOT be intercepted to the settlements list (which dropped the
        // id + doc and stranded the user on 206). Return nil for the
        // documents sub-path so it falls through to the system action.
        case "settlements":
            if segments.count >= 4, segments[2] == "documents" {
                return nil
            }
            if segments.count >= 5, segments[3] == "documents" {
                return nil
            }
            return "206"
        case "settlement":            return "227"
        case "payment-methods",
             "payment-method":        return "295"
        // `bol`/`bols` → registry id "228" = ShipperBOLs (the BOLs
        // LIST). NOTE: registry ids are NOT the file numbers — file
        // 228_ShipperRFPDetail registers as "228b", and registry "228"
        // is the BOLs list (ContentView 711). So this mapping is
        // CORRECT (a bare `/shipper/bol` link opens the BOL list). The
        // `/shipper/bol/<id>/audit-trail` sub-resource (229 BOL Upload's
        // "View audit trail" CTA) is a SHA-256-chain web document opened
        // in-app via SFSafariViewController on that screen — it never
        // routes through this mapper, so the audit trail is preserved.
        case "bol",
             "bols":                  return "228"
        case "rfp",
             "rfps":                  return "215"
        case "contracts",
             "contract":              return "217"
        case "freight-claims",
             "freight-claim",
             "claims":                return "219"
        case "control-tower":         return "212"
        case "compliance":            return "216"
        case "sustainability":        return "214"
        case "reports":               return "207"
        case "analytics":             return "210"
        case "live-tracking",
             "tracking":              return "222"
        case "hot-zones":             return "225"
        case "rate-board":            return "220"
        case "settings":              return "211"
        // `/shipper/push/<id>/open` (231 hero CTA) and
        // `/shipper/push/category/<id>` (231 category row) were MISSING
        // a case → fell through to `.systemAction` → browser-bounced.
        // Map to 231 (the Push Notification Landing) so any push
        // deep-link stays in-app. `/shipper/settings/push` is handled
        // by `case "settings"` below (→ 211) and is unaffected.
        case "push":                  return "231"
        // `/shipper/contacts/new` is an INTENTIONAL web continuation in
        // the audit's original read, BUT 209 now ships a native
        // `AddContactSheet`, so its add-contact CTAs present the sheet
        // locally and no longer emit this URL. Returning nil keeps any
        // legacy/external `contacts` deep-link on the system action
        // (correct — there is no list-level native `contacts` route to
        // mount; the contacts list is reached via the Me hub, not a
        // deep-link). Documented so it is not re-flagged as a gap.
        case "contacts":              return nil
        case "live-activity":         return "232"
        case "watch":                 return "233"
        case "haptic":                return "234"
        case "focus":                 return "235"
        case "widget",
             "widgets":               return "236"
        case "intents",
             "siri":                  return "237"
        case "handoff":               return "238"
        case "apple-pay":             return "239"
        case "carplay":               return "240"
        // `/shipper/loads` (bare) is the list; `/shipper/loads/<id>`
        // and `/shipper/load/<id>` are the detail. The detail screen
        // requires a load id — `loadId(for:)` below extracts it and
        // the openURL interceptor routes through the load-open path
        // so 205 never mounts on the registry sentinel (Wave I1).
        //
        // Keyword-leak guard — `/shipper/loads/<keyword>` where the
        // third segment is a reserved list-level action (search / new /
        // filter / …) is NOT a detail link. Map it to the loads LIST
        // (201) so it never tries to mount 205 on a non-id segment.
        // (Resolver `normalize`/`loadId(for:)` reject the same set; this
        // keeps the mapper honest at the screen-id layer too — the
        // founder-reported `/loads/search` "Load not found" class.)
        case "loads":
            if segments.count >= 3,
               ShipperLoadIdResolver.reservedSegments.contains(segments[2].lowercased()) {
                return "201"
            }
            return segments.count >= 3 ? "205" : "201"
        case "load":                  return "205"
        case "market-intelligence",
             "market-pricing",
             "market",
             "pricing":               return "330"
        default:                      return nil
        }
    }

    /// Extracts the load id segment from a shipper load deep-link
    /// (`/shipper/load/<id>` or `/shipper/loads/<id>`). Returns nil
    /// when the link carries no id — the caller falls back to the
    /// loads list rather than mounting a bare detail.
    static func loadId(for url: URL) -> String? {
        guard let host = url.host,
              host == "app.eusotrip.com" || host == "eusotrip.com" else {
            return nil
        }
        let segments = url.pathComponents.filter { $0 != "/" }
        guard segments.first == "shipper", segments.count >= 3,
              segments[1] == "load" || segments[1] == "loads" else {
            return nil
        }
        let candidate = segments[2]
        // Keyword-leak guard — `/shipper/loads/search` (and the rest of
        // the reserved action family) must NOT be handed back as a load
        // id. Returning nil here makes the openURL interceptor fall the
        // bare `loads` deep-link to the loads list (201) instead of
        // mounting 205 on a non-resolvable segment. `normalize` enforces
        // the same set, but rejecting here keeps the bogus id from ever
        // reaching the load-open path. (Resolver-level durable fix for
        // the whole `/loads/<non-numeric>` family.)
        if ShipperLoadIdResolver.reservedSegments.contains(candidate.lowercased()) {
            return nil
        }
        return candidate
    }

    /// Parses a leading screen-id number out of a human-readable
    /// `targetScreen` label and returns it iff it is a real shipper
    /// screen. The device-feature leaf screens (231-240) carry their
    /// row CTAs' destinations as strings like:
    ///
    ///   "212 Control Tower"            → "212"
    ///   "→ 205 Load Detail"           → "205"
    ///   "212 Control Tower · ACTIVE"  → "212"
    ///   "231 Push Notification Landing"→ "231"
    ///
    /// Those CTAs used to round-trip through `openURL` / an in-app
    /// Safari sheet (or re-mount their own list); this lets them swap
    /// natively to the labelled screen instead. Returns nil when the
    /// label has no leading screen number or the number is not a
    /// shipper-renderable screen (honest: the caller keeps the user on
    /// the current screen rather than navigating somewhere fake).
    ///
    /// IMPORTANT — these labels carry the WIREFRAME number, which is NOT
    /// always the registry id (the "iOS numbering vs SVG catalog"
    /// hazard: file 229_BOLUpload registers as "229b"; registry "229" is
    /// Allocations). So we reconcile by PURPOSE (the trailing name)
    /// FIRST, then fall back to the leading number only when the name is
    /// unrecognized AND the number is a real shipper screen. This stops
    /// "229 BOL Upload" from mis-routing to Allocations.
    static func targetScreenId(from label: String?) -> String? {
        guard let label = label else { return nil }
        let lower = label.lowercased()

        // Purpose-first reconciliation for the labels these leaf screens
        // actually emit. Match the screen NAME, return the real registry
        // id. (Name match wins over the embedded wireframe number.)
        if lower.contains("bol upload")              { return "229b" }  // not "229" (Allocations)
        if lower.contains("load detail")             { return "205" }
        if lower.contains("control tower")           { return "212" }
        if lower.contains("push notification")       { return "231" }
        if lower.contains("live activity")           { return "232" }
        if lower.contains("watch complication")      { return "233" }
        if lower.contains("rfp")                     { return "215" }
        if lower.contains("settlement")              { return "227" }
        if lower.contains("live tracking")           { return "222" }

        // Fallback — the first run of digits is the wireframe number;
        // accept it only when it is a real shipper screen.
        var digits = ""
        var started = false
        for ch in label {
            if ch.isNumber { digits.append(ch); started = true }
            else if started { break }   // stop at the first non-digit after digits began
        }
        guard !digits.isEmpty else { return nil }
        // Only return ids this surface can actually render — an
        // out-of-role / unknown number must NOT navigate anywhere.
        guard RoleAccess.canRender(role: .shipper, screenId: digits) else {
            return nil
        }
        return digits
    }
}

// MARK: - Carrier surface

/// Top-level Carrier (CATALYST) container. Mirror of `ShipperSurface`
/// for the carrier role. Holds the currently-rendered carrier screen
/// ID, listens to `.eusoCarrierNavSwap` for slot taps, and looks up
/// the matching screen out of `ScreenRegistry`. RBAC: only screens
/// where `role == .carrier` are accepted; an out-of-role notification
/// payload short-circuits to 300 home.
struct CarrierSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    /// Founder mandate 2026-05-05 — push/pop nav stack so leaf screens
    /// always have a back path. Bottom-nav tabs reset the stack to a
    /// single entry; non-tab screens append.
    @State private var screenStack: [String] = ["500"]
    @State private var showeSang: Bool = false
    /// Shared sheet→push detail layer (NAV remediation 2026-05-30).
    /// Ready for the per-role sheet-conversion wave; surfaces the
    /// `\.rolePushDetail` env closure and renders the pushed detail
    /// in-stack with a `BespokeBackBar`.
    @State private var pushedDetail: RoleDetailPush? = nil
    // tabRoots must equal the 4 BottomNav slot destinations. The Carrier
    // bottom-nav (300 Home / Loads / Drivers / Me) resolves through
    // `CarrierNavRoute.map`:
    //   home→300 · loads→301 · drivers→304 · me→350.
    // The previous literal {300,301,302,303} listed 302 (Load Detail) and
    // 303 (Dispatch Board) — neither is a bottom-nav slot — and omitted the
    // Drivers slot (304) and the Me slot (350). With 350 absent the Me tab
    // never reset to its root (350 CarrierMe). Carrier's back-overlay uses a
    // separate `backSuppress` set, so this change only corrects tab-reset
    // semantics. Corrected to the real slot set. (IA recon 2026-05-30.)
    private static let tabRoots: Set<String> = ["500", "501", "304", "350"]

    /// Carrier-side suppress list — same purpose as ShipperBackOverlay's
    /// `screensWithOwnBack`. Tab roots + leaves that draw their OWN
    /// functional back affordance (a `Button` posting `.eusoRoleNavBack`),
    /// so the surface overlay must NOT paint a second chevron.
    ///
    /// Back-button reconciliation 2026-06-02 — reconciled against the
    /// screens this surface can actually render. The surface resolves an
    /// id out of the concatenated `.carrier` + `.catalyst` pool, carrier
    /// FIRST, so a colliding id renders the carrier screen:
    ///   • 321 (Catalyst Driver Profile) DOES draw its own chevron that
    ///     posts `.eusoRoleNavBack` — kept (prevents the double).
    ///   • 305 collides: `.carrier` 305 = CarrierCounterResponse (NO own
    ///     back) wins the pool lookup over `.catalyst` 305 (Load Detail,
    ///     which has its own back). 305 is reachable at depth > 1 via
    ///     308_CarrierMyBids' `eusoCarrierNavSwap{"305"}`, so suppressing
    ///     the surface chevron STRANDED the rendered CounterResponse.
    ///     Removed — surface chevron now renders (no double, no strand).
    ///   • 302 (Carrier Load Detail) / 303 (Carrier Dispatch Board) are
    ///     NOT bottom-nav slots and are NOT reached as surface-stack
    ///     screens — 301 opens load detail through the in-stack
    ///     `\.rolePushDetail` layer, never `navSwap{"302"}` — and neither
    ///     draws its own back. The old comment mislabeled them "tab roots"
    ///     (the real tab roots are 300/301/304/350). Removed as stale; if
    ///     either is ever pushed it now correctly gets the surface chevron.
    private static let backSuppress: Set<String> = [
        "500", "501", "304", "350", // Catalyst role roots
        "321",                  // Catalyst Driver Profile — own .eusoRoleNavBack
    ]

    private var currentScreenId: String { screenStack.last ?? "500" }

    private var current: ProductionScreen {
        let pool = ScreenRegistry.forRole(.catalyst)
                 + ScreenRegistry.forRole(.carrier)
        return pool.first { $0.id == currentScreenId }
            ?? pool.first { $0.id == "500" }
            ?? pool.first
            ?? ProductionScreen(id: "500",
                                title: "Catalyst · Home",
                                role: .catalyst) { p in
                                    AnyView(CatalystHomeScreen(theme: p))
                                }
    }

    private var roleDock: RoleDockContract {
        RoleDockCatalog.catalyst(
            active: screenStack.first ?? "500",
            select: { destination in
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(destination) }
            },
            openESang: { showeSang = true }
        )
    }

    private func pushOrTab(_ id: String) {
        if Self.tabRoots.contains(id) { screenStack = [id]; return }
        if screenStack.last == id { return }
        screenStack.append(id)
    }
    private func popOne() { if screenStack.count > 1 { screenStack.removeLast() } }

    var body: some View {
        current.view(palette)
            .id("carrier-\(currentScreenId)")
            .eusoRefreshSurface("catalyst:\(currentScreenId)")
            .transition(.opacity)
            .modifier(RoleNavBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId,
                screensWithOwnBack: Self.backSuppress
            ))
            // Shared sheet→push detail layer — injects `\.rolePushDetail`
            // and renders the pushed detail in-stack (BespokeBackBar on
            // top). onBack posts the shared NavBack the surface listens to.
            .modifier(RoleDetailLayer(
                pushedDetail: $pushedDetail,
                palette: palette,
                onBack: {
                    NotificationCenter.default.post(
                        name: .eusoRoleNavBack, object: nil)
                }
            ))
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler, nil)
            .environment(\.carrierNavHandler) { label in
                CarrierNavDispatcher.handle(label)
            }
            .environment(\.roleDockContract, roleDock)
            .onReceive(NotificationCenter.default.publisher(for: .eusoCarrierNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .catalyst, screenId: id) else {
                    screenStack = ["500"]; return
                }
                // Any explicit swap leaves the detail layer behind.
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                // Detail-first: one back gesture pops one level.
                if pushedDetail != nil {
                    withAnimation(.easeInOut(duration: 0.28)) { pushedDetail = nil }
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) { popOne() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoCarriereSangTapped)) { _ in
                showeSang = true
            }
            // ASC AOd5xzXVfU6CF6hyijTDwgk parity: same peek-band/status-bar
            // collision class as the Shipper coach sheet — full-screen cover
            // across all nine role surfaces (sheet has its own close X).
            .fullScreenCover(isPresented: $showeSang) {
                DrivereSangCoachSheet()
                    .environment(\.palette, palette)
                    .environment(\.esangActionHandler) { action in
                        eSangRoleDispatcher.dispatch(
                            action,
                            role: session.user?.roleEnum ?? .catalyst,
                            dismissSheet: { showeSang = false })
                    }
            }
    }
}

// MARK: - Broker surface

/// Top-level Broker container. Mirror of `ShipperSurface` /
/// `CarrierSurface` for the BROKER role. Holds the currently-rendered
/// broker screen ID, listens to `.eusoBrokerNavSwap` for slot taps,
/// looks up the matching screen out of `ScreenRegistry`. RBAC: only
/// screens where `role == .broker` are accepted; an out-of-role
/// notification payload short-circuits to 400 home.
struct BrokerSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    @State private var screenStack: [String] = ["400"]
    @State private var showeSang: Bool = false
    /// Shared sheet→push detail layer (NAV remediation 2026-05-30).
    @State private var pushedDetail: RoleDetailPush? = nil
    // tabRoots must equal the 4 BottomNav slot destinations. The Broker
    // bottom-nav (400 Home / Tenders / Carriers / Me) resolves through
    // `BrokerNavRoute.map`:
    //   home→400 · loads/tenders→401 · carriers→402b · me→404B.
    // All four ids below are registered broker screens and match the map
    // verbatim — the Me hub is 404B (Commission Queue dual), NOT bare
    // 404. The "Tenders" label gained its own map alias onto 401 in the
    // 2026-06-09 alias sweep (it was a flagged no-op since the 2026-05-30
    // IA recon). Keep this set in lockstep with `BrokerNavRoute.map`.
    // (Comment re-verified against shipped code 2026-06-09.)
    private static let tabRoots: Set<String> = ["400", "401", "402b", "404B"]

    private var currentScreenId: String { screenStack.last ?? "400" }

    private var current: ProductionScreen {
        ScreenRegistry.forRole(.broker).first { $0.id == currentScreenId }
            ?? ScreenRegistry.forRole(.broker).first { $0.id == "400" }
            ?? ScreenRegistry.forRole(.broker).first
            ?? ProductionScreen(id: "400",
                                title: "Broker · Home",
                                role: .broker) { p in
                                    AnyView(BrokerHomeScreen(theme: p))
                                }
    }

    private func pushOrTab(_ id: String) {
        if Self.tabRoots.contains(id) { screenStack = [id]; return }
        if screenStack.last == id { return }
        screenStack.append(id)
    }
    private func popOne() { if screenStack.count > 1 { screenStack.removeLast() } }

    private var roleDock: RoleDockContract {
        RoleDockCatalog.broker(
            active: screenStack.first ?? "400",
            select: { destination in
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(destination) }
            },
            openESang: { showeSang = true }
        )
    }

    var body: some View {
        current.view(palette)
            .id("broker-\(currentScreenId)")
            .eusoRefreshSurface("broker:\(currentScreenId)")
            .transition(.opacity)
            .modifier(RoleNavBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId,
                screensWithOwnBack: Self.tabRoots
            ))
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler, nil)
            .environment(\.brokerNavHandler) { label in
                BrokerNavDispatcher.handle(label)
            }
            .environment(\.roleDockContract, roleDock)
            .modifier(RoleDetailLayer(
                pushedDetail: $pushedDetail,
                palette: palette,
                onBack: {
                    NotificationCenter.default.post(
                        name: .eusoRoleNavBack, object: nil)
                }
            ))
            .onReceive(NotificationCenter.default.publisher(for: .eusoBrokerNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .broker, screenId: id) else {
                    screenStack = ["400"]; return
                }
                // 2026-05-21 — capture drill-down payload (catalystId /
                // loadId) into BrokerNavContext so child screens can
                // read it during init. ScreenRegistry factories are
                // (palette) -> AnyView with no slot for extra args.
                if let c = note.userInfo?["catalystId"] as? String { BrokerNavContext.latestCatalystId = c }
                if let l = note.userInfo?["loadId"]     as? String { BrokerNavContext.latestLoadId     = l }
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                if pushedDetail != nil {
                    withAnimation(.easeInOut(duration: 0.28)) { pushedDetail = nil }
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) { popOne() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoBrokereSangTapped)) { _ in
                showeSang = true
            }
            .fullScreenCover(isPresented: $showeSang) {
                DrivereSangCoachSheet()
                    .environment(\.palette, palette)
                    .environment(\.esangActionHandler) { action in
                        eSangRoleDispatcher.dispatch(
                            action,
                            role: session.user?.roleEnum ?? .broker,
                            dismissSheet: { showeSang = false })
                    }
            }
    }
}

// MARK: - Escort surface

/// Top-level Escort container. Pattern matches Shipper / Carrier /
/// Broker. RBAC-gated through `RoleAccess.canRender(role:.escort)`.
struct EscortSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    @State private var screenStack: [String] = ["600"]
    @State private var showeSang: Bool = false
    /// Shared sheet→push detail layer (NAV remediation 2026-05-30).
    @State private var pushedDetail: RoleDetailPush? = nil
    // tabRoots must equal the 4 BottomNav slot destinations. The Escort
    // bottom-nav (600 Home / Assignments / Corridor / Me) resolves through
    // `EscortNavRoute.map`:
    //   home→600 · assignments→601 · corridor→602 · me→620.
    // All four ids below are registered escort screens and match the map
    // verbatim — Me resolves to the dedicated 620 Escort Me hub (it no
    // longer collapses onto 600 Home as an older revision of this comment
    // claimed). Keep this set in lockstep with `EscortNavRoute.map`.
    // (Comment re-verified against shipped code 2026-06-09.)
    private static let tabRoots: Set<String> = ["600", "601", "602", "620"]

    private var currentScreenId: String { screenStack.last ?? "600" }

    private var current: ProductionScreen {
        ScreenRegistry.forRole(.escort).first { $0.id == currentScreenId }
            ?? ScreenRegistry.forRole(.escort).first { $0.id == "600" }
            ?? ScreenRegistry.forRole(.escort).first
            ?? ProductionScreen(id: "600",
                                title: "Escort · Home",
                                role: .escort) { p in
                                    AnyView(EscortHomeScreen(theme: p))
                                }
    }

    private func pushOrTab(_ id: String) {
        if Self.tabRoots.contains(id) { screenStack = [id]; return }
        if screenStack.last == id { return }
        screenStack.append(id)
    }
    private func popOne() { if screenStack.count > 1 { screenStack.removeLast() } }

    private var roleDock: RoleDockContract {
        RoleDockCatalog.escort(
            active: screenStack.first ?? "600",
            select: { destination in
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(destination) }
            },
            openESang: { showeSang = true }
        )
    }

    var body: some View {
        current.view(palette)
            .id("escort-\(currentScreenId)")
            .eusoRefreshSurface("escort:\(currentScreenId)")
            .transition(.opacity)
            .modifier(RoleNavBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId,
                screensWithOwnBack: Self.tabRoots
            ))
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler, nil)
            .environment(\.escortNavHandler) { label in
                EscortNavDispatcher.handle(label)
            }
            .environment(\.roleDockContract, roleDock)
            .modifier(RoleDetailLayer(
                pushedDetail: $pushedDetail,
                palette: palette,
                onBack: {
                    NotificationCenter.default.post(
                        name: .eusoRoleNavBack, object: nil)
                }
            ))
            .onReceive(NotificationCenter.default.publisher(for: .eusoEscortNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .escort, screenId: id) else {
                    screenStack = ["600"]; return
                }
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                if pushedDetail != nil {
                    withAnimation(.easeInOut(duration: 0.28)) { pushedDetail = nil }
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) { popOne() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoEscorteSangTapped)) { _ in
                showeSang = true
            }
            .fullScreenCover(isPresented: $showeSang) {
                DrivereSangCoachSheet()
                    .environment(\.palette, palette)
                    .environment(\.esangActionHandler) { action in
                        eSangRoleDispatcher.dispatch(
                            action,
                            role: session.user?.roleEnum ?? .escort,
                            dismissSheet: { showeSang = false })
                    }
            }
    }
}

// MARK: - Terminal surface

/// Top-level Terminal container. Pattern matches Shipper / Carrier /
/// Broker / Escort. RBAC-gated through `RoleAccess.canRender(role:.terminal)`.
struct TerminalSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    @State private var screenStack: [String] = ["700"]
    @State private var showeSang: Bool = false
    /// Shared sheet→push detail layer (NAV remediation 2026-05-30).
    @State private var pushedDetail: RoleDetailPush? = nil
    // tabRoots must equal the 4 BottomNav slot destinations. The Terminal
    // bottom-nav (700 Home / Movements / Yard / Me) resolves through
    // `TerminalNavRoute.map`:
    //   home→700 · movements→701 · yard→702 · me→703.
    // All four ids below are registered terminal screens and match the
    // map verbatim — Me resolves to the dedicated 703 Terminal Me hub
    // (it no longer collapses onto 700 Home, and 703 IS registered now,
    // contrary to an older revision of this comment). Keep this set in
    // lockstep with `TerminalNavRoute.map`.
    // (Comment re-verified against shipped code 2026-06-09.)
    private static let tabRoots: Set<String> = ["700", "701", "702", "703"]

    private var currentScreenId: String { screenStack.last ?? "700" }

    private var current: ProductionScreen {
        ScreenRegistry.forRole(.terminal).first { $0.id == currentScreenId }
            ?? ScreenRegistry.forRole(.terminal).first { $0.id == "700" }
            ?? ScreenRegistry.forRole(.terminal).first
            ?? ProductionScreen(id: "700",
                                title: "Terminal · Home",
                                role: .terminal) { p in
                                    AnyView(TerminalHomeScreen(theme: p))
                                }
    }

    private func pushOrTab(_ id: String) {
        if Self.tabRoots.contains(id) { screenStack = [id]; return }
        if screenStack.last == id { return }
        screenStack.append(id)
    }
    private func popOne() { if screenStack.count > 1 { screenStack.removeLast() } }

    private var roleDock: RoleDockContract {
        RoleDockCatalog.terminal(
            active: screenStack.first ?? "700",
            select: { destination in
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(destination) }
            },
            openESang: { showeSang = true }
        )
    }

    var body: some View {
        current.view(palette)
            .id("terminal-\(currentScreenId)")
            .eusoRefreshSurface("terminal:\(currentScreenId)")
            .transition(.opacity)
            .modifier(RoleNavBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId,
                screensWithOwnBack: Self.tabRoots
            ))
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler, nil)
            .environment(\.terminalNavHandler) { label in
                TerminalNavDispatcher.handle(label)
            }
            .environment(\.roleDockContract, roleDock)
            .modifier(RoleDetailLayer(
                pushedDetail: $pushedDetail,
                palette: palette,
                onBack: {
                    NotificationCenter.default.post(
                        name: .eusoRoleNavBack, object: nil)
                }
            ))
            .onReceive(NotificationCenter.default.publisher(for: .eusoTerminalNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .terminal, screenId: id) else {
                    screenStack = ["700"]; return
                }
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                if pushedDetail != nil {
                    withAnimation(.easeInOut(duration: 0.28)) { pushedDetail = nil }
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) { popOne() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoTerminaleSangTapped)) { _ in
                showeSang = true
            }
            .fullScreenCover(isPresented: $showeSang) {
                DrivereSangCoachSheet()
                    .environment(\.palette, palette)
                    .environment(\.esangActionHandler) { action in
                        eSangRoleDispatcher.dispatch(
                            action,
                            role: session.user?.roleEnum ?? .terminal,
                            dismissSheet: { showeSang = false })
                    }
            }
    }
}

// MARK: - Admin surface

/// Top-level Admin container. Serves both `.admin` and `.superAdmin`
/// roles — the registered Admin screens (800-803) gate their own
/// sensitive features (tenant impersonation, etc.) at the screen
/// level via session-role checks. RBAC at the surface level is the
/// outer guard via `RoleAccess.canRender(role:.admin)`.
struct AdminSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    @State private var screenStack: [String] = ["800"]
    @State private var showeSang: Bool = false
    /// Shared sheet→push detail layer (NAV remediation 2026-05-30).
    @State private var pushedDetail: RoleDetailPush? = nil
    // tabRoots must equal the 4 BottomNav slot destinations. The Admin
    // bottom-nav (800 Home / Tickets / Tenants / Me) resolves through
    // `AdminNavRoute.map`:
    //   home→800 · tickets→801 · tenants→802 · me→804.
    // All four ids below are registered admin screens and match the map
    // verbatim — Me resolves to the dedicated 804 Admin Me hub (it no
    // longer collapses onto 800 Home as an older revision of this comment
    // claimed). 803 (Tenant Detail) is a push-detail drill from 802, not
    // a slot. Keep this set in lockstep with `AdminNavRoute.map`.
    // (Comment re-verified against shipped code 2026-06-09.)
    private static let tabRoots: Set<String> = ["800", "801", "802", "804"]

    private var currentScreenId: String { screenStack.last ?? "800" }

    private var current: ProductionScreen {
        ScreenRegistry.forRole(.admin).first { $0.id == currentScreenId }
            ?? ScreenRegistry.forRole(.admin).first { $0.id == "800" }
            ?? ScreenRegistry.forRole(.admin).first
            ?? ProductionScreen(id: "800",
                                title: "Admin · Home",
                                role: .admin) { p in
                                    AnyView(AdminHomeScreen(theme: p))
                                }
    }

    private func pushOrTab(_ id: String) {
        if Self.tabRoots.contains(id) { screenStack = [id]; return }
        if screenStack.last == id { return }
        screenStack.append(id)
    }
    private func popOne() { if screenStack.count > 1 { screenStack.removeLast() } }

    private var roleDock: RoleDockContract {
        RoleDockCatalog.admin(
            active: screenStack.first ?? "800",
            select: { destination in
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(destination) }
            },
            openESang: { showeSang = true }
        )
    }

    var body: some View {
        current.view(palette)
            .id("admin-\(currentScreenId)")
            .eusoRefreshSurface("admin:\(currentScreenId)")
            .transition(.opacity)
            .modifier(RoleNavBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId,
                screensWithOwnBack: Self.tabRoots
            ))
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler, nil)
            .environment(\.adminNavHandler) { label in
                AdminNavDispatcher.handle(label)
            }
            .environment(\.roleDockContract, roleDock)
            .modifier(RoleDetailLayer(
                pushedDetail: $pushedDetail,
                palette: palette,
                onBack: {
                    NotificationCenter.default.post(
                        name: .eusoRoleNavBack, object: nil)
                }
            ))
            .onReceive(NotificationCenter.default.publisher(for: .eusoAdminNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .admin, screenId: id) else {
                    screenStack = ["800"]; return
                }
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                if pushedDetail != nil {
                    withAnimation(.easeInOut(duration: 0.28)) { pushedDetail = nil }
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) { popOne() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoAdmineSangTapped)) { _ in
                showeSang = true
            }
            .fullScreenCover(isPresented: $showeSang) {
                DrivereSangCoachSheet()
                    .environment(\.palette, palette)
                    .environment(\.esangActionHandler) { action in
                        eSangRoleDispatcher.dispatch(
                            action,
                            role: session.user?.roleEnum ?? .admin,
                            dismissSheet: { showeSang = false })
                    }
            }
    }
}

// MARK: - Dispatch surface

/// Top-level Dispatch container. Mirror of Shipper / Carrier / Broker /
/// Escort / Terminal / Admin / Compliance surfaces. RBAC-gated through
/// `RoleAccess.canRender(role:.dispatch)`.
struct DispatchSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    @State private var screenStack: [String] = ["Disp400"]
    @State private var showeSang: Bool = false
    /// Shared sheet→push detail layer (NAV remediation 2026-05-30).
    @State private var pushedDetail: RoleDetailPush? = nil
    // tabRoots must equal the 4 BottomNav slot destinations. The Dispatch
    // bottom-nav (700 Home / Drivers / Loads / Me) resolves through
    // `DispatchNavRoute.map`:
    //   home→Dpch700 · drivers→Dpch701 · loads→Dpch702 · me→Dpch713.
    // The previous literal listed Dpch703 (Exception Triage) — not a
    // bottom-nav slot — and omitted the Me slot (Dpch713, the dedicated
    // Dispatch Me hub added 2026-05-21). With Dpch713 absent the Me tab
    // never reset to its root. Corrected to the real slot set.
    // (IA recon 2026-05-30.)
    // 2026-06-02 — canonical dispatcher nav promoted to the 400/401/405
    // SVG taxonomy (Home/Board/Comms/Me). Slots: Disp400 live-desk home,
    // Disp401 lifecycle kanban (Board), Dpch721 Comms Hub (Comms), Dpch713
    // Me. The voided 700-series Drivers/Loads invention is retired;
    // Dpch701 (drivers) + Dpch702 (loads) stay reachable via the Me hub.
    private static let tabRoots: Set<String> = ["Disp400", "Disp401", "Dpch721", "Dpch713"]
    /// Dispatch leaves with their own visible Back/Cancel affordance. Without
    /// this set the shared role overlay paints a second chevron above the
    /// screen, producing the double-back bug reported from TestFlight.
    private static let screensWithOwnBack: Set<String> = tabRoots.union([
        "Dpch724", "Dpch725", "Dpch731",
    ])

    private var currentScreenId: String { screenStack.last ?? "Disp400" }

    private var current: ProductionScreen {
        ScreenRegistry.forRole(.dispatch).first { $0.id == currentScreenId }
            ?? ScreenRegistry.forRole(.dispatch).first { $0.id == "Disp400" }
            ?? ScreenRegistry.forRole(.dispatch).first
            ?? ProductionScreen(id: "Disp400",
                                title: "Dispatch · Home",
                                role: .dispatch) { p in
                                    AnyView(DispatcherHomeScreen(theme: p))
                                }
    }

    private func pushOrTab(_ id: String) {
        if Self.tabRoots.contains(id) { screenStack = [id]; return }
        if screenStack.last == id { return }
        screenStack.append(id)
    }
    private func popOne() { if screenStack.count > 1 { screenStack.removeLast() } }

    private var roleDock: RoleDockContract {
        RoleDockCatalog.dispatch(
            active: screenStack.first ?? "Disp400",
            select: { destination in
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(destination) }
            },
            openESang: { showeSang = true }
        )
    }

    var body: some View {
        current.view(palette)
            .id("dispatch-\(currentScreenId)")
            .eusoRefreshSurface("dispatch:\(currentScreenId)")
            .transition(.opacity)
            .modifier(RoleNavBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId,
                screensWithOwnBack: Self.screensWithOwnBack
            ))
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler, nil)
            .environment(\.dispatchNavHandler) { label in
                DispatchNavDispatcher.handle(label)
            }
            .environment(\.roleDockContract, roleDock)
            .modifier(RoleDetailLayer(
                pushedDetail: $pushedDetail,
                palette: palette,
                onBack: {
                    NotificationCenter.default.post(
                        name: .eusoRoleNavBack, object: nil)
                }
            ))
            .onReceive(NotificationCenter.default.publisher(for: .eusoDispatchNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .dispatch, screenId: id) else {
                    screenStack = ["Disp400"]; return
                }
                if let driverId = stringPayload(note.userInfo, "driverId") {
                    BrokerNavContext.latestDriverId = driverId
                }
                if let loadId = stringPayload(note.userInfo, "loadId") {
                    BrokerNavContext.latestLoadId = loadId
                }
                if let loadNumber = stringPayload(note.userInfo, "loadNumber") {
                    BrokerNavContext.latestLoadNumber = loadNumber
                }
                if let catalystId = stringPayload(note.userInfo, "catalystId") {
                    BrokerNavContext.latestCatalystId = catalystId
                }
                if let shipperId = stringPayload(note.userInfo, "shipperId") {
                    BrokerNavContext.latestShipperId = shipperId
                }
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                if pushedDetail != nil {
                    withAnimation(.easeInOut(duration: 0.28)) { pushedDetail = nil }
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) { popOne() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoDispatcheSangTapped)) { _ in
                showeSang = true
            }
            .fullScreenCover(isPresented: $showeSang) {
                DrivereSangCoachSheet()
                    .environment(\.palette, palette)
                    .environment(\.esangActionHandler) { action in
                        eSangRoleDispatcher.dispatch(
                            action,
                            role: session.user?.roleEnum ?? .dispatch,
                            dismissSheet: { showeSang = false })
                    }
            }
    }

    private func stringPayload(_ userInfo: [AnyHashable: Any]?, _ key: String) -> String? {
        guard let raw = userInfo?[key] else { return nil }
        if let value = raw as? String, !value.isEmpty { return value }
        if let value = raw as? Int { return String(value) }
        if let value = raw as? Int64 { return String(value) }
        if let value = raw as? Double, value.isFinite { return String(Int(value)) }
        return nil
    }
}

// MARK: - Compliance surface

/// Top-level Compliance Officer container. Mirror of Shipper /
/// Carrier / Broker / Escort / Terminal / Admin surfaces. RBAC-gated
/// through `RoleAccess.canRender(role:.compliance)`.
struct ComplianceSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    @State private var screenStack: [String] = ["900"]
    @State private var showeSang: Bool = false
    /// Shared sheet→push detail layer (NAV remediation 2026-05-30).
    @State private var pushedDetail: RoleDetailPush? = nil
    // tabRoots must equal the 4 BottomNav slot destinations. The Compliance
    // bottom-nav (900 Home / Drivers / Audits / Me) resolves through
    // `ComplianceNavRoute.map`:
    //   home→900 · drivers→901 · audits→902 · me→903.
    // All four ids below are registered compliance screens and match the
    // map verbatim — Me resolves to the dedicated 903 Compliance Me hub
    // (903 IS registered now; an older revision of this comment called it
    // a phantom and claimed Me collapsed onto 900 Home). Keep this set in
    // lockstep with `ComplianceNavRoute.map`.
    // (Comment re-verified against shipped code 2026-06-09.)
    private static let tabRoots: Set<String> = ["900", "901", "902", "903"]

    private var currentScreenId: String { screenStack.last ?? "900" }

    private var current: ProductionScreen {
        ScreenRegistry.forRole(.compliance).first { $0.id == currentScreenId }
            ?? ScreenRegistry.forRole(.compliance).first { $0.id == "900" }
            ?? ScreenRegistry.forRole(.compliance).first
            ?? ProductionScreen(id: "900",
                                title: "Compliance · Home",
                                role: .compliance) { p in
                                    AnyView(ComplianceOfficerHomeScreen(theme: p))
                                }
    }

    private func pushOrTab(_ id: String) {
        if Self.tabRoots.contains(id) { screenStack = [id]; return }
        if screenStack.last == id { return }
        screenStack.append(id)
    }
    private func popOne() { if screenStack.count > 1 { screenStack.removeLast() } }

    private var roleDock: RoleDockContract {
        RoleDockCatalog.compliance(
            active: screenStack.first ?? "900",
            select: { destination in
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(destination) }
            },
            openESang: { showeSang = true }
        )
    }

    var body: some View {
        current.view(palette)
            .id("compliance-\(currentScreenId)")
            .eusoRefreshSurface("compliance:\(currentScreenId)")
            .transition(.opacity)
            .modifier(RoleNavBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId,
                screensWithOwnBack: Self.tabRoots
            ))
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler, nil)
            .environment(\.complianceNavHandler) { label in
                ComplianceNavDispatcher.handle(label)
            }
            .environment(\.roleDockContract, roleDock)
            .modifier(RoleDetailLayer(
                pushedDetail: $pushedDetail,
                palette: palette,
                onBack: {
                    NotificationCenter.default.post(
                        name: .eusoRoleNavBack, object: nil)
                }
            ))
            .onReceive(NotificationCenter.default.publisher(for: .eusoComplianceNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .compliance, screenId: id) else {
                    screenStack = ["900"]; return
                }
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                if pushedDetail != nil {
                    withAnimation(.easeInOut(duration: 0.28)) { pushedDetail = nil }
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) { popOne() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoComplianceeSangTapped)) { _ in
                showeSang = true
            }
            .fullScreenCover(isPresented: $showeSang) {
                DrivereSangCoachSheet()
                    .environment(\.palette, palette)
                    .environment(\.esangActionHandler) { action in
                        eSangRoleDispatcher.dispatch(
                            action,
                            role: session.user?.roleEnum ?? .compliance,
                            dismissSheet: { showeSang = false })
                    }
            }
    }
}

// MARK: - Shared native mode-role surface

/// Native container for rail and vessel roles whose strongest existing iOS
/// workspaces live in the shared mode registry. The definition is an exact
/// role allowlist: child-screen notifications can never broaden the catalog or
/// replace the role's four dock destinations.
@MainActor
struct NativeModeRoleSurface: View {
    let definition: NativeModeRoleDefinition
    let palette: Theme.Palette

    @EnvironmentObject private var session: EusoTripSession
    @State private var screenStack: [String]
    @State private var showeSang = false
    @State private var pushedDetail: RoleDetailPush?
    @State private var routeError: String?

    init(definition: NativeModeRoleDefinition, palette: Theme.Palette) {
        self.definition = definition
        self.palette = palette
        _screenStack = State(initialValue: [definition.home.destinationId])
    }

    private var currentScreenId: String {
        screenStack.last ?? definition.home.destinationId
    }

    private var currentView: AnyView {
        if currentScreenId == definition.home.destinationId {
            return AnyView(NativeModeRoleHome(
                definition: definition,
                palette: palette,
                open: selectDockDestination
            ))
        }
        if currentScreenId == definition.me.destinationId {
            return AnyView(NativeModeRoleMe(
                definition: definition,
                palette: palette
            ))
        }
        guard definition.allowedRoutes.contains(currentScreenId),
              let screen = ScreenRegistry.forRole(definition.registryRole)
                .first(where: { $0.id == currentScreenId }) else {
            return AnyView(NativeModeRouteUnavailable(
                definition: definition,
                palette: palette,
                returnHome: { selectDockDestination(definition.home.destinationId) }
            ))
        }
        return screen.view(palette)
    }

    private var swapNotification: Notification.Name {
        switch definition.mode {
        case .rail: return .eusoRailNavSwap
        case .vessel: return .eusoVesselNavSwap
        }
    }

    private var railNavigation: ((String) -> Void)? {
        guard definition.mode == .rail else { return nil }
        return { label in RailEngineerNavDispatcher.handle(label) }
    }

    private var vesselNavigation: ((String) -> Void)? {
        guard definition.mode == .vessel else { return nil }
        return { label in VesselOperatorNavDispatcher.handle(label) }
    }

    private var roleDock: RoleDockContract {
        RoleDockCatalog.nativeModeRole(
            definition: definition,
            active: screenStack.first ?? definition.home.destinationId,
            select: { destination in selectDockDestination(destination) },
            openESang: { showeSang = true }
        )
    }

    var body: some View {
        currentView
            .id("native-mode-role-\(definition.role.rawValue)-\(currentScreenId)")
            .eusoRefreshSurface("native-mode-role:\(definition.role.rawValue):\(currentScreenId)")
            .modifier(RoleNavBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId,
                screensWithOwnBack: definition.screensWithOwnBack.union(definition.tabRoots)
            ))
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler, nil)
            .environment(\.vesselShipperNavHandler, nil)
            .environment(\.railEngineerNavHandler, railNavigation)
            .environment(\.vesselOperatorNavHandler, vesselNavigation)
            .environment(\.roleDockContract, roleDock)
            .modifier(RoleDetailLayer(
                pushedDetail: $pushedDetail,
                palette: palette,
                onBack: {
                    NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
                }
            ))
            .onReceive(NotificationCenter.default.publisher(for: swapNotification)) { note in
                guard let screenId = note.userInfo?["screenId"] as? String else { return }
                openNotificationRoute(screenId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                if pushedDetail != nil {
                    withAnimation(.easeInOut(duration: 0.28)) { pushedDetail = nil }
                } else if screenStack.count > 1 {
                    withAnimation(.easeInOut(duration: 0.22)) { screenStack.removeLast() }
                }
            }
            .fullScreenCover(isPresented: $showeSang) {
                DrivereSangCoachSheet()
                    .environment(\.palette, palette)
                    .environmentObject(session)
                    .environment(\.esangActionHandler) { action in
                        eSangRoleDispatcher.dispatch(
                            action,
                            role: definition.role,
                            dismissSheet: { showeSang = false }
                        )
                    }
            }
            .alert("Route unavailable", isPresented: Binding(
                get: { routeError != nil },
                set: { if !$0 { routeError = nil } }
            )) {
                Button("OK", role: .cancel) { routeError = nil }
            } message: {
                Text(routeError ?? "")
            }
    }

    private func selectDockDestination(_ destination: String) {
        guard definition.tabRoots.contains(destination) else {
            routeError = "That destination is not assigned to the \(definition.role.displayName) dock."
            return
        }
        pushedDetail = nil
        withAnimation(.easeInOut(duration: 0.22)) {
            screenStack = [destination]
        }
    }

    private func openNotificationRoute(_ screenId: String) {
        guard definition.allowedRoutes.contains(screenId),
              ScreenRegistry.forRole(definition.registryRole)
                .contains(where: { $0.id == screenId }) else {
            routeError = "Open this item from its record so EusoTrip can preserve the required context."
            return
        }
        pushedDetail = nil
        withAnimation(.easeInOut(duration: 0.22)) {
            if definition.tabRoots.contains(screenId) {
                screenStack = [screenId]
            } else if screenStack.last != screenId {
                screenStack.append(screenId)
            }
        }
    }
}

@MainActor
private struct NativeModeRoleHome: View {
    let definition: NativeModeRoleDefinition
    let palette: Theme.Palette
    let open: (String) -> Void

    @EnvironmentObject private var session: EusoTripSession

    private var displayName: String {
        let value = session.user?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? definition.role.displayName : value
    }

    var body: some View {
        Shell(theme: palette) {
            VStack(alignment: .leading, spacing: Space.s5) {
                Spacer().frame(height: Space.s5)
                EusoTripEyebrow(verbatim: "\(definition.role.displayName.uppercased()) · HOME")
                Text("Welcome, \(displayName)")
                    .font(EType.h1)
                    .foregroundStyle(palette.textPrimary)
                Text(session.user?.email ?? "")
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)

                if let companyId = session.user?.companyId, !companyId.isEmpty {
                    Label("Company \(companyId)", systemImage: "building.2.fill")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }

                Text("WORKSPACES")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, Space.s3)

                workspaceButton(definition.workOne)
                workspaceButton(definition.workTwo)
                if definition.role == .portMaster {
                    workspaceButton(.init(
                        destinationId: "Vesl822",
                        label: "Register container",
                        systemImage: "shippingbox.fill"
                    ))
                } else if definition.role == .shipCaptain {
                    workspaceButton(.init(
                        destinationId: "Vesl822",
                        label: "Bunker delivery",
                        systemImage: "fuelpump.fill"
                    ))
                }
            }
            .padding(.horizontal, Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        } nav: {
            EmptyView()
        }
    }

    private func workspaceButton(_ item: RoleDockItem) -> some View {
        Button { open(item.destinationId) } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                Text(item.label)
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct NativeModeRoleMe: View {
    let definition: NativeModeRoleDefinition
    let palette: Theme.Palette

    @EnvironmentObject private var session: EusoTripSession

    var body: some View {
        Shell(theme: palette) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    Spacer().frame(height: Space.s5)
                    EusoTripEyebrow(verbatim: "\(definition.role.displayName.uppercased()) · ME")
                    Text("Account")
                        .font(EType.h1)
                        .foregroundStyle(palette.textPrimary)

                    VStack(alignment: .leading, spacing: Space.s3) {
                        Label(session.user?.name ?? definition.role.displayName,
                              systemImage: definition.role.iconSystemName)
                        Label(session.user?.email ?? "", systemImage: "envelope.fill")
                        if let companyId = session.user?.companyId, !companyId.isEmpty {
                            Label("Company \(companyId)", systemImage: "building.2.fill")
                        }
                    }
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .padding(Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                    EusoCardIssuePanel(
                        title: "\(definition.role.displayName) EusoCard",
                        subtitle: "Operational spend card backed by EusoWallet Treasury"
                    )

                    Button {
                        Task { await session.signOut() }
                    } label: {
                        Text("Sign out")
                            .font(EType.bodyStrong)
                            .foregroundStyle(Brand.danger)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(palette.bgCardSoft)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } nav: {
            EmptyView()
        }
    }
}

@MainActor
private struct NativeModeRouteUnavailable: View {
    let definition: NativeModeRoleDefinition
    let palette: Theme.Palette
    let returnHome: () -> Void

    var body: some View {
        Shell(theme: palette) {
            VStack(spacing: Space.s4) {
                Spacer().frame(height: Space.s8)
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                Text("Route unavailable")
                    .font(EType.h2)
                    .foregroundStyle(palette.textPrimary)
                Text("This screen is not assigned to the \(definition.role.displayName) workspace.")
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Return Home", action: returnHome)
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .padding(.horizontal, Space.s5)
        } nav: {
            EmptyView()
        }
    }
}

// MARK: - Rail Engineer surface

/// Top-level Rail Engineer container. First native iOS Rail surface.
/// RBAC-gated through `RoleAccess.canRender(role:.railEngineer)`.
struct RailEngineerSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    @State private var screenStack: [String] = ["Rail550"]
    @State private var showeSang: Bool = false
    /// Shared sheet→push detail layer (NAV remediation 2026-05-30).
    @State private var pushedDetail: RoleDetailPush? = nil
    // tabRoots must equal the set of screen IDs the 4 BottomNav slots
    // actually navigate to. The Rail bottom-nav (550 Home / Shipments /
    // Compliance / Me) resolves through `RailEngineerNavRoute.map`:
    //   home→Rail550 · shipments→Rail551 · compliance→Rail552 · me→Rail550.
    // The previous literal listed Rail553 — a deepMap-only Shipment Detail
    // screen that NO bottom-nav slot reaches — and omitted nothing else
    // (Me resolves to Rail550, already present). Rail553 as a phantom
    // tab-root made the back chevron wrongly suppress when drilled into
    // 553 and corrupted tab-reset semantics. Corrected to the 3 distinct
    // slot destinations. (IA recon 2026-05-30.)
    private static let tabRoots: Set<String> = ["Rail550", "Rail551", "Rail552", "Rail556"]

    private var currentScreenId: String { screenStack.last ?? "Rail550" }

    private var current: ProductionScreen {
        ScreenRegistry.forRole(.railEngineer).first { $0.id == currentScreenId }
            ?? ScreenRegistry.forRole(.railEngineer).first { $0.id == "Rail550" }
            ?? ScreenRegistry.forRole(.railEngineer).first
            ?? ProductionScreen(id: "Rail550",
                                title: "Rail Engineer · Home",
                                role: .railEngineer) { p in
                                    AnyView(RailEngineerHomeScreen(theme: p))
                                }
    }

    private func pushOrTab(_ id: String) {
        if Self.tabRoots.contains(id) { screenStack = [id]; return }
        if screenStack.last == id { return }
        screenStack.append(id)
    }
    private func popOne() { if screenStack.count > 1 { screenStack.removeLast() } }

    private var roleDock: RoleDockContract {
        RoleDockCatalog.railEngineer(
            active: screenStack.first ?? "Rail550",
            select: { destination in
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(destination) }
            },
            openESang: { showeSang = true }
        )
    }

    var body: some View {
        current.view(palette)
            .id("rail-\(currentScreenId)")
            .eusoRefreshSurface("rail-engineer:\(currentScreenId)")
            .transition(.opacity)
            .modifier(RoleNavBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId,
                screensWithOwnBack: Self.tabRoots
            ))
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler, nil)
            .environment(\.railEngineerNavHandler) { label in
                RailEngineerNavDispatcher.handle(label)
            }
            .environment(\.roleDockContract, roleDock)
            .modifier(RoleDetailLayer(
                pushedDetail: $pushedDetail,
                palette: palette,
                onBack: {
                    NotificationCenter.default.post(
                        name: .eusoRoleNavBack, object: nil)
                }
            ))
            .onReceive(NotificationCenter.default.publisher(for: .eusoRailNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .railEngineer, screenId: id) else {
                    screenStack = ["Rail550"]; return
                }
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                if pushedDetail != nil {
                    withAnimation(.easeInOut(duration: 0.28)) { pushedDetail = nil }
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) { popOne() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRaileSangTapped)) { _ in
                showeSang = true
            }
            .fullScreenCover(isPresented: $showeSang) {
                DrivereSangCoachSheet()
                    .environment(\.palette, palette)
                    .environment(\.esangActionHandler) { action in
                        eSangRoleDispatcher.dispatch(
                            action,
                            role: session.user?.roleEnum ?? .railEngineer,
                            dismissSheet: { showeSang = false })
                    }
            }
    }
}

// MARK: - Vessel Shipper surface

/// Owns Vessel Shipper navigation, selected-booking context, and the shared
/// edge-swipe/detail stack. Mounting `VesselShipperHomeScreen` directly left
/// every BottomNav event without a history owner and made all drill-ins dead.
struct VesselShipperSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject private var session: EusoTripSession
    @State private var screenStack = ["Vesl001"]
    @SceneStorage("EusoTrip.vesselShipper.activeShipmentId") private var activeShipmentId = 0
    @SceneStorage("EusoTrip.vesselShipper.activeBookingNumber") private var activeBookingNumber = ""
    @State private var showeSang = false
    @State private var pushedDetail: RoleDetailPush?
    @State private var contextResolving = false
    @State private var contextRecoveryMessage: String?

    private static let tabRoots: Set<String> = [
        "Vesl001", "Vesl011", "Vesl012", "320",
    ]

    private static let vesselRoutes: Set<String> = [
        "Vesl001", "Vesl002", "Vesl003", "Vesl004", "Vesl006",
        "Vesl010", "Vesl011", "Vesl012",
    ]

    /// Vessel Shippers share identity, wallet, partner, document, support, and
    /// account controls with the Shipper registry. Build this allow-list from
    /// the live Me catalog so newly added rows cannot become silent dead taps.
    private static let sharedMeRoutes: Set<String> = {
        var ids: Set<String> = [
            "320", "320a", "320b", "320c", "320d", "320e", "320f", "320g",
        ]
        let catalogs = [
            MeHubCatalog.account,
            MeHubCatalog.wallet,
            MeHubCatalog.operations,
            MeHubCatalog.network,
            MeHubCatalog.compliance,
        ]
        for sections in catalogs {
            for section in sections {
                for cell in section.cells {
                    if case .screen(let id) = cell.action { ids.insert(id) }
                }
            }
        }
        // Settings uses its own local catalog in `MeSettingsHubBody`.
        ids.formUnion(["211", "319", "340", "343", "347", "348", "PULSE"])
        return ids
    }()

    private static let screensWithOwnBack: Set<String> = [
        "Vesl010", "320a", "320b", "320c", "320d", "320e", "320f", "320g",
    ]

    private var currentScreenId: String { screenStack.last ?? "Vesl001" }

    private var current: ProductionScreen {
        switch currentScreenId {
        case "Vesl001":
            return ProductionScreen(id: "Vesl001", title: "Vessel Shipper · Home", role: .shipper) { p in
                AnyView(VesselShipperHomeScreen(theme: p))
            }
        case "Vesl002":
            guard activeShipmentId > 0 else {
                return ProductionScreen(id: "Vesl011", title: "Vessel Shipper · Bookings", role: .shipper) { p in
                    AnyView(VesselShipperBookingsScreen(theme: p))
                }
            }
            return ProductionScreen(id: "Vesl002", title: "Vessel Shipper · Booking Detail", role: .shipper) { p in
                AnyView(VesselBookingDetailScreen(theme: p, shipmentId: activeShipmentId))
            }
        case "Vesl003":
            guard !activeBookingNumber.isEmpty else {
                return ProductionScreen(id: "Vesl012", title: "Vessel Shipper · Tracking", role: .shipper) { p in
                    AnyView(VesselShipperTrackingLookupScreen(theme: p))
                }
            }
            return ProductionScreen(id: "Vesl003", title: "Vessel Shipper · Live Tracking", role: .shipper) { p in
                AnyView(VesselLiveTrackingScreen(theme: p, bookingNumber: activeBookingNumber))
            }
        case "Vesl004":
            guard activeShipmentId > 0 else {
                return ProductionScreen(id: "Vesl011", title: "Vessel Shipper · Bookings", role: .shipper) { p in
                    AnyView(VesselShipperBookingsScreen(theme: p))
                }
            }
            return ProductionScreen(id: "Vesl004", title: "Vessel Shipper · Demurrage & Detention", role: .shipper) { p in
                AnyView(VesselDemurrageDetentionScreen(theme: p, shipmentId: activeShipmentId))
            }
        case "Vesl006":
            return ProductionScreen(id: "Vesl006", title: "Vessel Shipper · Customs", role: .shipper) { p in
                AnyView(VesselCustomsISFScreen(theme: p))
            }
        case "Vesl010":
            return ProductionScreen(id: "Vesl010", title: "Vessel Shipper · Create Booking", role: .shipper) { p in
                AnyView(VesselShipperCreateBookingScreen(theme: p))
            }
        case "Vesl011":
            return ProductionScreen(id: "Vesl011", title: "Vessel Shipper · Bookings", role: .shipper) { p in
                AnyView(VesselShipperBookingsScreen(theme: p))
            }
        case "Vesl012":
            return ProductionScreen(id: "Vesl012", title: "Vessel Shipper · Tracking", role: .shipper) { p in
                AnyView(VesselShipperTrackingLookupScreen(theme: p))
            }
        default:
            if Self.sharedMeRoutes.contains(currentScreenId),
               let screen = ScreenRegistry.forRole(.shipper).first(where: { $0.id == currentScreenId }) {
                return screen
            }
            return ProductionScreen(id: "Vesl001", title: "Vessel Shipper · Home", role: .shipper) { p in
                AnyView(VesselShipperHomeScreen(theme: p))
            }
        }
    }

    private var currentIdentity: String {
        switch currentScreenId {
        case "Vesl002", "Vesl004":
            return "vessel-shipper-\(currentScreenId)-\(activeShipmentId)"
        case "Vesl003":
            return "vessel-shipper-Vesl003-\(activeBookingNumber.isEmpty ? "missing" : activeBookingNumber)"
        default:
            return "vessel-shipper-\(currentScreenId)"
        }
    }

    private var roleDock: RoleDockContract {
        RoleDockCatalog.vesselShipper(
            active: screenStack.first ?? "Vesl001",
            select: { destination in
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(destination) }
            },
            openESang: { showeSang = true }
        )
    }

    var body: some View {
        current.view(palette)
            .id(currentIdentity)
            .eusoRefreshSurface("vessel-shipper:\(currentIdentity)")
            .transition(.opacity)
            .modifier(RoleNavBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId,
                screensWithOwnBack: Self.screensWithOwnBack.union(Self.tabRoots)
            ))
            .modifier(RoleDetailLayer(
                pushedDetail: $pushedDetail,
                palette: palette,
                onBack: {
                    NotificationCenter.default.post(name: .eusoVesselShipperNavBack, object: nil)
                }
            ))
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler, nil)
            .environment(\.vesselOperatorNavHandler, nil)
            .environment(\.vesselShipperNavHandler) { label in
                VesselShipperNavDispatcher.handle(label)
            }
            .environment(\.roleDockContract, roleDock)
            .overlay(alignment: .topTrailing) {
                if contextResolving {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, Device.safeTop + Space.s3)
                        .padding(.trailing, Space.s4)
                        .accessibilityLabel("Verifying vessel booking")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoVesselShipperNavSwap)) { note in
                handleVesselSwap(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperNavSwap)) { note in
                handleSharedMeSwap(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoVesselShipperNavBack)) { _ in
                popOneLevel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                popOneLevel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperNavBack)) { _ in
                popOneLevel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoVesselShippereSangTapped)) { _ in
                showeSang = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShippereSangTapped)) { _ in
                showeSang = true
            }
            .alert("Choose a vessel booking", isPresented: Binding(
                get: { contextRecoveryMessage != nil },
                set: { if !$0 { contextRecoveryMessage = nil } }
            )) {
                Button("OK", role: .cancel) { contextRecoveryMessage = nil }
            } message: {
                Text(contextRecoveryMessage ?? "")
            }
            .fullScreenCover(isPresented: $showeSang) {
                ShippereSangCoachSheet()
                    .environment(\.palette, palette)
                    .environmentObject(session)
                    .environment(\.esangActionHandler) { action in
                        eSangRoleDispatcher.dispatch(
                            action,
                            role: .vesselShipper,
                            dismissSheet: { showeSang = false }
                        )
                    }
            }
    }

    private func handleVesselSwap(_ note: Notification) {
        guard let id = note.userInfo?["screenId"] as? String,
              Self.vesselRoutes.contains(id) || Self.sharedMeRoutes.contains(id) else {
            return
        }
        if ["Vesl002", "Vesl003", "Vesl004"].contains(id) {
            let requestedShipmentId = Self.positiveInteger(note.userInfo?["shipmentId"])
            let requestedBookingNumber = Self.nonemptyString(note.userInfo?["bookingNumber"])
            let hasFreshContext = requestedShipmentId != nil || requestedBookingNumber != nil
            let shipmentId = requestedShipmentId ?? (hasFreshContext || activeShipmentId <= 0 ? nil : activeShipmentId)
            let bookingNumber = requestedBookingNumber
                ?? (hasFreshContext || activeBookingNumber.isEmpty ? nil : activeBookingNumber)
            Task {
                await resolveBookingContextAndNavigate(
                    target: id,
                    shipmentId: shipmentId,
                    bookingNumber: bookingNumber
                )
            }
            return
        }
        pushedDetail = nil
        withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
    }

    @MainActor
    private func resolveBookingContextAndNavigate(
        target: String,
        shipmentId: Int?,
        bookingNumber: String?
    ) async {
        guard shipmentId != nil || bookingNumber != nil else {
            routeToBookingPicker(for: target, message: nil)
            return
        }

        struct Input: Encodable {
            let shipmentId: Int?
            let bookingNumber: String?
        }
        struct Output: Decodable {
            let found: Bool
            let shipmentId: Int?
            let bookingNumber: String?
            let canTrack: Bool?
        }

        contextResolving = true
        defer { contextResolving = false }
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let resolved: Output = try await EusoTripAPI.shared.query(
                    "vesselShipments.resolveVesselBookingContext",
                    input: Input(shipmentId: shipmentId, bookingNumber: bookingNumber)
                )
                guard resolved.found, let resolvedId = resolved.shipmentId, resolvedId > 0 else {
                    routeToBookingPicker(
                        for: target,
                        message: "Your live vessel bookings are refreshed. Choose the booking you want to continue with."
                    )
                    return
                }

                let resolvedNumber = resolved.bookingNumber?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if target == "Vesl003" && (resolved.canTrack != true || resolvedNumber.isEmpty) {
                    routeToBookingPicker(
                        for: target,
                        message: "This booking is yours, but its live tracking reference is not active yet. Choose another booking or open its details."
                    )
                    return
                }

                activeShipmentId = resolvedId
                activeBookingNumber = resolvedNumber
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(target) }
                return
            } catch {
                lastError = error
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                }
            }
        }

        routeToBookingPicker(
            for: target,
            message: "Your own booking list is open so you can continue. \(lastError?.eusoUserCopy ?? "")"
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    @MainActor
    private func routeToBookingPicker(for target: String, message: String?) {
        pushedDetail = nil
        let recoveryRoot = target == "Vesl003" ? "Vesl012" : "Vesl011"
        withAnimation(.easeInOut(duration: 0.22)) { screenStack = [recoveryRoot] }
        contextRecoveryMessage = message
    }

    private func handleSharedMeSwap(_ note: Notification) {
        guard let id = note.userInfo?["screenId"] as? String else { return }
        if id == "_logout" {
            NotificationCenter.default.post(name: Notification.Name("eusoLogoutRequested"), object: nil)
            return
        }
        guard Self.sharedMeRoutes.contains(id),
              RoleAccess.canRender(role: .vesselShipper, screenId: id) else {
            return
        }
        pushedDetail = nil
        withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
    }

    private func pushOrTab(_ id: String) {
        if Self.tabRoots.contains(id) {
            screenStack = [id]
        } else if screenStack.last != id {
            screenStack.append(id)
        }
    }

    private func popOneLevel() {
        if pushedDetail != nil {
            withAnimation(.easeInOut(duration: 0.28)) { pushedDetail = nil }
        } else if screenStack.count > 1 {
            withAnimation(.easeInOut(duration: 0.22)) { screenStack.removeLast() }
        }
    }

    private static func positiveInteger(_ value: Any?) -> Int? {
        if let value = value as? Int, value > 0 { return value }
        if let value = value as? String,
           let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
           parsed > 0 { return parsed }
        return nil
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

// MARK: - Vessel Operator surface

/// Top-level Vessel Operator container. First native iOS Vessel surface.
/// RBAC-gated through `RoleAccess.canRender(role:.vesselOperator)`.
struct VesselOperatorSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    @State private var screenStack: [String] = ["Vesl650"]
    @State private var showeSang: Bool = false
    /// Shared sheet→push detail layer (NAV remediation 2026-05-30).
    @State private var pushedDetail: RoleDetailPush? = nil
    // tabRoots must equal the 4 BottomNav slot destinations. The Vessel
    // bottom-nav (650 Home / Shipments / Compliance / Me) resolves through
    // `VesselOperatorNavRoute.map`:
    //   home→Vesl650 · shipments→Vesl651 · compliance→Vesl652 · me→Vesl650.
    // The previous literal listed Vesl653 — a deepMap-only Booking Detail
    // screen that NO bottom-nav slot reaches. Me resolves to Vesl650 (Home),
    // already present. Corrected to the 3 distinct slot destinations.
    // Vesl653 remains in `screensWithOwnBack` below (explicit union), so its
    // back-chevron behavior is unchanged. (IA recon 2026-05-30.)
    private static let tabRoots: Set<String> = ["Vesl650", "Vesl651", "Vesl652", "Vesl656"]
    /// Screens that draw their OWN top back affordance (a `BespokeBackBar`
    /// via `.injectBespokeBackBar`) so the surface's `RoleNavBackOverlay`
    /// must NOT paint a second chevron (avoids the founder-hated double
    /// back). 653/654/655/657 each replaced their decorative header chevron
    /// with a real `BespokeBackBar` (NAV remediation 2026-05-30, Wave 3).
    private static let screensWithOwnBack: Set<String> =
        tabRoots.union(["Vesl653", "Vesl654", "Vesl655", "Vesl657"])

    private var currentScreenId: String { screenStack.last ?? "Vesl650" }

    private var current: ProductionScreen {
        ScreenRegistry.forRole(.vesselOperator).first { $0.id == currentScreenId }
            ?? ScreenRegistry.forRole(.vesselOperator).first { $0.id == "Vesl650" }
            ?? ScreenRegistry.forRole(.vesselOperator).first
            ?? ProductionScreen(id: "Vesl650",
                                title: "Vessel Operator · Home",
                                role: .vesselOperator) { p in
                                    AnyView(VesselOperatorHomeScreen(theme: p))
                                }
    }

    private func pushOrTab(_ id: String) {
        if Self.tabRoots.contains(id) { screenStack = [id]; return }
        if screenStack.last == id { return }
        screenStack.append(id)
    }
    private func popOne() { if screenStack.count > 1 { screenStack.removeLast() } }

    private var roleDock: RoleDockContract {
        RoleDockCatalog.vesselOperator(
            active: screenStack.first ?? "Vesl650",
            select: { destination in
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(destination) }
            },
            openESang: { showeSang = true }
        )
    }

    var body: some View {
        current.view(palette)
            .id("vessel-\(currentScreenId)")
            .eusoRefreshSurface("vessel-operator:\(currentScreenId)")
            .transition(.opacity)
            .modifier(RoleNavBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId,
                screensWithOwnBack: Self.screensWithOwnBack
            ))
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler, nil)
            .environment(\.vesselOperatorNavHandler) { label in
                VesselOperatorNavDispatcher.handle(label)
            }
            .environment(\.roleDockContract, roleDock)
            .modifier(RoleDetailLayer(
                pushedDetail: $pushedDetail,
                palette: palette,
                onBack: {
                    NotificationCenter.default.post(
                        name: .eusoRoleNavBack, object: nil)
                }
            ))
            .onReceive(NotificationCenter.default.publisher(for: .eusoVesselNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .vesselOperator, screenId: id) else {
                    screenStack = ["Vesl650"]; return
                }
                pushedDetail = nil
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                if pushedDetail != nil {
                    withAnimation(.easeInOut(duration: 0.28)) { pushedDetail = nil }
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) { popOne() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoVesseleSangTapped)) { _ in
                showeSang = true
            }
            .fullScreenCover(isPresented: $showeSang) {
                DrivereSangCoachSheet()
                    .environment(\.palette, palette)
                    .environment(\.esangActionHandler) { action in
                        eSangRoleDispatcher.dispatch(
                            action,
                            role: session.user?.roleEnum ?? .vesselOperator,
                            dismissSheet: { showeSang = false })
                    }
            }
    }
}

// MARK: - Shared role-stack back overlay
//
// Founder mandate 2026-05-05 — every leaf screen across every role
// must have a back button that doesn't overlap content. The Shipper
// surface already had this via `ShipperBackOverlay`. Catalyst (Carrier),
// Broker, Escort, Terminal, Admin, Dispatch, and Compliance surfaces
// were single-`currentScreenId` containers with no stack and no back
// affordance — drilling into a leaf screen left the user stranded.
//
// This overlay paints a translucent black-pill chevron at top:8 / leading:12
// (same metrics as `ShipperBackOverlay`) with a 36pt hit-target. It posts
// `.eusoRoleNavBack` on tap; each role surface listens to that single
// notification and pops its own stack. The overlay is suppressed for
// screens that draw their own header back chevron (per-role lists),
// matching the Shipper pattern that prevents the double-back collision.

private struct RoleNavBackOverlay: ViewModifier {
    @Environment(\.eusoRoleDetailPresented) private var detailPresented
    let stackDepth: Int
    let currentScreenId: String
    let screensWithOwnBack: Set<String>

    func body(content: Content) -> some View {
        // 2026-05-22 — same fix as ShipperBackOverlay: switched from
        // .overlay(alignment: .topLeading) to .safeAreaInset so the
        // chevron has its own header band and never sits on top of
        // the screen's eyebrow / title row.
        content.safeAreaInset(edge: .top, spacing: 0) {
            if stackDepth > 1, !screensWithOwnBack.contains(currentScreenId) {
                HStack(spacing: 0) {
                    Button {
                        NotificationCenter.default.post(
                            name: .eusoRoleNavBack, object: nil
                        )
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.55), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .modifier(EusoEdgeSwipeBack(
            isEnabled: stackDepth > 1 && !detailPresented,
            onBack: {
                NotificationCenter.default.post(
                    name: .eusoRoleNavBack, object: nil
                )
            }
        ))
    }
}

// MARK: - Web continuation surface (roles without an iOS surface yet)

/// Production landing for backend roles that do not yet ship a native iOS
/// surface. Loads only App.tsx-verified, role-owned routes in
/// SFSafariViewController and keeps the same four destinations under every
/// continuation screen.
/// Native bearer credentials are not transferred to Safari; the web app may
/// require its own sign-in.
struct WebContinuationSurface: View {
    let role: EusoRole
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    @State private var presentingWeb = false
    @State private var selectedPath = ""
    @State private var activeDestinationId = ""
    @State private var showeSang = false
    @State private var routeError: String?

    private var definition: WebRoleDockDefinition {
        WebRoleDockDefinition.forRole(role)
    }

    private var continuationURL: URL? {
        // Production web app. Keep this as the public domain rather than the
        // Azure backend host because the web SPA + cookies live on eusotrip.com.
        let path = selectedPath.isEmpty ? definition.home.destinationId : selectedPath
        return URL(string: "https://app.eusotrip.com\(path)")
    }

    private var refreshSurfaceID: String {
        "web:\(role.rawValue):\(activeDestinationId.isEmpty ? definition.home.destinationId : activeDestinationId)"
    }

    private var roleDock: RoleDockContract {
        RoleDockCatalog.webContinuation(
            role: role,
            active: activeDestinationId.isEmpty ? definition.home.destinationId : activeDestinationId,
            select: { path in open(path: path, dockDestinationId: path) },
            openESang: { showeSang = true }
        )
    }

    var body: some View {
        Shell(theme: palette) {
            VStack(spacing: Space.s5) {
                Spacer().frame(height: Space.s6)

                Image(systemName: role.iconSystemName)
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(palette.textPrimary)
                    .padding(Space.s4)
                    .background(
                        Circle().fill(palette.bgCardSoft)
                    )

                VStack(spacing: Space.s2) {
                    Text(role.displayName)
                        .font(EType.h1)
                        .foregroundStyle(palette.textPrimary)
                    Text(role.shortDescription)
                        .font(EType.body)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.s5)
                }

                VStack(alignment: .leading, spacing: Space.s2) {
                    Label("Your \(role.displayName.lowercased()) workspace is ready.",
                          systemImage: role.iconSystemName)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Label("Open the full role workspace on app.eusotrip.com.",
                          systemImage: "safari")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Label("Web sign-in may be required.",
                          systemImage: "person.badge.key")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCardSoft)
                )
                .padding(.horizontal, Space.s4)

                EusoCardIssuePanel(
                    title: "\(role.displayName) EusoCard",
                    subtitle: "Virtual card backed by EusoWallet"
                )
                .padding(.horizontal, Space.s4)

                Button {
                    open(path: definition.home.destinationId,
                         dockDestinationId: definition.home.destinationId)
                } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "safari")
                        Text("Open \(role.displayName) workspace")
                    }
                    .font(EType.bodyStrong)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(LinearGradient.diagonal)
                    )
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, Space.s4)

                Button {
                    Task { await session.signOut() }
                } label: {
                    Text("Sign out")
                        .font(EType.body)
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.top, Space.s2)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } nav: {
            EmptyView()
        }
        .environment(\.roleDockContract, roleDock)
        .eusoRefreshSurface(refreshSurfaceID)
        .onAppear {
            if selectedPath.isEmpty { selectedPath = definition.home.destinationId }
            if activeDestinationId.isEmpty { activeDestinationId = definition.home.destinationId }
        }
        .sheet(isPresented: $presentingWeb) {
            if let continuationURL {
                SafariContinuationView(url: continuationURL)
                    .ignoresSafeArea()
                    .eusoRefreshSurface("modal:web-continuation:\(role.rawValue)")
            }
        }
        .fullScreenCover(isPresented: $showeSang) {
            DrivereSangCoachSheet()
                .environment(\.palette, palette)
                .environmentObject(session)
                .environment(\.esangActionHandler) { action in
                    handleESang(action)
                }
        }
        .alert("Workspace route", isPresented: Binding(
            get: { routeError != nil },
            set: { if !$0 { routeError = nil } }
        )) {
            Button("OK", role: .cancel) { routeError = nil }
        } message: {
            Text(routeError ?? "")
        }
    }

    @MainActor
    private func open(path rawPath: String, dockDestinationId: String?) {
        let path = WebRoleDockDefinition.normalizedPath(rawPath)
        guard definition.allows(path: path, for: role),
              URL(string: "https://app.eusotrip.com\(path)") != nil else {
            routeError = "That workspace destination is not assigned to your \(role.displayName) role."
            return
        }
        selectedPath = path
        if let dockDestinationId { activeDestinationId = dockDestinationId }
        presentingWeb = true
    }

    @MainActor
    private func handleESang(_ action: eSangAction) {
        switch action {
        case .navigatePath(let rawPath):
            let path = WebRoleDockDefinition.normalizedPath(rawPath)
            guard definition.allows(path: path, for: role) else {
                NotificationCenter.default.post(name: .esangUnhandledCommand, object: rawPath)
                return
            }
            showeSang = false
            let dockId = definition.items.first(where: { $0.destinationId == path })?.destinationId
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                open(path: path, dockDestinationId: dockId)
            }

        case .navigate(let route):
            let destination: RoleDockItem
            switch route {
            case .home:
                destination = definition.home
            case .trips:
                destination = definition.workOne
            case .myLoads:
                destination = definition.workTwo
            case .me, .meDetail:
                destination = definition.me
            }
            showeSang = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                open(path: destination.destinationId,
                     dockDestinationId: destination.destinationId)
            }

        case .selectLoad(let rawId):
            // Safety and factoring do not own a load-record continuation.
            // Leave the command unhandled instead of crossing into another
            // role's route catalog.
            NotificationCenter.default.post(name: .esangUnhandledCommand, object: rawId)

        case .closeChat, .back:
            showeSang = false

        default:
            _ = eSangRoleDispatcher.dispatch(
                action,
                role: role,
                dismissSheet: { showeSang = false }
            )
        }
    }

}

private struct SafariContinuationView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        // Match the canonical EusoInAppSafari config: SFSafariViewController
        // is what unlocks iOS's free system Translate + Reader mode (a bare
        // WKWebView gets neither). barCollapsing keeps the chrome out of the
        // way; the brand magenta control tint reads this as part of EusoTrip
        // rather than a generic Safari sheet.
        let cfg = SFSafariViewController.Configuration()
        cfg.entersReaderIfAvailable = false
        cfg.barCollapsingEnabled = true
        let vc = SFSafariViewController(
            url: AppRadioSilenceDirectTransportController.shared.gatedRemoteURL(url),
            configuration: cfg
        )
        vc.dismissButtonStyle = .done
        vc.preferredControlTintColor = UIColor(red: 0.745, green: 0.004, blue: 1.0, alpha: 1)
        AppRadioSilenceDirectTransportController.shared.track(safariController: vc)
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

/// Identifiable wrapper so a `URL` can drive a SwiftUI
/// `.sheet(item:)` modifier. The URL is itself unique per
/// presentation so we use it as the `id`. Named distinctly from
/// `106_MeEusoTickets`'s `IdentifiedURL` (private to that file)
/// to avoid module-internal collision.
struct ShipperWebContinuationItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
    init(_ url: URL) { self.url = url }
}

// MARK: - RBAC

/// Cross-role access guard. Every screen swap (notification, deep link,
/// sheet) flows through this check before mounting. Screens not in the
/// caller-role's registry slice are denied — the caller falls back to
/// the role's home or shows an empty surface.
enum RoleAccess {
    /// True when the screen with `screenId` is registered under any
    /// of the chrome roles `role` is allowed to see. Defaults to
    /// `false` — an unregistered ID is denied rather than silently
    /// allowed. A backend role can map to multiple chrome roles
    /// (e.g. `EusoRole.catalyst` → `.carrier` for the canonical
    /// carrier screens AND `.catalyst` for the SpectraMatch sub-
    /// surface 500-502); the inclusive check makes those screens
    /// reachable without re-registering them under both roles.
    static func canRender(role: EusoRole, screenId: String) -> Bool {
        for chrome in allowedScreenRoles(for: role) {
            if ScreenRegistry.forRole(chrome).contains(where: { $0.id == screenId }) {
                return true
            }
        }
        return false
    }

    /// Every chrome-role bucket the backend role can navigate within.
    /// Used by `canRender` and by Surfaces that render across multiple
    /// chrome buckets (e.g. CarrierSurface drilling into Catalyst
    /// 500-502).
    static func allowedScreenRoles(for role: EusoRole) -> [ProductionScreen.Role] {
        switch role {
        case .driver:                                   return [.driver]
        case .shipper, .vesselShipper:                  return [.shipper]
        // Carrier-track backend roles can navigate into both the
        // canonical Carrier registry (300-320) AND the Catalyst
        // SpectraMatch sub-surface (500-502).
        case .catalyst:                                 return [.carrier, .catalyst]
        case .broker:                                   return [.broker]
        case .escort:                                   return [.escort]
        case .terminal:                                 return [.terminal]
        case .admin, .superAdmin:                       return [.admin]
        case .compliance:                               return [.compliance]
        case .dispatch:                                 return [.dispatch]
        // Shared mode registries are deliberately broad enough to mount a
        // proven native screen. `NativeModeRoleDefinition.allowedRoutes` is
        // the narrower, role-specific navigation fence.
        case .railShipper, .railCatalyst, .railDispatch,
             .railEngineer, .railConductor, .railBroker:
                                                        return [.railEngineer]
        case .vesselOperator, .portMaster, .shipCaptain,
             .vesselBroker, .customsBroker:             return [.vesselOperator]
        // Explicit web continuations do not own a native screen registry.
        case .safety, .factoring, .serviceProvider:     return []
        }
    }

    /// Map every backend role with a native surface to the registry bucket
    /// that owns its implementation. Continuation roles remain explicit
    /// continuations and therefore never call this function from the router.
    static func productionRole(for role: EusoRole) -> ProductionScreen.Role {
        switch role {
        case .driver:                                   return .driver
        case .shipper, .vesselShipper:                  return .shipper
        case .catalyst:                                 return .carrier
        case .broker:                                   return .broker
        case .escort:                                   return .escort
        case .terminal:                                 return .terminal
        case .admin, .superAdmin:                       return .admin
        case .compliance:                               return .compliance
        case .dispatch:                                 return .dispatch
        case .railShipper, .railCatalyst, .railDispatch,
             .railEngineer, .railConductor, .railBroker:
                                                        return .railEngineer
        case .vesselOperator, .portMaster, .shipCaptain,
             .vesselBroker, .customsBroker:             return .vesselOperator
        // No native registry exists for the explicit continuations.
        // The value is never consumed by their routed surface.
        case .safety, .factoring, .serviceProvider:     return .driver
        }
    }
}

// MARK: - HardwareCapabilitiesView
//
// Tenant self-declaration form. Owners (TERMINAL_MANAGER, SHIPPER,
// ADMIN, CATALYST, DISPATCH) declare what hardware they have so the
// driver iOS app can light up the matching feature path:
//
//   - TERMINAL scope (terminal manager / shipper / admin) — UWB
//     anchors per door, partner camera-feed registrations, ARKit
//     door markers, yard-layout GeoJSON polygon.
//   - CARRIER scope (catalyst / dispatch / admin) — fleet-wide
//     dash-cam vendor.
//   - TRAILER scope (catalyst / dispatch / admin) — per-trailer
//     dome cam + reefer monitor.
//
// The form auto-tabs the visible scopes based on the caller's role.
// A SHIPPER who also runs their own carrier company sees both
// TERMINAL + CARRIER tabs.
//
// Each tab loads the live envelope on appear, presents editable
// rows, and persists via the matching `capabilities.set*` mutation.

struct HardwareCapabilitiesView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: EusoTripSession

    /// Optional terminal id. When the form is presented from a
    /// SHIPPER context, the shipper picks which of their terminals
    /// to edit; the picker writes to this binding. ADMINs editing
    /// any terminal inject the id directly.
    @State private var activeTerminalId: Int

    @State private var selectedTab: Tab = .terminal
    @State private var loading: Bool = false
    @State private var saveToast: String? = nil

    // Live envelopes pulled from the backend.
    @State private var terminal: CapabilitiesAPI.TerminalCapabilities?
    @State private var carrier: CapabilitiesAPI.CarrierCapabilities?
    @State private var trailerId: String = ""
    @State private var trailer: CapabilitiesAPI.TrailerCapabilities?
    @State private var oauthSheetUrl: IdentifiableURL? = nil

    @State private var newAnchorDoor: String = ""
    @State private var newAnchorVendor: String = "qorvo"
    @State private var newAnchorBlob: String = ""
    @State private var newAnchorBT: String = ""

    @State private var newFeedDoor: String = ""
    @State private var newFeedVendor: String = "rtsp"
    @State private var newFeedLabel: String = ""
    @State private var newFeedURL: String = ""

    @State private var newMarkerDoor: String = ""
    @State private var newMarkerId: String = ""
    @State private var newMarkerOffsetX: String = "0.0"
    @State private var newMarkerOffsetY: String = "0.0"

    /// Identifiable wrapper so .sheet(item:) re-presents per-tap when
    /// the URL changes.
    struct IdentifiableURL: Identifiable, Hashable {
        let id: String
        let url: URL
    }

    enum Tab: String, CaseIterable, Identifiable {
        case terminal, carrier, trailer
        var id: String { rawValue }
        var label: String {
            switch self {
            case .terminal: return "Terminal"
            case .carrier:  return "Carrier"
            case .trailer:  return "Trailer"
            }
        }
    }

    init(initialTerminalId: Int = 0) {
        self._activeTerminalId = State(initialValue: initialTerminalId)
    }

    /// Tabs the caller's role is allowed to write. Reads pass through
    /// regardless — the backend RBAC re-checks on mutation, so the
    /// UI gate is for clarity, not security.
    private var visibleTabs: [Tab] {
        let role = (session.user?.role ?? "").uppercased()
        var tabs: [Tab] = []
        if ["TERMINAL_MANAGER", "SHIPPER", "ADMIN", "SUPER_ADMIN"].contains(role) {
            tabs.append(.terminal)
        }
        if ["CATALYST", "DISPATCH", "ADMIN", "SUPER_ADMIN"].contains(role) {
            tabs.append(.carrier)
            tabs.append(.trailer)
        }
        return tabs.isEmpty ? [.terminal] : tabs
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    headerCard
                    if visibleTabs.count > 1 {
                        tabBar
                    }
                    Group {
                        switch selectedTab {
                        case .terminal: terminalSection
                        case .carrier:  carrierSection
                        case .trailer:  trailerSection
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("Hardware Capabilities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let msg = saveToast {
                    Text(msg)
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(palette.bgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderSoft)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: saveToast)
            .task { await hydrate() }
            .onAppear {
                if !visibleTabs.contains(selectedTab),
                   let first = visibleTabs.first {
                    selectedTab = first
                }
            }
            .sheet(item: $oauthSheetUrl) { wrapped in
                OAuthSafariSheet(url: wrapped.url)
                    .ignoresSafeArea()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoVendorOAuthCallback)) { note in
                guard let info = note.userInfo,
                      let vendor = info["vendor"] as? String,
                      let code = info["code"] as? String else { return }
                let state = info["state"] as? String ?? ""
                Task { await completeVendorOAuth(vendor: vendor, code: code, state: state) }
                oauthSheetUrl = nil
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HARDWARE CAPABILITIES")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text("Tell EusoTrip what hardware you have")
                .font(EType.body.weight(.bold))
                .foregroundStyle(palette.textPrimary)
            Text("Drivers see the matching dock-cam, yardmap and AR fallback paths light up automatically. Anything left blank stays as 'Pair hardware' on the driver side. The affordance never disappears.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(visibleTabs) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selectedTab = tab }
                } label: {
                    Text(tab.label.uppercased())
                        .font(.system(size: 10, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(
                            selectedTab == tab
                              ? AnyShapeStyle(LinearGradient.diagonal)
                              : AnyShapeStyle(palette.textSecondary)
                        )
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(
                            Capsule().strokeBorder(
                                selectedTab == tab ? Brand.success.opacity(0.5)
                                                   : palette.borderFaint,
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Terminal section

    @ViewBuilder
    private var terminalSection: some View {
        sectionCard(title: "TERMINAL ID") {
            HStack {
                TextField("Terminal id", value: $activeTerminalId, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                Button("Load") {
                    Task { await loadTerminal() }
                }
                .buttonStyle(.bordered)
            }
        }

        let caps = terminal ?? CapabilitiesAPI.TerminalCapabilities.empty
        sectionCard(title: "UWB ANCHORS · \(caps.uwbAnchors.count)") {
            VStack(alignment: .leading, spacing: 6) {
                if caps.uwbAnchors.isEmpty {
                    Text("No anchors registered. Print a Qorvo SR150 / NXP Trimension tag, scan its accessory-config data, paste below.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                ForEach(caps.uwbAnchors, id: \.self) { a in
                    HStack(alignment: .top, spacing: 6) {
                        Text("· Door \(a.doorNumber) · \(a.vendor) (\(a.accessoryConfigData.prefix(8))…)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                        Button {
                            removeAnchor(a)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(Brand.danger)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider().padding(.vertical, 4)
                Text("ADD ANCHOR")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: 6) {
                    TextField("Door #", text: $newAnchorDoor)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Picker("Vendor", selection: $newAnchorVendor) {
                        Text("Qorvo").tag("qorvo")
                        Text("NXP").tag("nxp")
                        Text("Find My").tag("applefindmy")
                    }
                    .pickerStyle(.menu)
                }
                TextField("Accessory config blob (base64)", text: $newAnchorBlob)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .font(EType.mono(.caption))
                TextField("BT peer identifier (optional)", text: $newAnchorBT)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Button {
                    addAnchor()
                } label: {
                    Label("Add anchor", systemImage: "plus.circle.fill")
                        .font(EType.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(canAddAnchor
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(Brand.neutral))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canAddAnchor)
            }
        }

        sectionCard(title: "PARTNER CAMERA FEEDS · \(caps.cameraFeeds.count)") {
            VStack(alignment: .leading, spacing: 6) {
                if caps.cameraFeeds.isEmpty {
                    Text("Genetec / Avigilon / Milestone NVR? Register one feed per dock door so drivers can see live as they back in.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                ForEach(caps.cameraFeeds, id: \.self) { f in
                    HStack(alignment: .top, spacing: 6) {
                        Text("· Door \(f.doorNumber) · \(f.vendor)\(f.label.map { " · \($0)" } ?? "")")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                        Button {
                            removeFeed(f)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(Brand.danger)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider().padding(.vertical, 4)
                Text("ADD FEED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: 6) {
                    TextField("Door #", text: $newFeedDoor)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Picker("Vendor", selection: $newFeedVendor) {
                        Text("RTSP").tag("rtsp")
                        Text("Genetec").tag("genetec")
                        Text("Avigilon").tag("avigilon")
                        Text("Milestone").tag("milestone")
                    }
                    .pickerStyle(.menu)
                }
                TextField("Label (optional)", text: $newFeedLabel)
                    .textFieldStyle(.roundedBorder)
                TextField("Stream URL (rtsp:// or signaling endpoint)", text: $newFeedURL)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button {
                    addFeed()
                } label: {
                    Label("Add feed", systemImage: "plus.circle.fill")
                        .font(EType.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(canAddFeed
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(Brand.neutral))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canAddFeed)
            }
        }

        sectionCard(title: "ARKIT DOOR MARKERS · \(caps.doorMarkers.count)") {
            VStack(alignment: .leading, spacing: 6) {
                if caps.doorMarkers.isEmpty {
                    Text("Print + epoxy 30cm AprilTag / QR markers above each dock door. Register the marker id (asset name) so drivers' phone cameras can read alignment when UWB drops LOS.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                ForEach(caps.doorMarkers, id: \.self) { m in
                    HStack(alignment: .top, spacing: 6) {
                        Text("· Door \(m.doorNumber) · marker \(m.markerId) (offset \(m.offsetX, specifier: "%.2f")m, \(m.offsetY, specifier: "%.2f")m)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                        Button {
                            removeMarker(m)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(Brand.danger)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider().padding(.vertical, 4)
                Text("ADD MARKER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: 6) {
                    TextField("Door #", text: $newMarkerDoor)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    TextField("Marker id", text: $newMarkerId)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
                HStack(spacing: 6) {
                    TextField("Offset X (m)", text: $newMarkerOffsetX)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                    TextField("Offset Y (m)", text: $newMarkerOffsetY)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }
                Button {
                    addMarker()
                } label: {
                    Label("Add marker", systemImage: "plus.circle.fill")
                        .font(EType.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(canAddMarker
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(Brand.neutral))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canAddMarker)
            }
        }

        sectionCard(title: "YARD LAYOUT (GeoJSON)") {
            VStack(alignment: .leading, spacing: 8) {
                let geoBinding = Binding<String>(
                    get: { terminal?.yardLayoutGeoJson ?? "" },
                    set: { newVal in
                        var updated = terminal ?? CapabilitiesAPI.TerminalCapabilities(
                            terminalId: activeTerminalId,
                            uwbAnchors: [],
                            cameraFeeds: [],
                            doorMarkers: [],
                            yardLayoutGeoJson: nil
                        )
                        updated = CapabilitiesAPI.TerminalCapabilities(
                            terminalId: updated.terminalId,
                            uwbAnchors: updated.uwbAnchors,
                            cameraFeeds: updated.cameraFeeds,
                            doorMarkers: updated.doorMarkers,
                            yardLayoutGeoJson: newVal.isEmpty ? nil : newVal
                        )
                        terminal = updated
                    }
                )
                TextEditor(text: geoBinding)
                    .font(EType.mono(.caption))
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                Text("Paste a Polygon, MultiPolygon, Feature or FeatureCollection. Drivers see translucent dock-lane / staging-zone overlays on top of the HereMapView basemap.")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
                Button("Save terminal capabilities") {
                    Task { await saveTerminal() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(loading)
            }
        }
    }

    // MARK: Carrier section

    @ViewBuilder
    private var carrierSection: some View {
        let cap = carrier ?? CapabilitiesAPI.CarrierCapabilities.empty
        sectionCard(title: "DASH CAM VENDOR") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["samsara", "motive", "garmin", "cipia", "none"], id: \.self) { vendor in
                    HStack {
                        Image(systemName: cap.dashCam.vendor == vendor
                              ? "largecircle.fill.circle"
                              : "circle")
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(vendor.capitalized)
                            .font(EType.body)
                            .foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        var updated = cap
                        updated = CapabilitiesAPI.CarrierCapabilities(
                            carrierId: updated.carrierId,
                            dashCam: CapabilitiesAPI.DashCamVendor(
                                vendor: vendor,
                                credentialsToken: nil,
                                configured: vendor != "none" ? updated.dashCam.configured : false
                            )
                        )
                        carrier = updated
                    }
                }
                if cap.dashCam.configured {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Brand.success)
                        Text("Connected to \(cap.dashCam.vendor.capitalized)")
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                    }
                } else if cap.dashCam.vendor != "none" {
                    Button {
                        Task { await launchVendorOAuth(vendor: cap.dashCam.vendor) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.square.fill")
                            Text("Connect \(cap.dashCam.vendor.capitalized)")
                                .font(EType.body.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(loading)
                }
                Text("Connect opens the vendor's secure OAuth login. After you grant access, drivers see the dash-cam row light up on the dock-cam picker.")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
                Button("Save vendor selection") {
                    Task { await saveCarrier() }
                }
                .buttonStyle(.bordered)
                .disabled(loading)
            }
        }
    }

    // MARK: Trailer section

    @ViewBuilder
    private var trailerSection: some View {
        sectionCard(title: "TRAILER ID") {
            HStack {
                TextField("Trailer id (VIN / asset tag)", text: $trailerId)
                    .textFieldStyle(.roundedBorder)
                Button("Load") {
                    Task { await loadTrailer() }
                }
                .buttonStyle(.bordered)
                .disabled(trailerId.isEmpty)
            }
        }

        if let t = trailer {
            sectionCard(title: "DOME CAM VENDOR") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(["sensata", "orbcomm", "spireon", "none"], id: \.self) { vendor in
                        HStack {
                            Image(systemName: t.domeCamVendor == vendor
                                  ? "largecircle.fill.circle"
                                  : "circle")
                                .foregroundStyle(LinearGradient.diagonal)
                            Text(vendor.capitalized)
                                .font(EType.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            trailer = CapabilitiesAPI.TrailerCapabilities(
                                trailerId: t.trailerId,
                                domeCamVendor: vendor,
                                domeCamStreamUrl: vendor == "none" ? nil : t.domeCamStreamUrl,
                                reeferMonitorVendor: t.reeferMonitorVendor
                            )
                        }
                    }
                    TextField("Stream URL (HLS .m3u8 or vendor-specific)",
                              text: Binding(
                                  get: { trailer?.domeCamStreamUrl ?? "" },
                                  set: { v in
                                      if let cur = trailer {
                                          trailer = CapabilitiesAPI.TrailerCapabilities(
                                              trailerId: cur.trailerId,
                                              domeCamVendor: cur.domeCamVendor,
                                              domeCamStreamUrl: v.isEmpty ? nil : v,
                                              reeferMonitorVendor: cur.reeferMonitorVendor
                                          )
                                      }
                                  }
                              ))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    Button("Save trailer capabilities") {
                        Task { await saveTrailer() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(loading)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionCard<Inner: View>(
        title: String,
        @ViewBuilder content: () -> Inner
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Inline-add helpers (anchors / camera feeds / door markers)

    private var canAddAnchor: Bool {
        !newAnchorDoor.trimmingCharacters(in: .whitespaces).isEmpty &&
        !newAnchorBlob.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var canAddFeed: Bool {
        !newFeedDoor.trimmingCharacters(in: .whitespaces).isEmpty &&
        !newFeedURL.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var canAddMarker: Bool {
        !newMarkerDoor.trimmingCharacters(in: .whitespaces).isEmpty &&
        !newMarkerId.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func currentTerminal() -> CapabilitiesAPI.TerminalCapabilities {
        terminal ?? CapabilitiesAPI.TerminalCapabilities(
            terminalId: activeTerminalId,
            uwbAnchors: [],
            cameraFeeds: [],
            doorMarkers: [],
            yardLayoutGeoJson: nil
        )
    }

    private func addAnchor() {
        let cur = currentTerminal()
        let door = newAnchorDoor.trimmingCharacters(in: .whitespaces)
        let blob = newAnchorBlob.trimmingCharacters(in: .whitespaces)
        let bt = newAnchorBT.trimmingCharacters(in: .whitespaces)
        var next = cur.uwbAnchors.filter { $0.doorNumber != door }
        next.append(CapabilitiesAPI.UwbAnchor(
            doorNumber: door,
            vendor: newAnchorVendor,
            accessoryConfigData: blob,
            bluetoothPeerIdentifier: bt.isEmpty ? nil : bt
        ))
        terminal = CapabilitiesAPI.TerminalCapabilities(
            terminalId: cur.terminalId,
            uwbAnchors: next,
            cameraFeeds: cur.cameraFeeds,
            doorMarkers: cur.doorMarkers,
            yardLayoutGeoJson: cur.yardLayoutGeoJson
        )
        newAnchorDoor = ""; newAnchorBlob = ""; newAnchorBT = ""
        Task { await saveTerminal() }
    }

    private func removeAnchor(_ a: CapabilitiesAPI.UwbAnchor) {
        let cur = currentTerminal()
        terminal = CapabilitiesAPI.TerminalCapabilities(
            terminalId: cur.terminalId,
            uwbAnchors: cur.uwbAnchors.filter { $0 != a },
            cameraFeeds: cur.cameraFeeds,
            doorMarkers: cur.doorMarkers,
            yardLayoutGeoJson: cur.yardLayoutGeoJson
        )
        Task { await saveTerminal() }
    }

    private func addFeed() {
        let cur = currentTerminal()
        let door = newFeedDoor.trimmingCharacters(in: .whitespaces)
        let url = newFeedURL.trimmingCharacters(in: .whitespaces)
        let label = newFeedLabel.trimmingCharacters(in: .whitespaces)
        var next = cur.cameraFeeds.filter { $0.doorNumber != door }
        next.append(CapabilitiesAPI.CameraFeed(
            doorNumber: door,
            vendor: newFeedVendor,
            label: label.isEmpty ? nil : label,
            streamUrl: url,
            signalingToken: nil
        ))
        terminal = CapabilitiesAPI.TerminalCapabilities(
            terminalId: cur.terminalId,
            uwbAnchors: cur.uwbAnchors,
            cameraFeeds: next,
            doorMarkers: cur.doorMarkers,
            yardLayoutGeoJson: cur.yardLayoutGeoJson
        )
        newFeedDoor = ""; newFeedURL = ""; newFeedLabel = ""
        Task { await saveTerminal() }
    }

    private func removeFeed(_ f: CapabilitiesAPI.CameraFeed) {
        let cur = currentTerminal()
        terminal = CapabilitiesAPI.TerminalCapabilities(
            terminalId: cur.terminalId,
            uwbAnchors: cur.uwbAnchors,
            cameraFeeds: cur.cameraFeeds.filter { $0 != f },
            doorMarkers: cur.doorMarkers,
            yardLayoutGeoJson: cur.yardLayoutGeoJson
        )
        Task { await saveTerminal() }
    }

    private func addMarker() {
        let cur = currentTerminal()
        let door = newMarkerDoor.trimmingCharacters(in: .whitespaces)
        let mid = newMarkerId.trimmingCharacters(in: .whitespaces)
        let ox = Double(newMarkerOffsetX.trimmingCharacters(in: .whitespaces)) ?? 0.0
        let oy = Double(newMarkerOffsetY.trimmingCharacters(in: .whitespaces)) ?? 0.0
        var next = cur.doorMarkers.filter { $0.doorNumber != door }
        next.append(CapabilitiesAPI.DoorMarker(
            doorNumber: door,
            markerId: mid,
            offsetX: ox,
            offsetY: oy
        ))
        terminal = CapabilitiesAPI.TerminalCapabilities(
            terminalId: cur.terminalId,
            uwbAnchors: cur.uwbAnchors,
            cameraFeeds: cur.cameraFeeds,
            doorMarkers: next,
            yardLayoutGeoJson: cur.yardLayoutGeoJson
        )
        newMarkerDoor = ""; newMarkerId = ""; newMarkerOffsetX = "0.0"; newMarkerOffsetY = "0.0"
        Task { await saveTerminal() }
    }

    private func removeMarker(_ m: CapabilitiesAPI.DoorMarker) {
        let cur = currentTerminal()
        terminal = CapabilitiesAPI.TerminalCapabilities(
            terminalId: cur.terminalId,
            uwbAnchors: cur.uwbAnchors,
            cameraFeeds: cur.cameraFeeds,
            doorMarkers: cur.doorMarkers.filter { $0 != m },
            yardLayoutGeoJson: cur.yardLayoutGeoJson
        )
        Task { await saveTerminal() }
    }

    // MARK: Hydrate + save

    private func hydrate() async {
        await loadTerminal()
        await loadCarrier()
    }

    private func loadTerminal() async {
        guard activeTerminalId > 0 else { return }
        terminal = try? await EusoTripAPI.shared.capabilities
            .getTerminal(terminalId: activeTerminalId)
    }
    private func loadCarrier() async {
        carrier = try? await EusoTripAPI.shared.capabilities.getMyCarrier()
    }
    private func loadTrailer() async {
        guard !trailerId.isEmpty else { return }
        trailer = try? await EusoTripAPI.shared.capabilities
            .getTrailer(trailerId: trailerId)
    }

    private func saveTerminal() async {
        guard let t = terminal else { return }
        loading = true; defer { loading = false }
        do {
            _ = try await EusoTripAPI.shared.capabilities.setTerminal(t)
            saveToast = "Terminal capabilities saved"
        } catch {
            saveToast = "Save failed: \(error.localizedDescription)"
        }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        saveToast = nil
    }
    private func saveCarrier() async {
        guard let c = carrier else { return }
        loading = true; defer { loading = false }
        do {
            _ = try await EusoTripAPI.shared.capabilities.setMyCarrier(c)
            saveToast = "Carrier capabilities saved"
        } catch {
            saveToast = "Save failed: \(error.localizedDescription)"
        }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        saveToast = nil
    }
    private func saveTrailer() async {
        guard let t = trailer else { return }
        loading = true; defer { loading = false }
        do {
            _ = try await EusoTripAPI.shared.capabilities.setTrailer(t)
            saveToast = "Trailer capabilities saved"
        } catch {
            saveToast = "Save failed: \(error.localizedDescription)"
        }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        saveToast = nil
    }

    // MARK: Vendor OAuth

    /// Step 1: ask the backend for the vendor's authorize URL +
    /// CSRF state, then present SFSafariViewController with that
    /// URL. The user grants permission, vendor redirects back via
    /// `eusotrip://oauth/callback/<vendor>?code=…&state=…`,
    /// AppRoot's URL handler captures it, posts
    /// `.eusoVendorOAuthCallback`, and the observer above calls
    /// `completeVendorOAuth`.
    private func launchVendorOAuth(vendor: String) async {
        loading = true; defer { loading = false }
        do {
            let resp = try await EusoTripAPI.shared.capabilities
                .startVendorOAuth(vendor: vendor)
            guard let url = URL(string: resp.authorizeUrl) else {
                saveToast = "Vendor returned an invalid authorize URL"
                return
            }
            oauthSheetUrl = IdentifiableURL(id: "\(vendor)-\(resp.state)", url: url)
        } catch {
            saveToast = "Couldn't start \(vendor.capitalized) OAuth: \(error.localizedDescription)"
        }
    }

    /// Step 2: trade the authorization code for the vendor's
    /// long-lived token. Backend stores ciphertext, flips
    /// `configured = true`, returns the iOS-side truth value. We
    /// reload the capability envelope so the form state matches
    /// the backend immediately.
    private func completeVendorOAuth(vendor: String, code: String, state: String) async {
        loading = true; defer { loading = false }
        do {
            _ = try await EusoTripAPI.shared.capabilities
                .exchangeOAuthCode(vendor: vendor, code: code, state: state)
            saveToast = "\(vendor.capitalized) connected"
            await loadCarrier()
        } catch {
            saveToast = "Connect failed: \(error.localizedDescription)"
        }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        saveToast = nil
    }
}

// MARK: - Vendor OAuth launcher + callback notification
//
// Per-vendor OAuth handshake for dash-cam (Samsara / Motive / Garmin
// / Cipia) and trailer dome-cam (Sensata / ORBCOMM / Spireon)
// integrations. Pattern is uniform per vendor:
//
//   1. User taps "Connect <vendor>" in the carrier or trailer tab
//      of the Hardware Capabilities form.
//   2. iOS calls `capabilities.startVendorOAuth(vendor)`; backend
//      mints the authorize URL + opaque CSRF state token.
//   3. iOS opens the URL in SFSafariViewController. User logs in
//      to the vendor + grants permission.
//   4. Vendor redirects to `eusotrip://oauth/callback/<vendor>?code=…&state=…`.
//   5. AppRoot's `.onOpenURL` handler captures the redirect, posts
//      `.eusoVendorOAuthCallback` with the parsed query items.
//   6. The HardwareCapabilitiesView observes that notification +
//      calls `capabilities.exchangeOAuthCode`. Backend trades the
//      code for the vendor's long-lived refresh token, stores
//      ciphertext on the matching capability envelope, flips
//      `configured = true`. iOS reloads + the matching dock-cam
//      picker row lights up.
//
// Custom URL scheme: `eusotrip://` is registered in Info.plist
// (CFBundleURLSchemes). Add an entry for `eusotrip` if missing.

import SafariServices

extension Notification.Name {
    /// Fired by AppRoot's `.onOpenURL` handler when the user finishes
    /// a vendor OAuth flow and Safari redirects to
    /// `eusotrip://oauth/callback/<vendor>?code=…&state=…`. userInfo:
    ///   - "vendor": String
    ///   - "code":   String
    ///   - "state":  String?
    static let eusoVendorOAuthCallback = Notification.Name("eusoVendorOAuthCallback")
}

/// Helper that parses an incoming `eusotrip://oauth/callback/...` URL
/// and posts the matching `.eusoVendorOAuthCallback` notification.
/// Called from `AppRoot` / `ContentView` `.onOpenURL` so the URL
/// scheme handler stays a single line at the call site.
enum VendorOAuthCallback {
    static func handle(url: URL) -> Bool {
        guard url.scheme == "eusotrip",
              url.host == "oauth",
              url.pathComponents.count >= 3,
              url.pathComponents[1] == "callback" else { return false }
        let vendor = url.pathComponents[2]
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value
        let state = comps?.queryItems?.first(where: { $0.name == "state" })?.value
        guard let code else { return true } // we recognized the URL but couldn't parse — swallow
        var info: [String: Any] = ["vendor": vendor, "code": code]
        if let state { info["state"] = state }
        NotificationCenter.default.post(
            name: .eusoVendorOAuthCallback,
            object: nil, userInfo: info
        )
        return true
    }
}

/// SwiftUI wrapper around SFSafariViewController for OAuth flows.
/// Pinned to a fresh instance per `present()` because SFSafariVC
/// won't load a new URL once it's been displayed.
struct OAuthSafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(
            url: AppRadioSilenceDirectTransportController.shared.gatedRemoteURL(url)
        )
        vc.dismissButtonStyle = .close
        AppRadioSilenceDirectTransportController.shared.track(safariController: vc)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
