//
//  DriverUtilityKit.swift
//  EusoTrip — shared chrome for the Driver utility/status screens
//  (169 Tolls · 170 Weigh Bypass · 171 Parking · 173 Clearinghouse ·
//   177 Cash Advance · 178 Drug Test · 179 Fuel Economy).
//
//  These screens share a house-standard status TopBar (eyebrow + title +
//  right persona cluster + back affordance), a loading state, an error
//  state, and the real Driver BottomNav slot set. Defined once here so the
//  screens stay purpose-built in their bodies without re-declaring chrome.
//
//  No data of its own — pure presentation. Binds Theme.Palette via the
//  environment exactly like the flagships.
//

import SwiftUI

// MARK: - Status TopBar

struct DriverUtilityHeader: View {
    let eyebrow: String
    let caption: String
    let title: String
    let subtitle: String
    let rightTop: String
    let rightBottom: String

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
                Button { dismiss() } label: {
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
                VStack(alignment: .trailing, spacing: 3) {
                    Text(rightTop).font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(rightBottom).font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
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
