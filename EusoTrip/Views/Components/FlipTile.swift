//
//  FlipTile.swift
//  EusoTrip — the ONE shared 3D flip primitive (Views/Components).
//
//  Lifted verbatim from the Hot Zones inline flip geometry
//  (225_ShipperHotZones.swift:618–642) and promoted to a single
//  reusable container so Hot / Cold / Intensity / Market all flip with
//  IDENTICAL physics instead of each re-deriving the rotation math.
//
//  Division of labor — `FlipTile` owns ONLY the geometry:
//    • the two faces are stacked in a `ZStack`; only the active face is
//      opaque, and the back is pre-rotated 180° so it reads upright once
//      the container reaches 180°;
//    • the container `rotation3DEffect` carries the perspective; and
//    • `accessibilityHidden` follows the visible face so VoiceOver never
//      reads the hidden side.
//
//  The CALLER owns everything else — the tap gesture, the
//  `withAnimation(.spring(response: 0.5, dampingFraction: 0.78))` toggle,
//  the `.sensoryFeedback(.selection, trigger:)`, and the per-element
//  `Set<String>` keyed by `id` that decides which tiles are flipped.
//  That keeps this primitive dependency-free: no palette, no store, no
//  model — the parents own all styling.
//
//  Reduce Motion: when the system asks for reduced motion we skip the 3D
//  rotation entirely and simply crossfade the two faces via opacity, so
//  the spinning-card vestibular trigger never fires.
//
//  Powered by ESANG AI™.
//

import SwiftUI

/// A two-faced tile that rotates in 3D to reveal its back. The owner
/// flips it by toggling `isFlipped` inside a `withAnimation { … }`; the
/// tile carries no internal flip state of its own.
struct FlipTile<Front: View, Back: View>: View {

    /// Driven by the caller's per-element flip `Set<String>`. When this
    /// flips, the parent's `withAnimation` animates the rotation.
    let isFlipped: Bool

    /// Rotation axis. Defaults to the Hot Zones horizontal flip
    /// (x: 1) — pass `(0, 1, 0)` for a vertical flip if a surface wants it.
    var axis: (x: CGFloat, y: CGFloat, z: CGFloat) = (1, 0, 0)

    /// The face shown when `isFlipped == false`.
    @ViewBuilder var front: () -> Front

    /// The face shown when `isFlipped == true`. Rendered pre-rotated 180°
    /// so its content is not mirrored when the container lands at 180°.
    @ViewBuilder var back: () -> Back

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            // Reduced motion — no 3D rotation. Crossfade the two faces so
            // the spinning-card vestibular trigger never fires. The back
            // is NOT pre-rotated here because there is no container flip
            // to un-mirror it against.
            ZStack {
                front()
                    .opacity(isFlipped ? 0 : 1)
                    .accessibilityHidden(isFlipped)
                back()
                    .opacity(isFlipped ? 1 : 0)
                    .accessibilityHidden(!isFlipped)
            }
            .contentShape(Rectangle())
        } else {
            ZStack {
                front()
                    .opacity(isFlipped ? 0 : 1)
                    .accessibilityHidden(isFlipped)
                back()
                    .opacity(isFlipped ? 1 : 0)
                    .accessibilityHidden(!isFlipped)
                    .rotation3DEffect(.degrees(180), axis: axis)   // pre-un-mirror the back
            }
            .rotation3DEffect(
                .degrees(isFlipped ? 180 : 0),
                axis: axis,
                perspective: 0.5
            )
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Preview

#Preview("FlipTile — light + dark") {
    /// Minimal caller harness: owns the flip `Set` + the spring toggle,
    /// exactly as the real surfaces do, so the preview exercises the same
    /// contract the production callers use.
    struct Demo: View {
        @State private var flipped: Set<String> = []

        private func card(_ id: String, _ scheme: ColorScheme) -> some View {
            FlipTile(isFlipped: flipped.contains(id)) {
                VStack(spacing: 6) {
                    Text("FRONT")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    Text("tap to flip")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.95))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } back: {
                VStack(spacing: 6) {
                    Text("BACK")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    Text("drill-down detail")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.accentColor.opacity(scheme == .dark ? 0.30 : 0.18))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .frame(height: 110)
            .onTapGesture {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                    if flipped.contains(id) { flipped.remove(id) }
                    else { flipped.insert(id) }
                }
            }
            .sensoryFeedback(.selection, trigger: flipped.contains(id))
            .padding()
        }

        var body: some View {
            VStack(spacing: 20) {
                card("light", .light)
                    .environment(\.colorScheme, .light)
                    .background(Color.white)
                card("dark", .dark)
                    .environment(\.colorScheme, .dark)
                    .background(Color.black)
            }
            .padding()
        }
    }
    return Demo()
}
