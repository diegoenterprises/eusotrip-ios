//
//  DriverComplianceKit.swift
//  EusoTrip — shared chrome for the Driver compliance/commodity detail screens
//  (190 Itinerary · 194 Livestock 28-Hour · 195 HHG Custody · 196 Auto VIN
//   Damage · 197 Heavy-Haul Bridge · 198 Gate Identity Bind ·
//   198B Liveness Challenge · 199B Lumper Reimbursement).
//
//  These screens share the golden DETAIL TopBar (one ✦ eyebrow + right mono
//  caption · circle back affordance · 28pt title · mono subtitle · right
//  label/value cluster), a section-card container, a compliance gate row, and
//  the real Driver BottomNav slot set. Defined once here so each screen stays
//  purpose-built in its body without re-declaring chrome. Loading / error /
//  empty states are reused from DriverUtilityKit.
//
//  Pure presentation — no data of its own. Binds Theme.Palette via the
//  environment exactly like the flagships. Sole author: Mike "Diego" Usoro /
//  Eusorone Technologies, Inc.
//
//  BACK AFFORDANCE: these screens mount as `Shell` roots (a ZStack +
//  ScrollView — no NavigationStack, no sheet), so a bare `dismiss()` is a
//  documented no-op. When the screen is pushed onto the Driver Me stack the
//  real pop verb is `.eusoDriverMeNavBack` (owned by `DriverMeSurface`). The
//  chevron posts that notification AND calls `dismiss()`, so one control works
//  in both contexts and neither path is inert. Screens using this header must
//  be listed in `DriverMeSurface.driverScreensWithOwnBack` so the surface does
//  not stack a second, redundant chevron over this one.
//

import SwiftUI

// MARK: - DETAIL TopBar (eyebrow + circle back + 28pt title + right cluster)

struct DriverComplianceHeader: View {
    let eyebrow: String
    /// Right-aligned mono caption on the eyebrow row (e.g. "49 USC 80502").
    let caption: String
    let title: String
    /// Mono subtitle under the title (load number · facility).
    let subtitle: String
    /// Small-caps right label above the value (e.g. "FWR DUE").
    let rightLabel: String
    /// Mono value under the right label (e.g. "in 5h 12m").
    let rightValue: String

    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                EusoTripEyebrow(verbatim: eyebrow)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: Space.s3)
                Text(caption)
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold)).tracking(-0.4)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(subtitle)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(rightLabel).font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(rightValue).font(EType.mono(.caption)).fontWeight(.semibold)
                        .foregroundStyle(palette.textSecondary)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }
}

// MARK: - Section card (small-caps label + trailing accessory + content)

struct ComplianceSection<Content: View>: View {
    let label: String
    var trailing: String? = nil
    var trailingColor: Color? = nil
    var intensity: EusoCardIntensity = .standard
    @ViewBuilder var content: () -> Content

    @Environment(\.palette) var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                if let trailing {
                    Text(trailing).font(EType.micro).tracking(0.6).fontWeight(.bold)
                        .foregroundStyle(trailingColor ?? palette.textTertiary)
                }
            }
            content()
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg, intensity: intensity)
    }
}

// MARK: - Compliance gate row (tint icon chip · title/sub · right status)

struct ComplianceGateRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let subtitle: String
    let status: String
    var statusColor: Color? = nil

    @Environment(\.palette) var palette

    var body: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.md))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            Text(status.uppercased())
                .font(EType.micro).tracking(0.6).fontWeight(.bold)
                .foregroundStyle(statusColor ?? tint)
                .fixedSize()
        }
    }
}

// MARK: - Honest gap note (matches 169's "not yet wired" surface)

struct ComplianceGapNote: View {
    let systemImage: String
    let title: String
    let detail: String
    @Environment(\.palette) var palette

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(detail).font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
    }
}

// MARK: - Driver nav slot sets (real DriverTab enum · frozen · any tab current)

enum DriverNavCurrent { case home, trips, loads, me }

func driverComplianceNavLeading(_ current: DriverNavCurrent) -> [NavSlot] {
    [ NavSlot(label: "Home",  systemImage: "house",     isCurrent: current == .home),
      NavSlot(label: "Trips", systemImage: "truck.box", isCurrent: current == .trips) ]
}
func driverComplianceNavTrailing(_ current: DriverNavCurrent) -> [NavSlot] {
    [ NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: current == .loads),
      NavSlot(label: "Me",    systemImage: "person",           isCurrent: current == .me) ]
}
