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
import PhotosUI
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
            RailEngineerSurface(palette: palette)
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
            VesselOperatorSurface(palette: palette)
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

    /// Top of the navigation stack — the screen currently rendered.
    private var currentScreenId: String { screenStack.last ?? "200" }

    /// Bottom-nav tab roots. Pushing one of these collapses the stack
    /// to a single entry rather than appending — same semantics as
    /// UIKit's `UITabBarController` where switching tabs resets the
    /// per-tab back-stack.
    private static let tabRoots: Set<String> = ["200", "201", "204", "320"]
    /// Captured from `.eusoShipperLoadOpen` / `.eusoShipperLoadOpenMap`
    /// / `.eusoShipperSettlementOpenLoad` notification userInfo. When
    /// non-nil and the current screen is 205 / 222, we construct that
    /// screen with the real loadId instead of the registry's `"0"`
    /// sentinel.
    @State private var activeLoadId: String? = nil
    /// Set when an action triggers SFSafariViewController to open a
    /// web continuation (load edit, settlement approve flow, etc.).
    /// Cleared when the sheet dismisses.
    @State private var webContinuationURL: URL? = nil

    /// Photos picker visibility — toggled by the avatar tap from the
    /// Me hero. The picked `PhotosPickerItem` resolves to JPEG `Data`
    /// in `.onChange`, gets uploaded as a base64 data URL via
    /// `profile.updateAvatar`, and the new URL is mirrored into the
    /// session user so the Me hero re-renders with the new image
    /// without a manual refresh.
    @State private var avatarPickerItem: PhotosPickerItem? = nil
    @State private var avatarPickerOpen: Bool = false

    private var current: ProductionScreen {
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

    var body: some View {
        // Body kept short to dodge SwiftUI's "compiler unable to
        // type-check this expression in reasonable time" timeout —
        // the surface previously chained 26+ modifiers on a single
        // expression which exceeds the type-checker's tractable
        // budget. Heavy work (back overlay, environment injections,
        // 15 onReceive subscribers, sheets) is split into private
        // ViewModifier types below.
        current.view(palette)
            .id("shipper-\(currentScreenId)")
            .transition(.opacity)
            .modifier(ShipperBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId
            ))
            .modifier(ShipperEnvInjections())
            .modifier(ShipperNotificationListeners(
                screenStack: $screenStack,
                activeLoadId: $activeLoadId,
                avatarPickerOpen: $avatarPickerOpen,
                showeSang: $showeSang,
                webContinuationURL: $webContinuationURL,
                pushOrTab: pushOrTab,
                popOne: popOne,
                handleMeAction: handleShipperMeAction
            ))
            .photosPicker(isPresented: $avatarPickerOpen,
                          selection: $avatarPickerItem,
                          matching: .images)
            .onChange(of: avatarPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await uploadShipperAvatar(item: newItem)
                    avatarPickerItem = nil
                }
            }
            .sheet(item: Binding<ShipperWebContinuationItem?>(
                get: { webContinuationURL.map(ShipperWebContinuationItem.init) },
                set: { webContinuationURL = $0?.url }
            )) { ident in
                SafariContinuationView(url: ident.url)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showeSang) {
                ShippereSangCoachSheet()
                    .environment(\.palette, palette)
                    .environmentObject(session)
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
            if let id = userInfo["partnerId"] as? String
                ?? userInfo["catalystId"] as? String {
                activeLoadId = id
            }
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

    // MARK: - Avatar upload

    /// Convert the picked photo to a JPEG data URL and ship it through
    /// `profile.updateAvatar`. The mutation persists `profilePicture`
    /// on the `users` row so web + iPad read the new image on next
    /// `profile.getMyProfile`. Best-effort — silent failure leaves
    /// the previous avatar in place.
    @MainActor
    private func uploadShipperAvatar(item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              !data.isEmpty else { return }
        // Compress to JPEG ≤ 200KB so the data-URL payload stays
        // reasonable for a tRPC string field. UIKit's
        // `UIImage(data:).jpegData(compressionQuality:)` produces a
        // smaller blob than the original PNG/HEIC the picker hands us.
        let bytes: Data = {
            #if canImport(UIKit)
            if let img = UIImage(data: data) {
                let target: CGFloat = 512
                let scale = min(target / img.size.width, target / img.size.height, 1)
                let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
                let renderer = UIGraphicsImageRenderer(size: size)
                let resized = renderer.image { _ in
                    img.draw(in: CGRect(origin: .zero, size: size))
                }
                if let jpeg = resized.jpegData(compressionQuality: 0.8) {
                    return jpeg
                }
            }
            #endif
            return data
        }()
        let dataURL = "data:image/jpeg;base64,\(bytes.base64EncodedString())"

        struct In: Encodable { let avatarUrl: String }
        struct Out: Decodable { let success: Bool; let avatarUrl: String }
        if let _: Out = try? await EusoTripAPI.shared.mutation(
            "profile.updateAvatar",
            input: In(avatarUrl: dataURL)
        ) {
            // Surface a refresh notification so any avatar-rendering
            // surface (Me hero, top-bar `duAvatar`, MeProfile card)
            // can re-fetch the profile and pick up the new picture.
            NotificationCenter.default.post(name: .eusoProfileAvatarUpdated, object: nil)
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
    let stackDepth: Int
    /// Screens that ship their own header back chevron — suppressing the
    /// surface overlay for these prevents the double-back collision the
    /// founder flagged 2026-04-30. Every other pushed screen gets the
    /// overlay so leaves like 222 Live Tracking, 226 Document Center,
    /// 106 EusoTickets, 064 Haul Leaderboard never strand the user.
    private static let screensWithOwnBack: Set<String> = [
        // 320 hub family draws its own "< Me" chevron in the header
        "320a", "320b", "320c", "320d", "320e", "320f", "320g",
        // Post-Load wizard has its own < chevron next to the title
        "204", "250", "251", "252", "253",
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
        // Founder back-button audit 2026-05-08 — both 203 (Bids)
        // and 223 (Agreements) draw their own header chevron AND
        // were getting the floating overlay on top. Added here so
        // only the in-screen back renders.
        "203", "223",
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
    }
}

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
    @Binding var avatarPickerOpen: Bool
    @Binding var showeSang: Bool
    @Binding var webContinuationURL: URL?
    let pushOrTab: (String) -> Void
    let popOne: () -> Void
    let handleMeAction: (String, [AnyHashable: Any]) -> Void

    func body(content: Content) -> some View {
        content
            .modifier(ShipperNavReceivers(
                screenStack: $screenStack,
                activeLoadId: $activeLoadId,
                avatarPickerOpen: $avatarPickerOpen,
                showeSang: $showeSang,
                pushOrTab: pushOrTab,
                popOne: popOne
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
    @Binding var avatarPickerOpen: Bool
    @Binding var showeSang: Bool
    let pushOrTab: (String) -> Void
    let popOne: () -> Void

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
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperNavBack)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) { popOne() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperAvatarPickRequested)) { _ in
                avatarPickerOpen = true
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
                    activeLoadId = nil
                    pushOrTab("224")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperLoadListOpen)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) {
                    activeLoadId = nil
                    pushOrTab("201")
                }
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
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperLoadOpen)) { note in
                guard let id = note.userInfo?["loadId"] as? String else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    activeLoadId = id
                    pushOrTab("205")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperLoadOpenMap)) { note in
                guard RoleAccess.canRender(role: .shipper, screenId: "222") else { return }
                if let id = note.userInfo?["loadId"] as? String { activeLoadId = id }
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab("222") }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperSettlementOpenLoad)) { note in
                guard let id = note.userInfo?["loadId"] as? String else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    activeLoadId = id
                    pushOrTab("205")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoShipperPostLoadDismiss)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) {
                    activeLoadId = nil
                    screenStack = ["200"]
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
        case "settlements":           return "206"
        case "settlement":            return "227"
        case "payment-methods",
             "payment-method":        return "208"
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
        case "loads":                 return "201"
        case "load":                  return "205"
        default:                      return nil
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
    /// Founder mandate 2026-05-05 — push/pop nav stack so leaf screens
    /// always have a back path. Bottom-nav tabs reset the stack to a
    /// single entry; non-tab screens append.
    @State private var screenStack: [String] = ["300"]
    @State private var showeSang: Bool = false
    private static let tabRoots: Set<String> = ["300", "301", "302", "303"]

    /// Carrier-side suppress list — same purpose as ShipperBackOverlay's
    /// `screensWithOwnBack`. Tab roots + leaves that draw their own
    /// header back chevron. Founder back-button audit 2026-05-08:
    /// 305 (Catalyst Load Detail) + 321 (Catalyst Driver Profile)
    /// each ship their own < chevron next to the title; without
    /// them in this set the surface overlay rendered a second back
    /// circle on top.
    private static let backSuppress: Set<String> = [
        "300", "301", "302", "303",   // tab roots
        "350",                          // CarrierMe (own dismiss)
        "305", "321",                   // detail screens with own back
    ]

    private var currentScreenId: String { screenStack.last ?? "300" }

    private var current: ProductionScreen {
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

    private func pushOrTab(_ id: String) {
        if Self.tabRoots.contains(id) { screenStack = [id]; return }
        if screenStack.last == id { return }
        screenStack.append(id)
    }
    private func popOne() { if screenStack.count > 1 { screenStack.removeLast() } }

    var body: some View {
        current.view(palette)
            .id("carrier-\(currentScreenId)")
            .transition(.opacity)
            .modifier(RoleNavBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId,
                screensWithOwnBack: Self.backSuppress
            ))
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler, nil)
            .environment(\.carrierNavHandler) { label in
                CarrierNavDispatcher.handle(label)
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoCarrierNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .catalyst, screenId: id) else {
                    screenStack = ["300"]; return
                }
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) { popOne() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoCarriereSangTapped)) { _ in
                showeSang = true
            }
            .sheet(isPresented: $showeSang) {
                DrivereSangCoachSheet().environment(\.palette, palette)
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
    private static let tabRoots: Set<String> = ["400", "401", "402", "403"]

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

    var body: some View {
        current.view(palette)
            .id("broker-\(currentScreenId)")
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
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) { popOne() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoBrokereSangTapped)) { _ in
                showeSang = true
            }
            .sheet(isPresented: $showeSang) {
                DrivereSangCoachSheet().environment(\.palette, palette)
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
    private static let tabRoots: Set<String> = ["600", "601", "602", "603"]

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

    var body: some View {
        current.view(palette)
            .id("escort-\(currentScreenId)")
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
            .onReceive(NotificationCenter.default.publisher(for: .eusoEscortNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .escort, screenId: id) else {
                    screenStack = ["600"]; return
                }
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) { popOne() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoEscorteSangTapped)) { _ in
                showeSang = true
            }
            .sheet(isPresented: $showeSang) {
                DrivereSangCoachSheet().environment(\.palette, palette)
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

    var body: some View {
        current.view(palette)
            .id("terminal-\(currentScreenId)")
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
            .onReceive(NotificationCenter.default.publisher(for: .eusoTerminalNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .terminal, screenId: id) else {
                    screenStack = ["700"]; return
                }
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) { popOne() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoTerminaleSangTapped)) { _ in
                showeSang = true
            }
            .sheet(isPresented: $showeSang) {
                DrivereSangCoachSheet().environment(\.palette, palette)
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
    private static let tabRoots: Set<String> = ["800", "801", "802", "803"]

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

    var body: some View {
        current.view(palette)
            .id("admin-\(currentScreenId)")
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
            .onReceive(NotificationCenter.default.publisher(for: .eusoAdminNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .admin, screenId: id) else {
                    screenStack = ["800"]; return
                }
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) { popOne() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoAdmineSangTapped)) { _ in
                showeSang = true
            }
            .sheet(isPresented: $showeSang) {
                DrivereSangCoachSheet().environment(\.palette, palette)
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
    @State private var screenStack: [String] = ["Dpch700"]
    @State private var showeSang: Bool = false
    private static let tabRoots: Set<String> = ["Dpch700", "Dpch701", "Dpch702", "Dpch703"]

    private var currentScreenId: String { screenStack.last ?? "Dpch700" }

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

    private func pushOrTab(_ id: String) {
        if Self.tabRoots.contains(id) { screenStack = [id]; return }
        if screenStack.last == id { return }
        screenStack.append(id)
    }
    private func popOne() { if screenStack.count > 1 { screenStack.removeLast() } }

    var body: some View {
        current.view(palette)
            .id("dispatch-\(currentScreenId)")
            .transition(.opacity)
            .modifier(RoleNavBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId,
                screensWithOwnBack: Self.tabRoots
            ))
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler, nil)
            .environment(\.dispatchNavHandler) { label in
                DispatchNavDispatcher.handle(label)
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoDispatchNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .dispatch, screenId: id) else {
                    screenStack = ["Dpch700"]; return
                }
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) { popOne() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoDispatcheSangTapped)) { _ in
                showeSang = true
            }
            .sheet(isPresented: $showeSang) {
                DrivereSangCoachSheet().environment(\.palette, palette)
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
    @State private var screenStack: [String] = ["900"]
    @State private var showeSang: Bool = false
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

    var body: some View {
        current.view(palette)
            .id("compliance-\(currentScreenId)")
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
            .onReceive(NotificationCenter.default.publisher(for: .eusoComplianceNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .compliance, screenId: id) else {
                    screenStack = ["900"]; return
                }
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) { popOne() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoComplianceeSangTapped)) { _ in
                showeSang = true
            }
            .sheet(isPresented: $showeSang) {
                DrivereSangCoachSheet().environment(\.palette, palette)
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
    private static let tabRoots: Set<String> = ["Rail550", "Rail551", "Rail552", "Rail553"]

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

    var body: some View {
        current.view(palette)
            .id("rail-\(currentScreenId)")
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
            .onReceive(NotificationCenter.default.publisher(for: .eusoRailNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .railEngineer, screenId: id) else {
                    screenStack = ["Rail550"]; return
                }
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) { popOne() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRaileSangTapped)) { _ in
                showeSang = true
            }
            .sheet(isPresented: $showeSang) {
                DrivereSangCoachSheet().environment(\.palette, palette)
            }
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
    private static let tabRoots: Set<String> = ["Vesl650", "Vesl651", "Vesl652", "Vesl653"]

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

    var body: some View {
        current.view(palette)
            .id("vessel-\(currentScreenId)")
            .transition(.opacity)
            .modifier(RoleNavBackOverlay(
                stackDepth: screenStack.count,
                currentScreenId: currentScreenId,
                screensWithOwnBack: Self.tabRoots
            ))
            .environment(\.driverNavHandler, nil)
            .environment(\.shipperNavHandler, nil)
            .environment(\.vesselOperatorNavHandler) { label in
                VesselOperatorNavDispatcher.handle(label)
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoVesselNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                guard RoleAccess.canRender(role: .vesselOperator, screenId: id) else {
                    screenStack = ["Vesl650"]; return
                }
                withAnimation(.easeInOut(duration: 0.22)) { pushOrTab(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) { popOne() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eusoVesseleSangTapped)) { _ in
                showeSang = true
            }
            .sheet(isPresented: $showeSang) {
                DrivereSangCoachSheet().environment(\.palette, palette)
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
        case .shipper, .railShipper, .vesselShipper:    return [.shipper]
        // Carrier-track backend roles can navigate into both the
        // canonical Carrier registry (300-320) AND the Catalyst
        // SpectraMatch sub-surface (500-502).
        case .catalyst, .railCatalyst:                  return [.carrier, .catalyst]
        case .vesselOperator:                           return [.vesselOperator]
        case .broker, .railBroker, .vesselBroker,
             .customsBroker:                            return [.broker]
        case .escort:                                   return [.escort]
        case .terminal, .portMaster:                    return [.terminal]
        case .admin, .superAdmin:                       return [.admin]
        case .compliance:                               return [.compliance]
        case .dispatch:                                 return [.dispatch]
        case .railEngineer:                             return [.railEngineer]
        // Roles below have no native chrome — they route to web
        // continuation in `RoleSurfaceRouter`. Empty list means
        // every cross-role swap is denied for them, which is the
        // correct outcome since their surface lives outside the
        // app entirely.
        case .safety, .factoring,
             .railDispatch, .railConductor,
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
        case .catalyst, .railCatalyst:
                                     return .carrier
        case .vesselOperator:        return .vesselOperator
        case .broker, .railBroker, .vesselBroker, .customsBroker:
                                     return .broker
        case .escort:                return .escort
        case .terminal, .portMaster: return .terminal
        case .admin, .superAdmin:    return .admin
        case .railEngineer:          return .railEngineer
        // Roles below have no chrome-role analog; map to a sentinel
        // (.driver) but RoleAccess.canRender still returns false for
        // them because none of their screen IDs are registered against
        // .driver. The router routes these to web continuation, never
        // through the registry path.
        case .dispatch, .compliance, .safety, .factoring,
             .railDispatch, .railConductor,
             .shipCaptain:
                                     return .driver
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
            Text("Drivers see the matching dock-cam, yardmap, and AR fallback paths light up automatically. Anything left blank stays as 'Pair hardware' on the driver side — the affordance never disappears.")
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
                        Text("· Door \(a.doorNumber) — \(a.vendor) (\(a.accessoryConfigData.prefix(8))…)")
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
                        Text("· Door \(f.doorNumber) — \(f.vendor)\(f.label.map { " · \($0)" } ?? "")")
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
                        Text("· Door \(m.doorNumber) — marker \(m.markerId) (offset \(m.offsetX, specifier: "%.2f")m, \(m.offsetY, specifier: "%.2f")m)")
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
                Text("Paste a Polygon, MultiPolygon, Feature, or FeatureCollection. Drivers see translucent dock-lane / staging-zone overlays on top of the HereMapView basemap.")
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
        let vc = SFSafariViewController(url: url)
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
