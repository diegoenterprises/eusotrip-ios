//
//  TileReveal.swift
//  EusoTrip — App-wide staggered "cafe-door" entrance primitive.
//
//  Wired per user direction:
//
//     > tiles animation ... it needs to be wired everywhere for uniformity
//     > and not just straight down tile. i want the elements coming from
//     > left to right like cafe doors. thats the uniform across the app.
//     >
//     > all screens use it
//     > that is the uniform animation for a screen when selected
//
//  Every screen in the app — Driver, Dispatch, Broker, Admin, Auth —
//  should present its content by dropping the root VStack in favor of
//  `TileStack { … }`. Children are automatically indexed and each child
//  swings in from an alternating side (odd index → left, even index →
//  right) while fading up, reading like saloon / cafe doors parting.
//
//  Opt-in surfaces:
//
//     1. `TileStack { … }` — drop-in replacement for the root VStack of
//        any screen. Auto-alternates horizontal entry sign per child.
//
//     2. `TileRow { … }` — horizontal variant. Children enter alternately
//        from top/bottom with a small lift so a chip row still has the
//        cafe-door feel without fighting the horizontal axis.
//
//     3. `.cafeDoorReveal(index:)` — manual variant for free-form layouts
//        (e.g. ZStack, LazyVGrid rows, list sections that can't be a
//        direct child of TileStack).
//
//     4. `.screenTileSurface()` — coarse fallback on screens built around
//        a single bespoke form. A soft horizontal slide-up for the whole
//        surface so even screens without a tile breakdown feel part of
//        the cafe-door family.
//
//  Respects `@Environment(\.accessibilityReduceMotion)`: when Reduce
//  Motion is on, all offset/scale components collapse to an instant
//  fade so the branded feel is preserved but motion is honored.
//
//  SwiftUI twin of the web platform's `TileReveal` / `useTileReveal`
//  hook in `frontend/client/src/hooks/useTileReveal.ts`.
//

import SwiftUI

// MARK: - Tokens

public enum TileReveal {
    /// Per-child stagger (seconds) between successive tiles.
    /// 55 ms reads as "elements land one after another" without feeling
    /// slow on a tall list.
    public static let stagger: Double = 0.055

    /// Base delay (seconds) applied to the first tile — keeps the
    /// animation from starting *exactly* at onAppear so the transition
    /// between screens breathes.
    public static let baseDelay: Double = 0.04

    /// Vertical offset (pt) tiles start from. Small — the story is the
    /// horizontal swing, the lift is just seasoning.
    public static let distance: CGFloat = 10

    /// Horizontal offset (pt) tiles start from — this is what makes the
    /// door swing. Alternates sign by index so odd tiles come from the
    /// left and even tiles come from the right.
    public static let horizontalDistance: CGFloat = 32

    /// Scale tiles enter from. Anchored to the *leading*/trailing edge
    /// inside the modifier so the scale reads as a door-swing rather
    /// than a center zoom.
    public static let scaleStart: CGFloat = 0.985

    /// Entrance duration (seconds). Long-tailed easeOut so the final
    /// pixels of the swing settle cleanly.
    public static let duration: Double = 0.46

    /// Cap on stagger delay. Long lists (40+ rows) shouldn't take
    /// >1.5s to finish entering, so we clamp the effective index.
    public static let maxDelay: Double = 1.2
}

// MARK: - Core modifier (single view)

/// Cafe-door reveal: a view fades, lifts, scales and slides in
/// horizontally from an alternating side. Safe on any view; a second
/// onAppear (e.g. from sheet re-show or cell reuse) is a no-op so the
/// animation doesn't re-trigger on scroll.
public struct TileRevealModifier: ViewModifier {
    let delay: Double
    let distance: CGFloat
    let horizontalDistance: CGFloat
    /// +1 = swing from the right, -1 = swing from the left.
    let horizontalSign: CGFloat
    let scaleStart: CGFloat
    let duration: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool = false

    public init(delay: Double,
                distance: CGFloat = TileReveal.distance,
                horizontalDistance: CGFloat = TileReveal.horizontalDistance,
                horizontalSign: CGFloat = -1,
                scaleStart: CGFloat = TileReveal.scaleStart,
                duration: Double = TileReveal.duration) {
        self.delay = min(delay, TileReveal.maxDelay)
        self.distance = distance
        self.horizontalDistance = horizontalDistance
        self.horizontalSign = horizontalSign >= 0 ? 1 : -1
        self.scaleStart = scaleStart
        self.duration = duration
    }

    /// Unit anchor matching the swing side so the scale looks like a
    /// door hinge rather than a center zoom. Left-entry tiles hinge at
    /// the leading edge, right-entry tiles hinge at the trailing edge.
    private var anchor: UnitPoint {
        horizontalSign < 0 ? .leading : .trailing
    }

    public func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(
                x: shown ? 0 : (reduceMotion ? 0 : horizontalSign * horizontalDistance),
                y: shown ? 0 : (reduceMotion ? 0 : distance)
            )
            .scaleEffect(shown ? 1 : (reduceMotion ? 1 : scaleStart),
                         anchor: anchor)
            .onAppear {
                guard !shown else { return }
                let ramp: Animation = reduceMotion
                    ? .easeOut(duration: 0.18)
                    : .easeOut(duration: duration)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(ramp) { shown = true }
                }
            }
    }
}

public extension View {
    /// Cafe-door staggered entrance. Use inside a `TileStack`/`TileRow`
    /// (auto-indexed), or manually with an explicit index for free-form
    /// layouts. Odd indices swing in from the left, even indices from
    /// the right — matching the uniform pattern used across the app.
    func cafeDoorReveal(index: Int,
                        stagger: Double = TileReveal.stagger,
                        baseDelay: Double = TileReveal.baseDelay) -> some View {
        let sign: CGFloat = (index % 2 == 0) ? -1 : 1
        return modifier(TileRevealModifier(
            delay: baseDelay + stagger * Double(index),
            horizontalSign: sign
        ))
    }

    /// Backwards-compatible alias — older callers that still say
    /// `.tileReveal(index:)` keep working, and now get the cafe-door
    /// swing automatically.
    func tileReveal(index: Int,
                    stagger: Double = TileReveal.stagger,
                    baseDelay: Double = TileReveal.baseDelay) -> some View {
        cafeDoorReveal(index: index, stagger: stagger, baseDelay: baseDelay)
    }

    /// Shorthand when you already have the exact delay — useful for a
    /// hero element that should land ahead of the rest. Swings from
    /// the left by default, since hero items are usually leading-aligned.
    func tileReveal(delay: Double,
                    fromLeft: Bool = true) -> some View {
        modifier(TileRevealModifier(
            delay: delay,
            horizontalSign: fromLeft ? -1 : 1
        ))
    }

    /// Screen-level entrance — a single fade-up-and-in for the whole
    /// surface. Use on screens that can't easily break into child tiles
    /// (e.g. Auth screens built around a single form). Also the default
    /// animation applied to every screen on selection via
    /// `.screenTileRoot()` — see below.
    func screenTileSurface(delay: Double = 0) -> some View {
        modifier(TileRevealModifier(
            delay: delay,
            distance: 8,
            horizontalDistance: 24,
            horizontalSign: -1,
            scaleStart: 0.995,
            duration: 0.5
        ))
    }

    /// Root-level screen animation. Applies the screen-surface fade so
    /// *every* screen in the app, on selection, slides into place — the
    /// uniform cafe-door feel at the surface level even for screens that
    /// don't yet adopt TileStack.
    func screenTileRoot() -> some View {
        modifier(TileRevealModifier(
            delay: 0,
            distance: 8,
            horizontalDistance: 24,
            horizontalSign: -1,
            scaleStart: 0.997,
            duration: 0.5
        ))
    }
}

// MARK: - TileStack — auto-indexed VStack with cafe-door entry

/// VStack-flavor container that applies a staggered cafe-door reveal to
/// each child in source order. Drop-in replacement for `VStack` when
/// you want the EusoTrip uniform screen-load-in effect.
///
/// ```
/// TileStack(alignment: .leading, spacing: Space.s5) {
///     Header()         // swings in from the left
///     MetricRow()      // swings in from the right
///     RecentSection()  // swings in from the left
/// }
/// ```
public struct TileStack<Content: View>: View {
    public let alignment: HorizontalAlignment
    public let spacing: CGFloat?
    public let stagger: Double
    public let baseDelay: Double
    public let content: Content

    public init(alignment: HorizontalAlignment = .leading,
                spacing: CGFloat? = nil,
                stagger: Double = TileReveal.stagger,
                baseDelay: Double = TileReveal.baseDelay,
                @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.stagger = stagger
        self.baseDelay = baseDelay
        self.content = content()
    }

    public var body: some View {
        _VariadicView.Tree(
            TileStackLayout(
                alignment: alignment,
                spacing: spacing,
                stagger: stagger,
                baseDelay: baseDelay
            )
        ) {
            content
        }
    }
}

/// HStack-flavor twin of `TileStack`. Children enter with alternating
/// vertical lift so a horizontal card row still reads as cafe-door
/// rather than a conveyor belt.
public struct TileRow<Content: View>: View {
    public let alignment: VerticalAlignment
    public let spacing: CGFloat?
    public let stagger: Double
    public let baseDelay: Double
    public let content: Content

    public init(alignment: VerticalAlignment = .center,
                spacing: CGFloat? = nil,
                stagger: Double = TileReveal.stagger,
                baseDelay: Double = TileReveal.baseDelay,
                @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.stagger = stagger
        self.baseDelay = baseDelay
        self.content = content()
    }

    public var body: some View {
        _VariadicView.Tree(
            TileRowLayout(
                alignment: alignment,
                spacing: spacing,
                stagger: stagger,
                baseDelay: baseDelay
            )
        ) {
            content
        }
    }
}

// MARK: - _VariadicView roots

private struct TileStackLayout: _VariadicView_MultiViewRoot {
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let stagger: Double
    let baseDelay: Double

    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        VStack(alignment: alignment, spacing: spacing) {
            ForEach(Array(children.enumerated()), id: \.element.id) { idx, child in
                let sign: CGFloat = (idx % 2 == 0) ? -1 : 1
                child
                    .modifier(TileRevealModifier(
                        delay: baseDelay + stagger * Double(idx),
                        horizontalSign: sign
                    ))
            }
        }
    }
}

private struct TileRowLayout: _VariadicView_MultiViewRoot {
    let alignment: VerticalAlignment
    let spacing: CGFloat?
    let stagger: Double
    let baseDelay: Double

    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        HStack(alignment: alignment, spacing: spacing) {
            ForEach(Array(children.enumerated()), id: \.element.id) { idx, child in
                // In a row the "swing" reads better as a horizontal slide
                // from the direction each tile came from, but with a
                // slight lift so it still feels like a door — alternate
                // vertical sign so chips don't look like a conveyor belt.
                let sign: CGFloat = (idx % 2 == 0) ? -1 : 1
                child
                    .modifier(TileRevealModifier(
                        delay: baseDelay + stagger * Double(idx),
                        distance: 6 * sign,
                        horizontalDistance: TileReveal.horizontalDistance * 0.6,
                        horizontalSign: sign
                    ))
            }
        }
    }
}

// MARK: - Screen-level helper

/// Wraps any view so its whole content fades up with a small lift when
/// the screen first appears. Use on screens that can't easily adopt
/// `TileStack` (e.g. screens built around a single bespoke form). Safe
/// to combine with `TileStack` children — the child stagger runs in
/// parallel with the outer surface fade.
public struct ScreenTileSurface<Content: View>: View {
    public let content: Content
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    public var body: some View {
        content.screenTileSurface()
    }
}
