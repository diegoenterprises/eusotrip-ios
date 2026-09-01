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

// MARK: - Shared edge-swipe back gesture

/// Mirrors iOS' interactive-pop intent for EusoTrip's notification-driven
/// role stacks. The gesture only begins at the physical leading edge and must
/// be decisively horizontal, so maps, sliders, boards, and ordinary scrolling
/// keep ownership of their gestures.
struct EusoEdgeSwipeBack: ViewModifier {
    let isEnabled: Bool
    let onBack: () -> Void

    @GestureState private var dragTranslation: CGFloat = 0

    private var interactiveOffset: CGFloat {
        guard isEnabled else { return 0 }
        return max(0, dragTranslation)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                // Follow the finger only after the gesture proves it began at
                // the leading edge and is decisively horizontal. Horizontal
                // boards, maps, sliders, and carousels elsewhere keep their
                // normal gesture ownership.
                .contentShape(Rectangle())
                .offset(x: interactiveOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .global)
                    .updating($dragTranslation) { value, state, _ in
                        let horizontal = value.translation.width
                        let vertical = abs(value.translation.height)
                        guard value.startLocation.x <= 36,
                              horizontal > 0,
                              horizontal > vertical * 1.25 else { return }
                        state = horizontal
                    }
                    .onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = abs(value.translation.height)
                        guard value.startLocation.x <= 36,
                              horizontal >= 72,
                              horizontal > vertical * 1.25,
                              value.predictedEndTranslation.width >= 90 else { return }
                        onBack()
                    }
                )
        } else {
            content
        }
    }
}

// MARK: - Shared role navigation path semantics

/// The state machine for every notification-driven role stack. Role surfaces
/// still own their route payloads, but tab selection, push de-duplication, and
/// guarded pop behavior live here so explicit back and edge-swipe back cannot
/// drift into different navigation semantics.
enum RoleNavigationPathContract {
    static func activeTab(
        in stack: [String],
        tabRoots: Set<String>,
        fallback: String
    ) -> String {
        guard let root = stack.first, tabRoots.contains(root) else { return fallback }
        return root
    }

    static func open(
        _ destination: String,
        tabRoots: Set<String>,
        fallback: String,
        stack: inout [String]
    ) {
        guard !destination.isEmpty else { return }
        if tabRoots.contains(destination) {
            stack = [destination]
            return
        }
        if stack.first.map({ !tabRoots.contains($0) }) ?? true {
            stack = [fallback]
        }
        guard stack.last != destination else { return }
        stack.append(destination)
    }

    @discardableResult
    static func pop(_ stack: inout [String]) -> Bool {
        guard stack.count > 1 else { return false }
        stack.removeLast()
        return true
    }

    static func canPop(_ stack: [String]) -> Bool {
        stack.count > 1
    }
}

/// Restores a notification-driven screen to the row that launched its child.
/// The first scroll seats the expanded hub; the delayed scroll waits for the
/// accordion body to enter the hierarchy before targeting the exact row.
@MainActor
func eusoRestoreScrollPosition(
    using proxy: ScrollViewProxy,
    anchor: String,
    fallback: String
) {
    guard !anchor.isEmpty, !fallback.isEmpty else { return }
    DispatchQueue.main.async {
        proxy.scrollTo(fallback, anchor: .top)
        guard anchor != fallback else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            proxy.scrollTo(anchor, anchor: .center)
        }
    }
}

private struct EusoRoleDetailPresentedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var eusoRoleDetailPresented: Bool {
        get { self[EusoRoleDetailPresentedKey.self] }
        set { self[EusoRoleDetailPresentedKey.self] = newValue }
    }
}

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
                // A pushed detail is the sole interactive surface while it is
                // visible. This also prevents an underlying stack owner's
                // simultaneous edge gesture from firing alongside the detail
                // gesture and popping two levels on one swipe.
                .allowsHitTesting(pushedDetail == nil)
            if let detail = pushedDetail {
                detail.content
                    .eusoRefreshSurface("role-detail:\(detail.id.uuidString)")
                    .injectBespokeBackBar(title: detail.title, onBack: onBack)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.bgPage.ignoresSafeArea())
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .modifier(EusoEdgeSwipeBack(
            isEnabled: pushedDetail != nil,
            onBack: onBack
        ))
        .environment(\.eusoRoleDetailPresented, pushedDetail != nil)
        .environment(\.rolePushDetail) { title, builder in
            withAnimation(.easeInOut(duration: 0.22)) {
                pushedDetail = RoleDetailPush(title: title, content: builder())
            }
        }
    }
}
