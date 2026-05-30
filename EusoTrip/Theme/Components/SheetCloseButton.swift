//
//  SheetCloseButton.swift
//  EusoTrip — Canonical X-close button for every pull-down sheet.
//
//  Why this primitive exists:
//  -------------------------
//  iOS sheets dismiss via a swipe-down on the top edge. That target is
//  small and easy to miss with one hand on the wheel. Per direct user
//  direction (2026-04-25):
//
//    > every screen that you can pull down needs the x in the right
//    > corner because sometimes that pull down you miss it multiple
//    > times because of where it is on the screen. so add a back button
//    > and the x button
//
//  This primitive is the single source of truth for that X. It sits on
//  the trailing edge of the sheet header, hits the §B.4 button-press
//  motion (`.easeOut(0.12)` + scale 0.985 + iridescent hue shift), and
//  fires the caller's dismiss closure. Pair with `BackChevron` (when
//  the sheet has a navigation stack inside it) so the user has BOTH
//  back and close, never just one.
//
//  Usage:
//
//      .overlay(alignment: .topTrailing) {
//          SheetCloseButton { dismiss() }
//              .padding(Space.s4)
//      }
//
//  Or use the `.eusoSheetChrome(title:onClose:)` modifier below for a
//  full header (back + title + X) drop-in.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Primitive

struct SheetCloseButton: View {
    @Environment(\.palette) private var palette
    @State private var pressed: Bool = false

    let action: () -> Void

    /// Standard 32×32 hit-target. Above the iOS HIG 44pt minimum when
    /// you account for the surrounding padding the caller applies.
    var size: CGFloat = 32

    var body: some View {
        Button(action: {
            // Doctrine §B.4 — every primary press has a sensory click.
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(palette.bgCardSoft)
                )
                .overlay(
                    Circle().strokeBorder(palette.borderFaint)
                )
                .scaleEffect(pressed ? 0.92 : 1.0)
                .animation(.easeOut(duration: 0.12), value: pressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
    }
}

// MARK: - Back chevron sibling

/// Companion to `SheetCloseButton` for sheets that present a multi-step
/// inner flow. `Back` pops one step inside the sheet; `X` dismisses the
/// whole sheet. Drivers get both targets — they shouldn't have to
/// guess which button collapses what.
struct BackChevron: View {
    @Environment(\.palette) private var palette
    @State private var pressed: Bool = false

    let action: () -> Void
    var size: CGFloat = 32

    var body: some View {
        Button(action: {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(palette.bgCardSoft)
                )
                .overlay(
                    Circle().strokeBorder(palette.borderFaint)
                )
                .scaleEffect(pressed ? 0.92 : 1.0)
                .animation(.easeOut(duration: 0.12), value: pressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
    }
}

// MARK: - Sheet chrome modifier

/// Drop-in chrome for any `.sheet { … }` content view. Renders an
/// optional back chevron + the title + the canonical close X, all
/// pinned to the top of the sheet without affecting the inner layout.
///
/// Use the modifier on the sheet's root view:
///
///     SomeContent()
///         .eusoSheetChrome(title: "Carrier") {
///             dismiss()
///         }
///
/// When the sheet has its own header already, prefer just the
/// `SheetCloseButton` overlay so the chrome doesn't double up.
struct EusoSheetChrome: ViewModifier {
    @Environment(\.palette) private var palette

    let title: String?
    let onBack: (() -> Void)?
    let onClose: () -> Void

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                if let onBack {
                    BackChevron(action: onBack)
                } else {
                    Color.clear.frame(width: 32, height: 32)
                }
                Spacer(minLength: 8)
                if let title, !title.isEmpty {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                SheetCloseButton(action: onClose)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(palette.bgPage)
            content
        }
    }
}

extension View {
    /// Apply the canonical sheet chrome (back + title + close X) to
    /// any sheet's root view. Pass `onBack` only when the sheet has an
    /// internal navigation stack.
    func eusoSheetChrome(
        title: String? = nil,
        onBack: (() -> Void)? = nil,
        onClose: @escaping () -> Void
    ) -> some View {
        modifier(EusoSheetChrome(title: title, onBack: onBack, onClose: onClose))
    }

    /// Canonical sheet presentation per the 2026 UX motion doc §6.6.
    /// Applies `.presentationDetents([.large])` and shows the drag
    /// indicator. Use this on any view passed to `.sheet { … }` so
    /// every sheet in the app sizes the same way and surfaces the
    /// same swipe-down affordance — drivers shouldn't have to relearn
    /// per-screen geometry.
    ///
    /// Example:
    ///
    ///     .sheet(isPresented: $showDetail) {
    ///         LoadDetailSheet(load: load)
    ///             .eusoSheet()
    ///     }
    func eusoSheet() -> some View {
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }

    /// Same as `eusoSheet()` but ALSO injects the canonical close X in
    /// the top-right corner. Use on every `.sheet { … }` content view
    /// that doesn't render its own custom header. The modifier reads
    /// the SwiftUI dismiss environment, so the caller does not need
    /// to thread anything explicitly.
    ///
    /// Example:
    ///
    ///     .sheet(isPresented: $showWeekly) {
    ///         DriverWeeklyPlan().eusoSheetX()
    ///     }
    func eusoSheetX() -> some View {
        modifier(EusoSheetXModifier())
    }

    /// Adds JUST the canonical close X to the top-right corner of a
    /// sheet body — no detent or drag-indicator changes. Use when the
    /// sheet has its own custom detents (e.g. `.medium`) that should
    /// not be overridden by `eusoSheetX()`'s `.large` default.
    ///
    /// Example:
    ///
    ///     .sheet(item: $detail) { row in
    ///         RowDetailSheet(row: row)
    ///             .presentationDetents([.medium])
    ///             .eusoCloseX()
    ///     }
    func eusoCloseX() -> some View {
        modifier(EusoCloseXModifier())
    }
}

// MARK: - Auto-X overlay modifier

/// Adds the canonical `SheetCloseButton` to the top-trailing edge of a
/// sheet body and applies the standard detents + drag indicator. Reads
/// the SwiftUI `dismiss` environment internally so call sites stay
/// one-liners.
// 2026-04-25 retraction: the auto-overlay variants of these modifiers
// were collapsed because the batch sweep that added them double-stamped
// SheetCloseButton on screens that already render their own header X
// (Authority, Documents Center, Rate Sheets, Safety Coach orb collision,
// AddPaymentAccountSheet → Stripe ready / Plaid Link). The modifiers now
// behave as pure detent helpers — call sites compile unchanged but no
// longer paint a second X. Re-introduce per-screen X overlays surgically
// (one screen at a time, by hand) using the `SheetCloseButton` primitive
// directly when a sheet truly lacks any close affordance.
private struct EusoSheetXModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }
}

private struct EusoCloseXModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

// MARK: - BespokeBackBar (the unified top back affordance)
//
// The canonical TOP-of-screen back control for PUSHED detail screens
// (sheet→push conversions per the 2026-05-30 NAV remediation spec).
// It is the in-stack sibling of `SheetCloseButton`:
//
//   • SheetCloseButton (X, top-right)  → dismisses a *modal sheet*.
//   • BespokeBackBar  (chevron, top-left + title) → pops a *pushed*
//     detail back to its caller via the role's NavBack notification.
//
// Layout contract (founder hard constraint — "back must NEVER overlap
// the title"): the back control is a FIXED-WIDTH leading element
// (`backSlot` pt). The title is centered in the remaining space with a
// symmetric trailing spacer of the same fixed width, so the title's
// optical center is the bar center and it can never slide under the
// chevron. With a long title the center block truncates with an
// ellipsis well clear of the chevron.
//
// This bar is role-agnostic: the caller supplies `onBack` (which posts
// the role's correct `eusoXxxNavBack`), so every role surface reuses
// the identical structure the IA spec requires.
//
// BottomNav is untouched (founder mandate) — this lives only at the
// top of the pushed content.

struct BespokeBackBar: View {
    @Environment(\.palette) private var palette
    @State private var pressed: Bool = false

    /// Page title shown centered in the bar. Pass `nil`/empty on
    /// screens that already paint a strong eyebrow+title so the bar
    /// renders chevron-only (avoids the title-collision the floating
    /// overlay used to cause).
    let title: String?
    /// Fires the role's NavBack. The bar adds the canonical §B.4 haptic
    /// before invoking; the surface owns the pop animation, so `onBack`
    /// should NOT animate (avoids double-animation).
    let onBack: () -> Void

    /// Fixed leading + trailing slot width. The chevron lives in the
    /// leading slot; an equal-width invisible trailing slot keeps the
    /// centered title optically centered without overlapping the back.
    private let backSlot: CGFloat = 56

    var body: some View {
        ZStack {
            // Centered title — bounded by symmetric fixed insets so it
            // can never reach the chevron.
            if let title, !title.isEmpty {
                Text(title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, backSlot)
                    .accessibilityAddTraits(.isHeader)
            }

            HStack(spacing: 0) {
                // Leading fixed-width back slot.
                Button(action: {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    onBack()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 44, height: 44)   // HIG hit target
                        .background(Circle().fill(palette.bgCardSoft))
                        .overlay(Circle().strokeBorder(palette.borderFaint))
                        .scaleEffect(pressed ? 0.92 : 1.0)
                        .animation(.easeOut(duration: 0.12), value: pressed)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in pressed = true }
                        .onEnded   { _ in pressed = false }
                )
                .frame(width: backSlot, alignment: .leading)

                Spacer(minLength: 0)

                // Trailing fixed-width mirror slot keeps the centered
                // title balanced. Empty by design — the X close lives
                // on sheets, not on pushed screens (never both).
                Color.clear
                    .frame(width: backSlot, height: 44)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 52)
        .padding(.horizontal, Space.s3)
        .background(palette.bgPage)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.borderFaint)
                .frame(height: 1)
        }
    }
}

extension View {
    /// Inject the canonical `BespokeBackBar` above a PUSHED detail
    /// screen. The bar pins to the top; the screen body fills below it.
    /// Use this on the root of any view that a role surface renders
    /// in-stack (slide-in-from-right) instead of in a `.sheet`.
    ///
    ///     SomeDetailBody()
    ///         .injectBespokeBackBar(title: "Contract") {
    ///             NotificationCenter.default.post(
    ///                 name: .eusoShipperNavBack, object: nil)
    ///         }
    ///
    /// Pass `title: nil` when the body already shows a strong title.
    /// `onBack` must post the role's correct NavBack notification.
    func injectBespokeBackBar(
        title: String? = nil,
        onBack: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            BespokeBackBar(title: title, onBack: onBack)
            self
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Preview

#Preview("Bespoke Back Bar · Dark") {
    ZStack {
        Theme.dark.bgPage.ignoresSafeArea()
        VStack(spacing: 0) {
            BespokeBackBar(title: "Contract · EUSO-2120 Volume Commitment That Is Very Long") {}
            BespokeBackBar(title: "Live Tracking") {}
            BespokeBackBar(title: nil) {}
            Spacer()
        }
        .environment(\.palette, Theme.dark)
    }
    .preferredColorScheme(.dark)
}

#Preview("Sheet Close Button · Dark") {
    ZStack {
        Theme.dark.bgPage.ignoresSafeArea()
        VStack(spacing: 24) {
            HStack {
                BackChevron {}
                Spacer()
                SheetCloseButton {}
            }
            .padding()
            Spacer()
        }
        .environment(\.palette, Theme.dark)
    }
    .preferredColorScheme(.dark)
}
