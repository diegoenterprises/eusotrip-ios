//
//  StaggeredEntrance.swift
//  EusoTrip — the iPhone-unlock home entrance primitive (Views/Components).
//
//  Founder direction:
//
//     > on FIRST app load, the role-home screen elements should animate in
//     > "exactly like the iPhone home screen when you unlock the phone —
//     > in separate pieces."
//
//  The researched motion (matches the SpringBoard unlock cascade):
//    • each element starts at ~0.92 scale + ~0.75 opacity + a subtle
//      ~5pt Gaussian blur;
//    • it then SPRINGS into place (response ~0.65, dampingFraction ~0.75);
//    • a PER-ELEMENT STAGGER (~50 ms) cascades the pieces top-to-bottom
//      so the home assembles itself "in separate pieces" rather than as a
//      single block.
//
//  This is deliberately a DIFFERENT motion from `TileReveal`'s cafe-door
//  swing — cafe-door fires on every screen selection for uniformity; the
//  unlock cascade fires ONCE per cold launch, only on the role-home, as a
//  branded "welcome back" moment. The two never fight: a home can run the
//  unlock cascade on first load and never again, while inner surfaces keep
//  their cafe-door reveals.
//
//  FIRST-LOAD-ONLY gate — the cascade plays on APP COLD-LAUNCH, not on
//  every navigation back to Home. A process-wide static flag
//  (`StaggeredEntrance.didPlayHomeEntrance`) is flipped the first time any
//  role-home mounts the cascade; every later mount in the same process
//  resolves instantly to the settled state (no replay). The flag lives for
//  the lifetime of the process, so a true cold launch (process restart)
//  replays it, while a warm tab-switch / push-pop back to Home does not.
//
//  Reduce Motion — when the system asks for reduced motion we drop the
//  scale + blur + spring entirely and use a clean 200 ms opacity fade
//  only, so the vestibular zoom/blur trigger never fires.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Tokens + first-load gate

public enum StaggeredEntrance {

    // — Researched unlock-cascade physics —

    /// Scale each element enters from (zoom-up to settle). 0.92 reads as
    /// "pieces snapping forward into place" without an overshoot pop.
    public static let scaleStart: CGFloat = 0.92

    /// Opacity each element enters from. 0.75 (not 0) keeps the cascade
    /// feeling like the home "resolving into focus" rather than fading in
    /// from black — the SpringBoard unlock never fully hides its tiles.
    public static let opacityStart: Double = 0.75

    /// Gaussian blur (pt) each element enters with, melting to 0 on
    /// settle — the subtle "coming into focus" of the unlock animation.
    public static let blurStart: CGFloat = 5

    /// Spring response (seconds). 0.65 = a relaxed, premium settle.
    public static let response: Double = 0.65

    /// Spring damping fraction. 0.75 = a hair of life at the end without a
    /// bouncy overshoot.
    public static let damping: Double = 0.75

    /// Per-element stagger (seconds) between successive pieces — the
    /// top-to-bottom cascade. ~50 ms reads as "separate pieces" landing
    /// one after another.
    public static let stagger: Double = 0.05

    /// Base delay (seconds) before the first piece moves — lets the home
    /// frame settle a beat before the cascade begins.
    public static let baseDelay: Double = 0.02

    /// Cap on the cascade delay so a tall home (many sections) still
    /// finishes the welcome within a beat instead of trickling for a
    /// second-plus.
    public static let maxDelay: Double = 0.9

    /// Reduce-Motion fade duration — a clean fade, no scale/blur/spring.
    public static let reducedFade: Double = 0.20

    // — First-load-only gate —

    /// Process-wide flag: set TRUE the first time any role-home plays the
    /// unlock cascade. Re-visiting Home in the same session (tab switch,
    /// push-pop back) sees this already TRUE and renders settled instantly
    /// — no replay. A real cold launch starts a fresh process, so the flag
    /// is FALSE again and the cascade plays once more. Touched only on the
    /// main actor (view body / onAppear), so the plain static is safe.
    public static var didPlayHomeEntrance: Bool = false
}

// MARK: - Per-element modifier

/// Applies the iPhone-unlock entrance to a single view: it starts scaled
/// down, dimmed and blurred, then springs to its settled state after a
/// per-index delay. Fires ONCE per first mount (a re-`onAppear` from cell
/// reuse / sheet re-show is a no-op). Reduce-Motion collapses it to a
/// clean opacity fade.
public struct StaggeredEntranceModifier: ViewModifier {
    /// Stagger position (0 = first piece, top of the cascade).
    let index: Int
    /// Total siblings — reserved for future easing curves; the cascade is
    /// linear-staggered today, but keeping `total` in the signature lets a
    /// caller balance the delay over a known count without a breaking
    /// change later.
    let total: Int
    let stagger: Double
    let baseDelay: Double

    /// When TRUE this element already played its cascade earlier in the
    /// session, so it mounts settled with no animation — the first-load
    /// gate. Defaults to honoring the process flag.
    let alreadyPlayed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool = false

    public init(index: Int,
                total: Int,
                stagger: Double = StaggeredEntrance.stagger,
                baseDelay: Double = StaggeredEntrance.baseDelay,
                alreadyPlayed: Bool = StaggeredEntrance.didPlayHomeEntrance) {
        self.index = max(0, index)
        self.total = max(1, total)
        self.stagger = stagger
        self.baseDelay = baseDelay
        self.alreadyPlayed = alreadyPlayed
    }

    private var delay: Double {
        min(baseDelay + stagger * Double(index), StaggeredEntrance.maxDelay)
    }

    public func body(content: Content) -> some View {
        // If the cascade already played this session, render settled with
        // no per-element animation at all — the first-load gate.
        let settled = shown || alreadyPlayed

        return content
            .opacity(settled ? 1 : (reduceMotion ? 0 : StaggeredEntrance.opacityStart))
            .scaleEffect(settled ? 1 : (reduceMotion ? 1 : StaggeredEntrance.scaleStart))
            .blur(radius: settled ? 0 : (reduceMotion ? 0 : StaggeredEntrance.blurStart))
            .onAppear {
                // Guard 1 — already settled (gate hit): jump to shown so
                // any subsequent layout pass keeps the settled state, no
                // animation.
                guard !alreadyPlayed else {
                    shown = true
                    return
                }
                // Guard 2 — this instance already ran (re-onAppear from
                // reuse): no-op so the cascade never re-triggers on scroll.
                guard !shown else { return }

                if reduceMotion {
                    // Reduce-Motion: clean 200 ms fade, no scale/blur/spring.
                    withAnimation(.easeOut(duration: StaggeredEntrance.reducedFade)) {
                        shown = true
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        withAnimation(.spring(response: StaggeredEntrance.response,
                                              dampingFraction: StaggeredEntrance.damping)) {
                            shown = true
                        }
                    }
                }
            }
    }
}

public extension View {
    /// Manual unlock-cascade entrance for free-form layouts (ZStack rows,
    /// grid rows, or sections that can't be a direct child of a
    /// `StaggeredEntranceStack`). Pass the section's `index` (0 = top) and
    /// the `total` number of staggered siblings.
    ///
    /// Honors the process-wide first-load gate by default: if the cascade
    /// already played this session, the element mounts settled with no
    /// animation. Reduce-Motion → clean fade.
    func staggeredEntrance(index: Int,
                           total: Int,
                           stagger: Double = StaggeredEntrance.stagger,
                           baseDelay: Double = StaggeredEntrance.baseDelay) -> some View {
        modifier(StaggeredEntranceModifier(index: index,
                                           total: total,
                                           stagger: stagger,
                                           baseDelay: baseDelay))
    }
}

// MARK: - StaggeredEntranceStack — auto-indexed unlock cascade

/// VStack-flavor container that plays the iPhone-unlock entrance on each
/// child in source order, top-to-bottom, ONCE per cold launch. Drop-in
/// replacement for the top-level VStack of a role-home's sections.
///
/// ```
/// StaggeredEntranceStack(alignment: .leading, spacing: Space.s5) {
///     RoleHomeIntro()    // piece 0 — springs in first
///     MetricRow()        // piece 1 — ~50 ms later
///     RecentSection()    // piece 2 — ~50 ms later again
/// }
/// ```
///
/// The container reads the process-wide `didPlayHomeEntrance` flag at
/// mount: the first home to mount plays the cascade and trips the flag, so
/// every later home mount (tab switch / push-pop back) renders settled
/// instantly. Reduce-Motion → clean per-piece fade.
public struct StaggeredEntranceStack<Content: View>: View {
    public let alignment: HorizontalAlignment
    public let spacing: CGFloat?
    public let stagger: Double
    public let baseDelay: Double
    public let content: Content

    /// Snapshot of the gate taken when this stack is *constructed*. The
    /// first home to build flips the static flag in `onAppear` (below); we
    /// capture the pre-flip value here so this stack's children animate,
    /// while any home constructed afterward in the same session sees the
    /// flag already TRUE and renders settled.
    private let playedAtBuild: Bool = StaggeredEntrance.didPlayHomeEntrance

    public init(alignment: HorizontalAlignment = .leading,
                spacing: CGFloat? = nil,
                stagger: Double = StaggeredEntrance.stagger,
                baseDelay: Double = StaggeredEntrance.baseDelay,
                @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.stagger = stagger
        self.baseDelay = baseDelay
        self.content = content()
    }

    public var body: some View {
        _VariadicView.Tree(
            StaggeredEntranceLayout(
                alignment: alignment,
                spacing: spacing,
                stagger: stagger,
                baseDelay: baseDelay,
                alreadyPlayed: playedAtBuild
            )
        ) {
            content
        }
        .onAppear {
            // Trip the process-wide gate once the first home mounts, so any
            // later home (or a re-visit to this one) renders settled.
            if !StaggeredEntrance.didPlayHomeEntrance {
                StaggeredEntrance.didPlayHomeEntrance = true
            }
        }
    }
}

// MARK: - _VariadicView root

private struct StaggeredEntranceLayout: _VariadicView_MultiViewRoot {
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let stagger: Double
    let baseDelay: Double
    /// The gate value captured when the owning stack was built. Passed to
    /// each child modifier so a stack built after the cascade already ran
    /// renders every child settled.
    let alreadyPlayed: Bool

    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let total = children.count
        VStack(alignment: alignment, spacing: spacing) {
            ForEach(Array(children.enumerated()), id: \.element.id) { idx, child in
                child
                    .modifier(StaggeredEntranceModifier(
                        index: idx,
                        total: total,
                        stagger: stagger,
                        baseDelay: baseDelay,
                        alreadyPlayed: alreadyPlayed
                    ))
            }
        }
    }
}
