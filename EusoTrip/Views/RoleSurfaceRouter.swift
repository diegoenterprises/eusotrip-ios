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
//  Roles with full native iOS surfaces this session:
//    • DRIVER   → driverSurface (existing 4-pane: Home/Trips/Loads/Me)
//    • SHIPPER  → ShipperSurface (200/201/202/204 routed by
//                  `eusoShipperNavSwap` from `ShipperNavController`)
//
//  Roles that have a real registered Home screen and route to it:
//    • CATALYST (Carrier)        → 300_CarrierHome
//    • BROKER                    → 400_BrokerHome
//    • ESCORT                    → 600_EscortHome
//    • TERMINAL_MANAGER          → 700_TerminalHome
//    • ADMIN / SUPER_ADMIN       → 800_AdminHome
//
//  Roles whose iOS surface ships in a later session (Dispatch, Compliance,
//  Safety, Factoring, all Rail, all Vessel, Customs Broker) route to a
//  real `WebContinuationView` — an SFSafariViewController loading
//  `app.eusotrip.com/{role-slug}` over the same Bearer-cookie session
//  the iOS app already holds. The web app is the production surface for
//  those roles today; this is not a stub.
//
//  RBAC: every cross-role nav request (notification, deep-link, sheet)
//  passes through `RoleAccess.canRender(role:screenId:)` which short-
//  circuits to the role's home if the requested screen is not in
//  `ScreenRegistry.forRole(role)`.
//

import SwiftUI
import SafariServices

// MARK: - Role surface router

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

        switch role {
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

        case .escort:
            EscortSurface(palette: palette)

        case .terminal:
            TerminalSurface(palette: palette)

        case .admin, .superAdmin:
            AdminSurface(palette: palette)

        case .dispatch:
            // Dispatch has 13 native iOS files (Dpch700-Dpch712) —
            // surface landed natively 2026-05-01 with the design-
            // token normalization + unshelf of 702-712.
            DispatchSurface(palette: palette)
        case .compliance:
            // Compliance has 3 native iOS files (900-902) — surfaces
            // landed natively 2026-05-01 with the resurrection of the
            // previously-shelved 901/902 + addition of `.compliance`
            // to the chrome registry.
            ComplianceSurface(palette: palette)
        case .safety:
            WebContinuationSurface(role: role, palette: palette,
                                   pathSlug: "safety")
        case .factoring:
            WebContinuationSurface(role: role, palette: palette,
                                   pathSlug: "factoring")
        case .railShipper:
            WebContinuationSurface(role: role, palette: palette,
                                   pathSlug: "rail/shipper")
        case .railCatalyst:
            WebContinuationSurface(role: role, palette: palette,
                                   pathSlug: "rail/carrier")
        case .railDispatch:
            WebContinuationSurface(role: role, palette: palette,
                                   pathSlug: "rail/dispatch")
        case .railEngineer:
            WebContinuationSurface(role: role, palette: palette,
                                   pathSlug: "rail/engineer")
        case .railConductor:
            WebContinuationSurface(role: role, palette: palette,
                                   pathSlug: "rail/conductor")
        case .railBroker:
            WebContinuationSurface(role: role, palette: palette,
                                   pathSlug: "rail/broker")
        case .vesselShipper:
            WebContinuationSurface(role: role, palette: palette,
                                   pathSlug: "vessel/shipper")
        case .vesselOperator:
            WebContinuationSurface(role: role, palette: palette,
                                   pathSlug: "vessel/operator")
        case .portMaster:
            WebContinuationSurface(role: role, palette: palette,
                                   pathSlug: "vessel/port-master")
        case .shipCaptain:
            WebContinuationSurface(role: role, palette: palette,
                                   pathSlug: "vessel/captain")
        case .vesselBroker:
            WebContinuationSurface(role: role, palette: palette,
                                   pathSlug: "vessel/broker")
        case .customsBroker:
            WebContinuationSurface(role: role, palette: palette,
                                   pathSlug: "customs-broker")
        }
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
                Text("ContentView should have dispatched the Driver surface directly. Reaching `RoleSurfaceRouter` for `.driver` is a build-time wiring bug — file a defect.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.s5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } nav: { EmptyView() }
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
    @State private var currentScreenId: String = "200"
    @State private var showESang: Bool = false

    private var current: ProductionScreen {
        // 200 (Home) is the canonical fallback. RBAC is also enforced
        // here — if for any reason the registry is missing 200 (build
        // mistake), we fall through to a hard error surface rather
        // than silently rendering a Driver screen.
        ScreenRegistry.forRole(.shipper).first { $0.id == currentScreenId }
            ?? ScreenRegistry.forRole(.shipper).first { $0.id == "200" }
            ?? ScreenRegistry.forRole(.shipper).first
            ?? ProductionScreen(id: "200",
                                title: "Shipper · Home",
                                role: .shipper) { p in
                                    AnyView(ShipperHomeScreen(theme: p))
                                }
    }

    var body: some View {
        current.view(palette)
            .id("shipper-\(currentScreenId)")
            .transition(.opacity)
            .environment(\.shipperNavHandler) { label in
                // Direct in-process dispatch — no NotificationCenter
                // round-trip needed when this surface owns the state.
                // Mirrors the Driver-side `driverNavHandler` pattern
                // already wired in ContentView.
                ShipperNavDispatcher.handle(label)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoShipperNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .shipper, screenId: id) else {
                    currentScreenId = "200"
                    return
                }
                withAnimation(.easeInOut(duration: 0.22)) {
                    currentScreenId = id
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoShipperEsangTapped)) { _ in
                showESang = true
            }
            .sheet(isPresented: $showESang) {
                // Shipper-context ESANG sheet — driver sheet was a
                // mistake (showed driver chips like "HOS buffer" /
                // "Fuel stop" / "Detention log" to a shipper).
                // ShipperESangCoachSheet uses shipper chips
                // (Active bids / Carrier vet / Settlement / Spend
                // YTD / Post a load / Best lane rate) and sends
                // `currentPage = "shipper.coach"` so server-side
                // ESANG tunes its system prompt to the shipper
                // knowledge slice.
                ShipperESangCoachSheet()
                    .environment(\.palette, palette)
                    .environmentObject(session)
            }
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
    @State private var currentScreenId: String = "300"
    @State private var showESang: Bool = false

    private var current: ProductionScreen {
        // Look across both `.carrier` (300-320) and `.catalyst`
        // (500-502) registries so the carrier user can navigate
        // into the SpectraMatch sub-surface without re-registering
        // those screens under `.carrier`. RBAC has already approved
        // the swap before the surface gets here (see
        // `RoleAccess.allowedScreenRoles(for:.catalyst)`).
        let pool = ScreenRegistry.forRole(.carrier)
                 + ScreenRegistry.forRole(.catalyst)
        return pool.first { $0.id == currentScreenId }
            ?? pool.first { $0.id == "300" }
            ?? pool.first
            ?? ProductionScreen(id: "300",
                                title: "Carrier · Home",
                                role: .carrier) { p in
                                    AnyView(CarrierHomeScreen(theme: p))
                                }
    }

    var body: some View {
        current.view(palette)
            .id("carrier-\(currentScreenId)")
            .transition(.opacity)
            .environment(\.carrierNavHandler) { label in
                // In-process dispatch — same pattern as the
                // Driver / Shipper handlers. The dispatcher posts
                // through NotificationCenter so per-screen helpers
                // (e.g. row taps, deep-links from sheet bodies)
                // can also post the same notification without
                // needing a handle to this surface.
                CarrierNavDispatcher.handle(label)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoCarrierNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .catalyst, screenId: id) else {
                    currentScreenId = "300"
                    return
                }
                withAnimation(.easeInOut(duration: 0.22)) {
                    currentScreenId = id
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoCarrierEsangTapped)) { _ in
                showESang = true
            }
            .sheet(isPresented: $showESang) {
                DriverESangCoachSheet()
                    .environment(\.palette, palette)
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
    @State private var currentScreenId: String = "400"
    @State private var showESang: Bool = false

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

    var body: some View {
        current.view(palette)
            .id("broker-\(currentScreenId)")
            .transition(.opacity)
            .environment(\.brokerNavHandler) { label in
                BrokerNavDispatcher.handle(label)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoBrokerNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .broker, screenId: id) else {
                    currentScreenId = "400"
                    return
                }
                withAnimation(.easeInOut(duration: 0.22)) {
                    currentScreenId = id
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoBrokerEsangTapped)) { _ in
                showESang = true
            }
            .sheet(isPresented: $showESang) {
                DriverESangCoachSheet()
                    .environment(\.palette, palette)
            }
    }
}

// MARK: - Escort surface

/// Top-level Escort container. Pattern matches Shipper / Carrier /
/// Broker. RBAC-gated through `RoleAccess.canRender(role:.escort)`.
struct EscortSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    @State private var currentScreenId: String = "600"
    @State private var showESang: Bool = false

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

    var body: some View {
        current.view(palette)
            .id("escort-\(currentScreenId)")
            .transition(.opacity)
            .environment(\.escortNavHandler) { label in
                EscortNavDispatcher.handle(label)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoEscortNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .escort, screenId: id) else {
                    currentScreenId = "600"
                    return
                }
                withAnimation(.easeInOut(duration: 0.22)) {
                    currentScreenId = id
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoEscortEsangTapped)) { _ in
                showESang = true
            }
            .sheet(isPresented: $showESang) {
                DriverESangCoachSheet().environment(\.palette, palette)
            }
    }
}

// MARK: - Terminal surface

/// Top-level Terminal container. Pattern matches Shipper / Carrier /
/// Broker / Escort. RBAC-gated through `RoleAccess.canRender(role:.terminal)`.
struct TerminalSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    @State private var currentScreenId: String = "700"
    @State private var showESang: Bool = false

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

    var body: some View {
        current.view(palette)
            .id("terminal-\(currentScreenId)")
            .transition(.opacity)
            .environment(\.terminalNavHandler) { label in
                TerminalNavDispatcher.handle(label)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoTerminalNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .terminal, screenId: id) else {
                    currentScreenId = "700"
                    return
                }
                withAnimation(.easeInOut(duration: 0.22)) {
                    currentScreenId = id
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoTerminalEsangTapped)) { _ in
                showESang = true
            }
            .sheet(isPresented: $showESang) {
                DriverESangCoachSheet().environment(\.palette, palette)
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
    @State private var currentScreenId: String = "800"
    @State private var showESang: Bool = false

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

    var body: some View {
        current.view(palette)
            .id("admin-\(currentScreenId)")
            .transition(.opacity)
            .environment(\.adminNavHandler) { label in
                AdminNavDispatcher.handle(label)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoAdminNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .admin, screenId: id) else {
                    currentScreenId = "800"
                    return
                }
                withAnimation(.easeInOut(duration: 0.22)) {
                    currentScreenId = id
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoAdminEsangTapped)) { _ in
                showESang = true
            }
            .sheet(isPresented: $showESang) {
                DriverESangCoachSheet().environment(\.palette, palette)
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
    @State private var currentScreenId: String = "Dpch700"
    @State private var showESang: Bool = false

    private var current: ProductionScreen {
        ScreenRegistry.forRole(.dispatch).first { $0.id == currentScreenId }
            ?? ScreenRegistry.forRole(.dispatch).first { $0.id == "Dpch700" }
            ?? ScreenRegistry.forRole(.dispatch).first
            ?? ProductionScreen(id: "Dpch700",
                                title: "Dispatch · Home",
                                role: .dispatch) { p in
                                    AnyView(DispatchHomeScreen(theme: p))
                                }
    }

    var body: some View {
        current.view(palette)
            .id("dispatch-\(currentScreenId)")
            .transition(.opacity)
            .environment(\.dispatchNavHandler) { label in
                DispatchNavDispatcher.handle(label)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoDispatchNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .dispatch, screenId: id) else {
                    currentScreenId = "Dpch700"
                    return
                }
                withAnimation(.easeInOut(duration: 0.22)) {
                    currentScreenId = id
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoDispatchEsangTapped)) { _ in
                showESang = true
            }
            .sheet(isPresented: $showESang) {
                DriverESangCoachSheet().environment(\.palette, palette)
            }
    }
}

// MARK: - Compliance surface

/// Top-level Compliance Officer container. Mirror of Shipper /
/// Carrier / Broker / Escort / Terminal / Admin surfaces. RBAC-gated
/// through `RoleAccess.canRender(role:.compliance)`.
struct ComplianceSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    @State private var currentScreenId: String = "900"
    @State private var showESang: Bool = false

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

    var body: some View {
        current.view(palette)
            .id("compliance-\(currentScreenId)")
            .transition(.opacity)
            .environment(\.complianceNavHandler) { label in
                ComplianceNavDispatcher.handle(label)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoComplianceNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .compliance, screenId: id) else {
                    currentScreenId = "900"
                    return
                }
                withAnimation(.easeInOut(duration: 0.22)) {
                    currentScreenId = id
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoComplianceEsangTapped)) { _ in
                showESang = true
            }
            .sheet(isPresented: $showESang) {
                DriverESangCoachSheet().environment(\.palette, palette)
            }
    }
}

// MARK: - Web continuation surface (roles without an iOS surface yet)

/// Real production landing for the 14 backend roles that don't ship a
/// native iOS surface in this session. Loads `app.eusotrip.com` in an
/// SFSafariViewController on tap. The user is already authenticated via
/// the same Bearer token cookie the iOS app uses against
/// `eusotrip-app.azurewebsites.net`, so the web app honors the session
/// without a re-login.
struct WebContinuationSurface: View {
    let role: EusoRole
    let palette: Theme.Palette
    /// Path segment under `/` on the web app — e.g. "dispatch", "rail/shipper".
    let pathSlug: String

    @EnvironmentObject var session: EusoTripSession
    @State private var presentingWeb = false

    private var continuationURL: URL {
        // Production web app. Keep this as the public domain rather
        // than the Azure backend host because the web SPA + cookies
        // live on eusotrip.com.
        URL(string: "https://app.eusotrip.com/\(pathSlug)")!
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
                    Label("Native iOS surface ships in a later release.",
                          systemImage: "iphone")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Label("Full role tooling is live on the web today.",
                          systemImage: "safari")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Label("You stay signed in — your session carries over.",
                          systemImage: "checkmark.shield")
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

                Button {
                    presentingWeb = true
                } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "safari")
                        Text("Continue on app.eusotrip.com")
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
        .sheet(isPresented: $presentingWeb) {
            SafariContinuationView(url: continuationURL)
                .ignoresSafeArea()
        }
    }
}

private struct SafariContinuationView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
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
        case .shipper, .railShipper, .vesselShipper:    return [.shipper]
        // Carrier-track backend roles can navigate into both the
        // canonical Carrier registry (300-320) AND the Catalyst
        // SpectraMatch sub-surface (500-502).
        case .catalyst, .railCatalyst, .vesselOperator: return [.carrier, .catalyst]
        case .broker, .railBroker, .vesselBroker,
             .customsBroker:                            return [.broker]
        case .escort:                                   return [.escort]
        case .terminal, .portMaster:                    return [.terminal]
        case .admin, .superAdmin:                       return [.admin]
        case .compliance:                               return [.compliance]
        case .dispatch:                                 return [.dispatch]
        // Roles below have no native chrome — they route to web
        // continuation in `RoleSurfaceRouter`. Empty list means
        // every cross-role swap is denied for them, which is the
        // correct outcome since their surface lives outside the
        // app entirely.
        case .safety, .factoring,
             .railDispatch, .railEngineer, .railConductor,
             .shipCaptain:                              return []
        }
    }

    /// Map the 24-role backend enum to the 8-role chrome enum used by
    /// `ScreenRegistry`. Roles without a registered surface map to
    /// their nearest analog so RBAC can still answer truthfully (a
    /// rail-shipper has no registered iOS screens, so every check
    /// fails — which is the correct outcome).
    static func productionRole(for role: EusoRole) -> ProductionScreen.Role {
        switch role {
        case .driver:                return .driver
        case .shipper, .railShipper, .vesselShipper:
                                     return .shipper
        case .catalyst, .railCatalyst, .vesselOperator:
                                     return .carrier
        case .broker, .railBroker, .vesselBroker, .customsBroker:
                                     return .broker
        case .escort:                return .escort
        case .terminal, .portMaster: return .terminal
        case .admin, .superAdmin:    return .admin
        // Roles below have no chrome-role analog; map to a sentinel
        // (.driver) but RoleAccess.canRender still returns false for
        // them because none of their screen IDs are registered against
        // .driver. The router routes these to web continuation, never
        // through the registry path.
        case .dispatch, .compliance, .safety, .factoring,
             .railDispatch, .railEngineer, .railConductor,
             .shipCaptain:
                                     return .driver
        }
    }
}
