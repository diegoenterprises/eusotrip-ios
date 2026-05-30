//
//  RoleDetailPush.swift
//  EusoTrip — the SHARED sheet→push detail primitive.
//
//  Why this primitive exists:
//  -------------------------
//  Every standard role surface in `RoleSurfaceRouter` is a notification-
//  driven `screenStack: [String]` router. It pushes REGISTERED screens
//  by id. But many detail surfaces are inline structs (ContractDetail,
//  ClaimDetail, BookingDetail, …) carrying rich runtime data (a row
//  model, a binding) that doesn't reduce cleanly to a registry id +
//  string token. Registering one screen per inline detail is wasteful.
//
//  Instead, each surface owns a single generic detail LAYER: a screen
//  calls `\.rolePushDetail(title:) { AnyView(...) }` and the surface
//  renders that view IN-STACK — slid in from the trailing edge, topped
//  with a `BespokeBackBar`, above the current screen. Back posts the
//  role's `eusoXxxNavBack` (or the shared `eusoRoleNavBack`); the
//  surface clears the detail layer FIRST, else pops `screenStack`. This
//  stays entirely within the existing notification router — no SwiftUI
//  `NavigationStack`, and the BottomNav design is untouched.
//
//  This file is the ONE implementation. It started life Shipper-only
//  (`ShipperDetailPush` / `\.shipperPushDetail` / `ShipperDetailLayer`)
//  and was promoted here per the 2026-05-30 NAV remediation spec so
//  every role surface (Carrier, Broker, Dispatch, Escort, Terminal,
//  Admin, Compliance, Rail, Vessel — and Shipper) reuses the identical
//  mechanism. `\.shipperPushDetail` is now a thin alias onto the shared
//  `\.rolePushDetail` key so the four already-converted Shipper screens
//  keep working without change.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - The pushed detail model

/// One pushed detail layer. `id` lets SwiftUI diff/transition between
/// successive pushes; `title` feeds the `BespokeBackBar` (pass nil for
/// chevron-only); `content` is the caller-built body (already carrying
/// its own data wiring). Role-agnostic — identical for every surface.
struct RoleDetailPush: Identifiable {
    let id = UUID()
    let title: String?
    let content: AnyView
}

// MARK: - Shared push environment key

/// Environment closure a screen on ANY standard role surface invokes to
/// push an inline detail view in-stack (sheet→push). Signature mirrors
/// the simple `(String) -> Void` nav handlers so screens depend only on
/// the environment, never on the surface type. Nil outside a surface
/// that installs `RoleDetailLayer`.
struct RolePushDetailKey: EnvironmentKey {
    static let defaultValue: ((String?, @escaping () -> AnyView) -> Void)? = nil
}

extension EnvironmentValues {
    /// Push an inline detail in-stack. `title` feeds the back bar (pass
    /// nil to render chevron-only); the closure builds the body.
    ///
    ///     @Environment(\.rolePushDetail) private var pushDetail
    ///     ...
    ///     pushDetail?("Contract") { AnyView(ContractDetailBody(row: row)) }
    ///
    /// The surface wraps the result with `BespokeBackBar` automatically
    /// and animates the slide-in; callers must NOT add their own bar.
    var rolePushDetail: ((String?, @escaping () -> AnyView) -> Void)? {
        get { self[RolePushDetailKey.self] }
        set { self[RolePushDetailKey.self] = newValue }
    }
}

// MARK: - Shared detail layer view-modifier

/// Renders the surface-owned `pushedDetail` ABOVE the current screen,
/// slid in from the trailing edge and topped with a `BespokeBackBar`.
/// Also injects the `\.rolePushDetail` environment closure that screens
/// call to push an inline detail in-stack.
///
/// The surface supplies:
///   • `pushedDetail` — its `@State` binding (truth lives on the surface
///     so its NavBack receiver can clear it before popping `screenStack`).
///   • `palette` — the active theme palette (the `bgPage` underlay makes
///     the slide-in opaque so the screen beneath is fully covered while
///     it animates).
///   • `onBack` — posts the role's correct NavBack notification. The bar
///     fires it; the surface's NavBack receiver does the detail-first
///     dismissal (clear `pushedDetail`, else pop). `onBack` should NOT
///     animate — the surface owns the pop animation (avoids double-anim).
///
/// Usage (in a role surface body):
///
///     .modifier(RoleDetailLayer(
///         pushedDetail: $pushedDetail,
///         palette: palette,
///         onBack: { NotificationCenter.default.post(
///             name: .eusoCarrierNavBack, object: nil) }
///     ))
///
/// This is the Shipper mechanism, parameterized — exactly one
/// implementation for the whole app.
struct RoleDetailLayer: ViewModifier {
    @Binding var pushedDetail: RoleDetailPush?
    let palette: Theme.Palette
    /// Posts the role's NavBack notification. Invoked by the back bar.
    let onBack: () -> Void

    func body(content: Content) -> some View {
        ZStack {
            content
            if let detail = pushedDetail {
                detail.content
                    .injectBespokeBackBar(title: detail.title, onBack: onBack)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.bgPage.ignoresSafeArea())
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .environment(\.rolePushDetail) { title, builder in
            withAnimation(.easeInOut(duration: 0.28)) {
                pushedDetail = RoleDetailPush(title: title, content: builder())
            }
        }
    }
}
