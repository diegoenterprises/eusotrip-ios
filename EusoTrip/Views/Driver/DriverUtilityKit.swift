//
//  DriverUtilityKit.swift
//  EusoTrip — shared chrome for the Driver utility/status screens
//  (169 Tolls · 170 Weigh Bypass · 171 Parking · 173 Clearinghouse ·
//   177 Cash Advance · 178 Drug Test · 179 Fuel Economy).
//
//  These screens share a house-standard status TopBar (eyebrow + title +
//  optional right meta cluster + back affordance), a loading state, an error
//  state, and the real Driver BottomNav slot set. Defined once here so the
//  screens stay purpose-built in their bodies without re-declaring chrome.
//
//  No data of its own — pure presentation. Binds Theme.Palette via the
//  environment exactly like the flagships.
//
//  BACK AFFORDANCE: these screens mount as `Shell` roots (a ZStack +
//  ScrollView — no NavigationStack, no sheet), so a bare `dismiss()` is a
//  documented no-op. When the screen is pushed onto the Driver Me stack the
//  real pop verb is `.eusoDriverMeNavBack` (owned by `DriverMeSurface`).
//  The chevron therefore posts that notification AND calls `dismiss()`, so
//  one control works in both contexts and neither path is inert. Screens
//  using this header must be listed in `DriverMeSurface.driverScreensWithOwnBack`
//  so the surface does not stack a second chevron over this one.
//
//  RIGHT META CLUSTER: `rightTop` / `rightBottom` render ONLY when non-empty.
//  They previously carried a hardcoded persona string, which painted one
//  fabricated driver's name + CDL into every signed-in driver's chrome; the
//  call sites now pass "" until a real signed-in identity is bound.
//

import SwiftUI

// MARK: - Status TopBar

struct DriverUtilityHeader: View {
    let eyebrow: String
    let caption: String
    let title: String
    let subtitle: String
    /// Optional right-rail meta. Rendered only when non-empty — never a
    /// stand-in persona.
    var rightTop: String = ""
    var rightBottom: String = ""

    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                EusoTripEyebrow(verbatim: eyebrow)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(caption)
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top, spacing: Space.s3) {
                Button {
                    // Pop the Driver Me stack (the real verb when this screen
                    // is pushed by DriverMeSurface), then dismiss for any
                    // sheet/push context. Exactly one of the two acts.
                    NotificationCenter.default.post(name: .eusoDriverMeNavBack, object: nil)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(palette.bgCard)
                        .overlay(Circle().strokeBorder(palette.borderFaint))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(EType.h2).foregroundStyle(palette.textPrimary)
                    Text(subtitle).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                // Right rail renders only when the caller has real meta to
                // show. Empty = nothing, never a placeholder identity.
                if !rightTop.isEmpty || !rightBottom.isEmpty {
                    VStack(alignment: .trailing, spacing: 3) {
                        if !rightTop.isEmpty {
                            Text(rightTop).font(EType.micro).tracking(0.6)
                                .foregroundStyle(palette.textTertiary)
                        }
                        if !rightBottom.isEmpty {
                            Text(rightBottom).font(EType.mono(.caption))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }
}

// MARK: - Loading / Error

struct DriverUtilityLoading: View {
    let text: String
    @Environment(\.palette) var palette
    var body: some View {
        VStack(spacing: Space.s3) {
            ProgressView().tint(palette.textPrimary)
            Text(text).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

struct DriverUtilityError: View {
    let message: String
    let retry: () -> Void
    @Environment(\.palette) var palette
    var body: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26, weight: .semibold)).foregroundStyle(Brand.warning)
            Text(message).font(EType.body).foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center).padding(.horizontal, Space.s6)
            Button("Try again", action: retry)
                .font(EType.bodyStrong).foregroundStyle(LinearGradient.diagonal)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

// MARK: - Empty-state strip

struct DriverUtilityEmpty: View {
    let systemImage: String
    let title: String
    let detail: String
    @Environment(\.palette) var palette
    var body: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular)).foregroundStyle(palette.textTertiary)
            Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text(detail).font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s6)
        .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
    }
}

// MARK: - Driver nav slot sets (real DriverTab enum · frozen)

func driverUtilityNavLeading(tripsCurrent: Bool = false) -> [NavSlot] {
    [ NavSlot(label: "Home",  systemImage: "house", isCurrent: false),
      NavSlot(label: "Trips", systemImage: "truck.box", isCurrent: tripsCurrent) ]
}
func driverUtilityNavTrailing(meCurrent: Bool = false) -> [NavSlot] {
    [ NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
      NavSlot(label: "Me",    systemImage: "person", isCurrent: meCurrent) ]
}
